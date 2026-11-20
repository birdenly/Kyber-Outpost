// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <Network/UDPSocket.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Network/SocketManager.h>
#include <Utilities/ErrorUtils.h>
#include <Utilities/PlatformUtils.h>
#include <Utilities/StringUtils.h>
#include <SDK/Funcs.h>

#include <ws2tcpip.h>

namespace Kyber
{
static bool IsLanAddress(const sockaddr_in& address)
{
    const uint32_t ip = ntohl(address.sin_addr.s_addr);
    return (ip & 0xFF000000) == 0x7F000000 || // Loopback
        (ip & 0xFF000000) == 0x0A000000 || // 10.0.0.0/8
        (ip & 0xFF000000) == 0x19000000 || // Hamachi: 25.0.0.0/8
        (ip & 0xFF000000) == 0x1A000000 || // Radmin VPN: 26.0.0.0/8
        (ip & 0xFFF00000) == 0xAC100000 || // 172.16.0.0/12
        (ip & 0xFFFF0000) == 0xC0A80000 || // 192.168.0.0/16
        (ip & 0xFFFF0000) == 0xA9FE0000 || // Link local
        (ip & 0xFFC00000) == 0x64400000; // Shared address space used by VPNs
}

std::string DirectionToString(ProtocolDirection direction)
{
    switch (direction)
    {
    case ProtocolDirection::Serverbound:
        return "Client";
    case ProtocolDirection::Clientbound:
        return "Server";
    }

    return "";
}

UDPSocket::UDPSocket(SocketCreator* creator, ProtocolDirection direction, SocketSpawnInfo info)
    : m_creator(creator)
    , m_socketHandle(INVALID_SOCKET)
    , m_port(0)
    , m_isBroadcasting(false)
    , m_blockingMode(false)
    , m_peerAddressIsValid(false)
    , m_direction(direction)
    , m_info(info)
{
    m_info.isProxied = false;
}

UDPSocket::~UDPSocket() {}

void UDPSocket::Close()
{
    KYBER_LOG(Info, "[" << DirectionToString(m_direction) << "] Closing socket");

    if (m_socketHandle != INVALID_SOCKET)
    {
        shutdown(m_socketHandle, SD_BOTH);
        closesocket(m_socketHandle);
    }

    m_socketHandle = INVALID_SOCKET;
}

bool UDPSocket::Send(uint8_t* buffer, int bufferSize, unsigned int flags)
{
    sockaddr* addr = (sockaddr*)m_peerAddress.Data();
    if (!IsLanAddress(*reinterpret_cast<sockaddr_in*>(addr)))
    {
        return false;
    }

    if (sendto(m_socketHandle, reinterpret_cast<const char*>(buffer), bufferSize, 0, addr, sizeof(sockaddr_in)) < 0)
    {
        int error = WSAGetLastError();
        if (error != WSAEWOULDBLOCK)
        {
            KYBER_LOG(Error, "[" << DirectionToString(m_direction) << "] Failed to send data: " << error);
            return false;
        }

        return true;
    }

#ifdef _DEBUG
    KYBER_LOG(Trace, "[" << DirectionToString(m_direction) << "] Sent " << bufferSize << " bytes");
#endif

    return true;
}

int UDPSocket::ReceiveFromWhen(uint8_t* buffer, int bufferSize, unsigned int& when)
{
    int addressSize = sizeof(sockaddr_in);
    sockaddr_in addr = *(sockaddr_in*)m_peerAddress.Data();

    if (m_socketHandle == INVALID_SOCKET)
    {
        KYBER_LOG(Error, "Invalid socket handle");
        return -1;
    }

    when = NetTick();
    int recvSize = recvfrom(m_socketHandle, (char*)buffer, bufferSize, 0, (sockaddr*)&addr, &addressSize);
    if (recvSize < 0)
    {
        int error = WSAGetLastError();
        if (error != WSAEWOULDBLOCK)
        {
            KYBER_LOG(Debug, "Error receiving data: " << error);
        }

        return recvSize;
    }

    if (!IsLanAddress(addr))
    {
        return 0;
    }

    m_peerAddress.SetData(&addr, sizeof(sockaddr_in));
    m_peerAddressIsValid = true;

#ifdef _DEBUG
    KYBER_LOG(Trace, "[" << DirectionToString(m_direction) << "] Received " << recvSize << " bytes");
#endif

    return recvSize;
}

bool UDPSocket::Listen(const SocketAddr& address, bool blocking)
{
    m_socketHandle = INVALID_SOCKET;

    sockaddr_in* addr = (sockaddr_in*)address.Data();
    if ((m_socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == INVALID_SOCKET)
    {
        KYBER_LOG(Error, "Failed to create socket (" << WSAGetLastError() << ")");
        return false;
    }

    if (bind(m_socketHandle, (sockaddr*)addr, sizeof(sockaddr_in)) != 0)
    {
        int error = WSAGetLastError();
        Close();
        KYBER_LOG(Error, "Failed to bind socket (" << error << ")");
        return false;
    }

    if (!SetBlockingMode(blocking))
    {
        Close();
        KYBER_LOG(Error, "Failed to set blocking mode of socket");
        return false;
    }

    m_port = ntohs(addr->sin_port);
    m_address = address;

    KYBER_LOG(Trace, "Created listening socket");

    return true;
}

bool UDPSocket::Connect(const SocketAddr& address, bool blocking)
{
    return false;
}

bool UDPSocket::Create(bool blocking)
{
    return false;
}

bool UDPSocket::SetBlockingMode(bool blocking)
{
    m_blockingMode = blocking;
    if (m_socketHandle == INVALID_SOCKET)
    {
        return true;
    }

    u_long mode = blocking ? 0 : 1;
    if (ioctlsocket(m_socketHandle, FIONBIO, &mode) == SOCKET_ERROR)
    {
        return false;
    }

    int bufferSize = 600000;
    if (setsockopt(m_socketHandle, SOL_SOCKET, SO_SNDBUF, (char*)&bufferSize, sizeof(bufferSize)) == SOCKET_ERROR)
    {
        return false;
    }

    if (setsockopt(m_socketHandle, SOL_SOCKET, SO_RCVBUF, (char*)&bufferSize, sizeof(bufferSize)) == SOCKET_ERROR)
    {
        return false;
    }

    return true;
}

void UDPSocket::SetPeerAddress(const SocketAddr& address)
{
    m_peerAddress = address;
    m_peerAddressIsValid = true;
}

SocketAddr UDPSocket::PeerAddress() const
{
    return m_peerAddress;
}

bool UDPSocket::SetBroadcast(uint16_t port)
{
    KYBER_LOG(Trace, "Setting broadcast port to " << port);
    return false;
}

bool UDPSocket::BlockingMode() const
{
    return false;
}

intptr_t UDPSocket::NativeSocket() const
{
    return m_socketHandle;
}

int UDPSocket::Port() const
{
    return m_port;
}

const SocketAddr* UDPSocket::Address() const
{
    return &m_address;
}

bool UDPSocket::SetDefaultPacketInfo(PacketInfo* info)
{
    if (!info)
    {
        KYBER_LOG(Error, "Invalid packet info");
        return false;
    }

    info->minSize = 1;
    info->maxSize = 1264;
    info->recommendedSize = info->maxSize;
    info->overheadWhenAligned = 28;
    info->alignment = 1;
    return true;
}
} // namespace Kyber
