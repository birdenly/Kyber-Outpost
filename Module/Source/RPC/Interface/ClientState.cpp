// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
#include <RPC/Interface/ClientState.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Utilities/StringUtils.h>

#include <grpcpp/support/status.h>

namespace Kyber
{
using grpc::Status;

using namespace kyber_interface;

ServerUnaryReactor* ClientInterfaceService::JoinServer( 
    CallbackServerContext* context, const JoinServerRequest* request, kyber_common::Empty* response)
{
    g_program->m_client->m_joinToken = request->jointoken();
    g_program->m_client->JoinServer(request->id(), request->ip(), request->port(), request->spectate(),
        request->type() == kyber_interface::JoinServerType::PROXIED, true);

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ClientInterfaceService::SetVoipSettings(CallbackServerContext* context,
    const kyber_interface::SetVoipSettingsRequest* request, kyber_common::Empty* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ClientInterfaceService::GetVoipSettings(CallbackServerContext* context,
    const kyber_common::Empty* request, kyber_interface::VoipSettings* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}
} // namespace Kyber
