// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.
// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.

#define _WINSOCKAPI_

#include <RPC/API.h>

#include <Utilities/PlatformUtils.h>

#include <errhandlingapi.h>
#include <grpc++/alarm.h>
#include <grpcpp/create_channel.h>
#include <grpcpp/security/credentials.h>

#include <grpc/grpc.h>
#include <memory>
#include <wincrypt.h>

namespace Kyber
{
std::string Utf8Encode(const std::wstring& wstr)
{
	if (wstr.empty())
		return std::string();

	int sizeNeeded = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
	std::string strTo(sizeNeeded, 0);
	WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], sizeNeeded, NULL, NULL);
	return strTo;
}

grpc::SslCredentialsOptions GetSslOptions()
{
	grpc::SslCredentialsOptions result;

    std::ifstream certFile(PlatformUtils::GetModulePath() / "ca_root.pem");
    if (!certFile.is_open())
    {
        KYBER_LOG(Error, "Failed to open root certificate file");
        return result;
    }

    std::stringstream certBuffer;
    certBuffer << certFile.rdbuf();

    result.pem_root_certs = certBuffer.str();
	return result;
}

void ListenToStateChanges(const std::shared_ptr<grpc::Channel>& channel) {
    auto state = channel->GetState(true);

    while (true) {
        std::chrono::system_clock::time_point deadline = std::chrono::system_clock::now() + std::chrono::seconds(60);
        channel->WaitForStateChange(state, deadline);

		auto newState = channel->GetState(false);
		if (newState == state)
		{
			continue;
		}

		if (newState == GRPC_CHANNEL_TRANSIENT_FAILURE)
		{
			KYBER_LOG(Error, "gRPC entered transient failure state!");
		}
		else if (state == GRPC_CHANNEL_TRANSIENT_FAILURE && newState == GRPC_CHANNEL_CONNECTING)
		{
			KYBER_LOG(Warning, "Attempting gRPC reconnection...");
		}

		state = newState;
    }
}

API::API(std::string token)
{
    // This build only creates the local Launcher channel.
    std::string launcherPort = PlatformUtils::GetEnv("KYBER_LAUNCHER_PORT");
    std::shared_ptr<Channel> launcherChannel = grpc::CreateChannel("127.0.0.1:" + launcherPort, grpc::InsecureChannelCredentials());
    m_launcherInterface = std::make_unique<LauncherInterface>(launcherChannel, &m_asyncManager);
}

void API::Update() const
{
    m_asyncManager.Update();
}
} // namespace Kyber
