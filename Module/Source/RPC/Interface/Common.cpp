// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <RPC/Interface/Common.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <grpcpp/support/status.h>

#include <FastDelegate.h>
#include <mutex>

namespace Kyber
{
using grpc::Status;
using grpc::StatusCode;

using namespace kyber_interface;

ServerUnaryReactor* CommonInterfaceService::GetInfo(
    CallbackServerContext* context, const kyber_common::Empty* request, kyber_interface::CommonState* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    if (g_program == nullptr)
    {
        reactor->Finish(Status(StatusCode::UNAVAILABLE, "Kyber is still initializing"));
        return reactor;
    }
    {
        // The interface starts before the client/server are constructed. The
        // startup flag publishes their initialization under this same mutex.
        std::lock_guard<std::mutex> lock(g_program->m_startupMutex);
        if (!g_program->m_startupInitialized || g_program->m_server == nullptr || g_program->m_client == nullptr)
        {
            reactor->Finish(Status(StatusCode::UNAVAILABLE, "Kyber is still initializing"));
            return reactor;
        }
    }

    if (g_program->m_server->IsRunning() && g_program->m_server->m_serverInstance != nullptr)
    {
        kyber_interface::ServerState* server = response->mutable_server();
        server->set_id(g_program->m_server->m_serverId);

        server->mutable_levelsetup()->set_map(g_program->m_server->m_currentLevel);
        server->mutable_levelsetup()->set_mode(g_program->m_server->m_currentMode);

        server->set_maprotationindex(0);

        for (ServerPlayer* player : g_program->m_server->m_playerManager->m_players)
        {
            if (player->IsAIPlayer())
            {
                continue;
            }

            kyber_common::ServerPlayer* protoPlayer = server->add_playerlist();
            protoPlayer->set_id(std::to_string(player->m_onlineId.m_nativeData));
            protoPlayer->set_name(player->m_name);
            protoPlayer->set_teamid(player->m_teamId);
        }
    }
    else if (g_program->m_client->m_connected)
    {
        response->mutable_client()->set_serverid(g_program->m_server->m_socketSpawnInfo.serverName);
    }

    response->set_vivoxinitialized(false);

    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* CommonInterfaceService::RunCommand(
    CallbackServerContext* context, const kyber_interface::RunCommandRequest* request, kyber_common::Empty* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    auto delegate = fastdelegate::FastDelegate<void(const char*)>([](const char* result) {
        if (strlen(result) == 0)
        {
            return;
        }

        KYBER_LOG(Info, "[Console] Result: " << result);
    });
    Console_enqueueCommand(request->command().c_str(), delegate);

    reactor->Finish(Status::OK);
    return reactor;
}

} // namespace Kyber
