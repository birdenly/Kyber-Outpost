// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.
// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.

#define _WINSOCKAPI_

#include <RPC/API.h>

#include <Utilities/PlatformUtils.h>

#include <grpcpp/create_channel.h>
#include <grpcpp/security/credentials.h>

#include <memory>

namespace Kyber
{
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
