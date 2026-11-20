// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.
// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.

#include <Core/Server.h>

#include <Core/Program.h>
#include <Hook/HookManager.h>
#include <Base/Log.h>
#include <cstdlib>
#include <Utilities/MemoryUtils.h>
#include <SDK/TypeInfo.h>
#include <SDK/SDK.h>
#include <SDK/Funcs.h>
#include <Utilities/PlatformUtils.h>
#include <Utilities/StringUtils.h>
#include <Entity/KyberSettings.h>

#include <fstream>
#include <stdlib.h>
#include <ws2tcpip.h>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <cstdio>
#include <thread>
#include <cstring>

#define OFFSET_SERVER_CONSTRUCTOR HOOK_OFFSET(0x140BC6370)
#define OFFSET_SERVER_START HOOK_OFFSET(0x140BD17E0)
#define OFFSET_SERVER_UPDATEPASSPREFRAME HOOK_OFFSET(0x146860470)
#define OFFSET_SERVERLEVEL_UPDATELOAD HOOK_OFFSET(0x140BD3360)

#define OFFSET_SERVERPLAYER_SETTEAMID HOOK_OFFSET(0x140BE9C10)
#define OFFSET_SERVERPLAYER_LEAVEINGAME HOOK_OFFSET(0x146876310)
#define OFFSET_SERVERPLAYER_DISCONNECT HOOK_OFFSET(0x140BDDBE0)

#define OFFSET_SERVERPEER_DELETECONNECTION HOOK_OFFSET(0x146C3A900)

#define OFFSET_SERVERCONNECTION_DISCONNECT HOOK_OFFSET(0x140BF01D0)
#define OFFSET_SERVERCONNECTION_KICKPLAYER HOOK_OFFSET(0x14688DB50)
#define OFFSET_SERVERCONNECTION_ONCREATEPLAYERMESSAGE HOOK_OFFSET(0x140BF33B0)

#define OFFSET_SERVERPLAYERMANAGER_DELETEPLAYER HOOK_OFFSET(0x140BDD950)

#define OFFSET_APPLY_SETTINGS HOOK_OFFSET(0x1401B31B0)

#define OFFSET_SERVER_PATCH 0x140A92F71

namespace Kyber
{
void ServerLoadLevelMessagePostHk(LevelSetup* levelSetup, bool fadeOut, bool forceReloadResources)
{
    static const auto trampoline = HookManager::Call(ServerLoadLevelMessagePostHk);

    std::string initialStartPoint = levelSetup->InitialStartPoint ? levelSetup->InitialStartPoint : "";
    std::string initialSubLevel = levelSetup->InitialDSubLevel ? levelSetup->InitialDSubLevel : "";

    if (g_program->m_server != nullptr)
    {
        if (!g_program->m_server->m_levelLoaded)
        {
            MutexGuard<LoadLevelRequest> requestGuard = g_program->m_server->m_latestLoadLevelRequest.Lock();

            requestGuard->level = levelSetup->Name;
            requestGuard->mode = levelSetup->GetInclusionOption("GameMode");

            KYBER_LOG(Debug, "[Server] Put level setup in queue: " << requestGuard->level << " " << requestGuard->mode);
            return;
        }

        g_program->m_server->m_levelLoaded = false;
        g_program->m_server->m_mode3RoundHasSpawned = false;
        g_program->m_server->m_roundLoadedTime = std::chrono::steady_clock::now();
    }

    KYBER_LOG(Info, "[Server] Loading level " << levelSetup->Name << " [InitialStartPoint: " << initialStartPoint << ", InitialDSubLevel: "
                                              << initialSubLevel << ", LevelSetup: " << std::hex << levelSetup << "]");

    trampoline(levelSetup, fadeOut, forceReloadResources);
}

void InitLevelSetup(LevelSetup* levelSetup, const char* level, const char* mode, const char* startPoint, const char* initialSubLevel)
{
    KYBER_LOG(Info, "[Server] Loading level '" << level << "'"
                                               << " with mode '" << (mode != nullptr ? mode : "none") << "'");

    if (g_program->m_scriptManager != nullptr)
    {
        g_program->m_scriptManager->GetEventManager().Fire("Level:Loaded", level, mode);
    }

    g_program->m_server->m_currentLevel = level;
    g_program->m_server->m_currentMode = mode != nullptr ? mode : "";

    levelSetup->Init();
    levelSetup->Name = StringUtils::CopyWithArena(level);

    if (mode != nullptr)
    {
        levelSetup->SetInclusionOption("GameMode", mode);
    }
    else
    {
        return;
    }

    // Below is campaign map testing, breaks dedicated server start points
    if (strcmp(mode, "Campaign") != 0)
    {
        return;
    }

    if (strlen(initialSubLevel) != 0)
    {
        levelSetup->InitialStartPoint = StringUtils::CopyWithArena(startPoint);
    }

    levelSetup->InitialDSubLevel = StringUtils::CopyWithArena(initialSubLevel);
}

Server::Server()
    : m_socketManager()
    , m_playerManager(nullptr)
    , m_persistenceManager(new PersistenceManager())
    , m_eventManager(new EventManager())
    , m_squadManager(nullptr)
    , m_chatFilter(ChatFilter())
    , m_socketSpawnInfo(SocketSpawnInfo(false, "", "", ""))
    , m_serverInstance(nullptr)
    , m_runningHosted(false)
    , m_restarting(false)
    , m_hooksRemoved(false)
    , m_levelLoaded(false)
    , m_latestLoadLevelRequest(LoadLevelRequest())
{
    m_squadManager = new ServerSquadManager(m_eventManager);
    m_eventManager->RegisterListener<MainLoopInitStartServerEvent>(this);

    // Using the dirty sock socket manager makes KYBER servers compatible with non-kyber battlefront clients
    bool useDirtySockSocketManager = std::getenv("KYBER_USE_DIRTY_SOCK") != nullptr;
    if (useDirtySockSocketManager)
    {
        // Lazy loaded in InitDedicatedServer
        m_socketManager = nullptr;
    }
    else
    {
        m_socketManager = new SocketManager(ProtocolDirection::Clientbound, SocketSpawnInfo());
    }
}

Server::~Server()
{
    KYBER_LOG(Debug, "[Server] Destroying");
}

bool Server::IsRunning()
{
    return m_runningHosted || g_program->m_isDedicatedServer;
}

void Server::Initialize()
{
    InitializeGameHooks();

    // Spaghetti code alert. m_hooksRemoved changes if the sockmanager
    // gets pushed in the ctor of the server so we will keep this here so
    // it properly sets the custom sockmanager
    if (!g_program->m_isDedicatedServer)
    {
        m_hooksRemoved = true;
    }

    InitializeGamePatches();

    m_persistenceManager->Initialize();
}

void Server::Start(const ServerCreationInfo& info, bool changeState)
{
    EnableGameHooks();

    NetworkSettings* networkSettings = Settings<NetworkSettings>("Network");
    networkSettings->MaxClientCount = info.maxPlayers;
    // Each Launcher instance (split-screen on one PC) picks its own game port.
    uint16_t serverPort = 25200;
    if (const char* portVar = std::getenv("KYBER_SERVER_PORT"))
    {
        int parsed = atoi(portVar);
        if (parsed > 0 && parsed < 65536)
        {
            serverPort = static_cast<uint16_t>(parsed);
        }
    }
    networkSettings->ServerPort = serverPort;
    networkSettings->UseFrameManager = true;

    KYBER_LOG(Info, "[Server] Protocol Version " << networkSettings->ProtocolVersion << " TitleId " << networkSettings->TitleId);

    NetObjectSystemSettings* netObjectSettings = Settings<NetObjectSystemSettings>("NetObjectSystem");
    netObjectSettings->MaxServerConnectionCount = info.maxPlayers;
    // netObjectSettings->DeltaCompressionSettings.IsEnabled = false;

    ClientSettings* clientSettings = Settings<ClientSettings>("Client");
    clientSettings->FastExit = true;
    clientSettings->ServerIp = StringUtils::CopyWithArena("");

    GameSettings* gameSettings = Settings<GameSettings>("Game");
    gameSettings->Level = StringUtils::CopyWithArena(info.level);
    gameSettings->MaxSpectatorCount = 4;

    char* gameMode = StringUtils::CopyWithArena("GameMode=" + info.mode);
    gameSettings->DefaultLayerInclusion = gameMode;

    // Populate misc server details for potential usage in plugins
    ServerSettings* serverSettings = Settings<ServerSettings>("Server");
    serverSettings->ServerName = StringUtils::CopyWithArena(info.name.c_str());
    //serverSettings->ServerPassword = StringUtils::CopyWithArena(info.password.c_str());

    m_creationInfo = info;

    m_serverId = "lan_server";
    KYBER_LOG(Info, "[Server] Starting server in LAN mode on UDP port 25200");

    m_socketSpawnInfo = SocketSpawnInfo(false, "", m_serverId, "");

    if (m_runningHosted)
    {
        m_restarting = true;
    }

    if (changeState)
    {
        // Force
        m_levelLoaded = true;
        LoadNextLevel(info.level.c_str(), info.mode.c_str());
        // g_program->ChangeClientState(ClientState_Startup);
    }

    m_hooksRemoved = false;
    m_runningHosted = true;
}

void Server::KickPlayer(ServerPlayer* player, const char* reason)
{
    ServerConnection* serverConnection = GetServerGameContext()->m_serverPeer->GetConnectionForPlayer(player);
    serverConnection->SafeDisconnect(reason, SecureReason_KickedByAdmin);

    SendConsoleMessage(
        "Kicked " + std::string(player->m_name) + " (" + std::to_string(player->m_onlineId.m_nativeData) + ") from the server for reason: " + std::string(reason));
}

void Server::LoadNextLevel(
    const char* level, const char* mode, const char* startPoint, const char* initialSubLevel, bool updateServerBrowser)
{
    LevelSetup levelSetup;
    InitLevelSetup(&levelSetup, level, mode, startPoint, initialSubLevel);
    ServerLoadLevelMessage_post(&levelSetup, true, true);
}

void Server::OnLevelLoaded()
{
    m_levelLoaded = true;
    m_mode3RoundHasSpawned = false;
    m_roundLoadedTime = std::chrono::steady_clock::now();
    {
        MutexGuard<LoadLevelRequest> requestGuard = m_latestLoadLevelRequest.Lock();

        if (!requestGuard->level.empty())
        {
            LoadNextLevel(requestGuard->level.c_str(), requestGuard->mode.c_str());

            requestGuard->level = "";
            requestGuard->mode = "";
        }
    }

    KyberSettings* kyberSettings = Settings<KyberSettings>("Kyber");
    if (kyberSettings && kyberSettings->EnableShuffleTeams)
    {
        g_program->m_console->EnqueueCommand("Kyber.ShuffleTeams");
    }

    EnsureEwokHuntTeams();
}

const uint32_t kServerTeamAdminMarker = 19472;

bool ServerSendChatMessageHk(ChatChannel channel, const char* message, const ServerPlayer* player)
{
    static const auto trampoline = HookManager::Call(ServerSendChatMessageHk);
    if (message == nullptr || player == nullptr)
    {
        // uh oh?
        return false;
    }

    if (channel == ChatChannel_Admin && player->m_teamId != kServerTeamAdminMarker)
    {
        KYBER_LOG(Warning, "[Server] Player '" << player->m_name << "' (id: " << player->m_onlineId.m_nativeData
                                      << ") attempted to send admin chat message: " << message);
        return false;
    }

    if (g_program->m_scriptManager != nullptr && channel != ChatChannel_Admin)
    {
        g_program->m_scriptManager->GetEventManager().Fire("ServerPlayer:SendMessage", const_cast<ServerPlayer*>(player), message);
        if (g_program->m_scriptManager->GetEventManager().IsEventCancelled())
        {
            KYBER_LOG(Debug, "Lua event ServerPlayer:SendMessage cancelled");
            return false;
        }
    }

    return trampoline(channel, message, player);
}

void Server::BroadcastMessage(const std::string& message, const std::string& username, ChatChannel channel)
{
    char* dummyName = StringUtils::CopyWithArena(username, FB_SERVER_ARENA);

    ServerPlayer dummyPlayer;
    dummyPlayer.m_name = dummyName;
    dummyPlayer.m_teamId = kServerTeamAdminMarker;
    memset(dummyPlayer.m_onlineId.m_id, 0, sizeof(OnlineId::m_id));
    Server_sendChatMessage(channel, message.c_str(), &dummyPlayer);

    FB_SERVER_ARENA->free(dummyName);
}

void Server::SendChatMessage(ServerPlayer* player, const std::string& message)
{
    ServerPlayer dummyPlayer;
    dummyPlayer.m_name = "";
    dummyPlayer.m_teamId = kServerTeamAdminMarker;
    memset(dummyPlayer.m_onlineId.m_id, 0, sizeof(OnlineId::m_id));

    ServerConnection* serverConnection = GetServerGameContext()->m_serverPeer->GetConnectionForPlayer(player);
    serverConnection->SendChatMessage(ChatChannel_Admin, message.c_str(), dummyPlayer.m_onlineId);
}

// Unused
void Server::SetDedicatedCreationInfo(const ServerCreationInfo& info)
{
    if (!g_program->m_isDedicatedServer)
    {
        return;
    }

    m_creationInfo = info;
}

__int64 ServerCtorHk(void* inst, ServerSpawnInfo& info, SocketManager* socketManager)
{
    static const auto trampoline = HookManager::Call(ServerCtorHk);

    if (g_program->m_server->m_hooksRemoved)
    {
        return trampoline(inst, info, socketManager);
    }

    info.isLocalHost = false;

    if (g_program->m_isDedicatedServer)
    {
        ServerSettings* serverSettings = Settings<ServerSettings>("Server");
        serverSettings->ThreadingEnable = false;
        //  g_program->InitializeConsole();
    }

    g_program->m_server->m_playerManager = info.playerManager;
    g_program->m_server->m_serverInstance = inst;
    // Initial hosted starts select the level through GameSettings rather than
    // LoadNextLevel; publish the level actually being constructed as well.
    if (info.levelSetup.Name != nullptr)
    {
        g_program->m_server->m_currentLevel = info.levelSetup.Name;
    }
    if (const char* mode = info.levelSetup.GetInclusionOption("GameMode"))
    {
        g_program->m_server->m_currentMode = mode;
    }
    KYBER_LOG(Info, "[Server] Constructing a " << info.tickFrequency << "hz server " << info.levelSetup.Name);
    
    if (g_program->m_scriptManager != nullptr)
    {
        g_program->m_scriptManager->GetEventManager().Fire("Server:Init");
    }

    return trampoline(inst, info, socketManager);
}

__int64 ServerStartHk(__int64 inst, ServerSpawnInfo& info, __int64 spawnOverrides, SocketManager* socketManager)
{
    static const auto trampoline = HookManager::Call(ServerStartHk);
    Server* server = g_program->m_server;

    KYBER_LOG(Info, "[Server] Starting server " << info.levelSetup.Name << " (Hooked: " << !server->m_hooksRemoved << ")");

    if (server->m_hooksRemoved)
    {
        return trampoline(inst, info, spawnOverrides, socketManager);
    }

    if (!g_program->m_isDedicatedServer && server->m_socketManager != nullptr)
    {
        socketManager = server->m_socketManager;
        socketManager->m_info = server->m_socketSpawnInfo;
        KYBER_LOG(Info, "[Server] Server is using custom socket manager");
    }

    __int64 result = trampoline(inst, info, spawnOverrides, socketManager);

    if (server->m_runningHosted && !server->m_hooksRemoved)
    {
        server->m_hooksRemoved = true;
        server->DisableGameHooks();
    }

    KYBER_LOG(Info, "[Server] Server started");

    return result;
}

__int64 SettingsManagerApplyHk(__int64 inst, __int64* a2, char* script, BYTE* a4)
{
    static const auto trampoline = HookManager::Call(SettingsManagerApplyHk);
    __int64 result = trampoline(inst, a2, script, a4);

    Settings<MeshStreamingSettings>("MeshStreaming")->PoolSize = 999999;

    WSGameSettings* wsSettings = Settings<WSGameSettings>("Whiteshark");
    //wsSettings->NoInteractivityTimeoutTime = 30.f; // Kick after inactive for 120s

    // Setting designed for bot balancer to ensure that AutoBalanceTeamsOnNeutral is never true.
    KyberSettings* kyberSettings = Settings<KyberSettings>("Kyber");
    if (kyberSettings != nullptr)
    {
        bool enableTeamBalancing = !kyberSettings->DisableTeamBalancing;
        wsSettings->AutoBalanceTeamsOnNeutral = enableTeamBalancing;
    }

    static bool s_disableForceDx11 = std::getenv("KYBER_EXPERIMENTAL_DISABLE_FORCE_DX11") != nullptr;
    if (!s_disableForceDx11)
    {
        GameRenderSettings* renderSettings = Settings<GameRenderSettings>("Render");
        renderSettings->Dx11Enable = true;
        renderSettings->DLISPEnable = false;
        renderSettings->Dx12UseProfileOptionEnable = false;
        renderSettings->Dx12Enable = false;
        renderSettings->DxrEnable = 0;
        renderSettings->DynamicResolutionScaleTargetTime = -1; // other dx12 stuff
        renderSettings->DynamicResolutionMaxStepCount = 0;
        renderSettings->HdrLiveGradingOverlayOpacity = 0.f;
        renderSettings->HdrOutputPreferCs = false;
        renderSettings->DrawHdrCalibrationScreen = false;
    }

    GlobalPostProcessSettings* postProcessSettings = Settings<GlobalPostProcessSettings>("PostProcess");
    if (postProcessSettings != nullptr)
    {
        postProcessSettings->ScreenSpaceRaytraceQuality = 4;
        postProcessSettings->ScreenSpaceRaytraceFullresEnable = true;
        postProcessSettings->SpriteDofHalfResolutionEnable = false;
    }

    static bool s_disableForceNoHDR = std::getenv("KYBER_EXPERIMENTAL_DISABLE_FORCE_NOHDR") != nullptr;
    BaseDisplaySettings* renderDeviceSettings = Settings<BaseDisplaySettings>("RenderDevice");
    if (renderDeviceSettings != nullptr && !s_disableForceNoHDR)
    {
        renderDeviceSettings->DisplayDynamicRange = 0; // DisplayDynamicRange_SDR
    }

    NetworkSettings* networkSettings = Settings<NetworkSettings>("Network");
    if (networkSettings != nullptr)
    {
        networkSettings->UseFrameManager = true;
    }

    return result;
}

void ServerPlayerSetTeamIdHk(ServerPlayer* inst, int teamId)
{
    static const auto trampoline = HookManager::Call(ServerPlayerSetTeamIdHk);
    int oldTeam = inst != nullptr ? inst->m_teamId : -1;
    int effectiveTeam = teamId;
    if (g_program->m_server != nullptr && g_program->m_server->ShouldOverrideMode3TeamChange(inst, teamId, effectiveTeam))
    {
        KYBER_LOG(Debug, "[Mode3] Preserved '" << (inst->m_name ? inst->m_name : "<null>")
            << "' on Team " << effectiveTeam << " (blocked collapse to Team " << teamId << ")");
    }
    trampoline(inst, effectiveTeam);

    if (inst != nullptr && !inst->IsAIPlayer() && g_program->m_server != nullptr && g_program->m_server->m_currentMode == "Mode3" &&
        oldTeam != inst->m_teamId)
    {
        KYBER_LOG(Info, "[Mode3] SetTeamId '" << (inst->m_name ? inst->m_name : "<null>") << "': " << oldTeam
                                            << " -> " << inst->m_teamId);
    }
}

void PresenceBackendManagerAddBackendHk(void* inst, TypeObject* backend)
{
    static const auto trampoline = HookManager::Call(PresenceBackendManagerAddBackendHk);
    if (backend == nullptr)
    {
        KYBER_LOG(Debug, "[Presence] Registering null backend");
        return;
    }

    KYBER_LOG(Debug, "[Presence] Registering backend " << backend->getType()->getName());
    trampoline(inst, backend);
}

void LoadSomethingHk(void* a1, __int64 a2, __int64 a3, __int64 a4, __int64 a5, __int64 a6, void(__fastcall*** a7)(__int64), __int64 a8,
    __int64 a9, __int64 a10, char a11)
{
    static const auto trampoline = HookManager::Call(LoadSomethingHk);
    return trampoline(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, false);
}

void OnlineServerPlayerExtentUpdateHk(OnlineServerPlayerExtent* inst, float deltaTime)
{
    static const auto trampoline = HookManager::Call(OnlineServerPlayerExtentUpdateHk);
    trampoline(inst, deltaTime);

    if (!inst->m_enableInactivityTimer)
    {
        return;
    }

    WSGameSettings* wsSettings = Settings<WSGameSettings>("Whiteshark");
    if (wsSettings->NoInteractivityTimeoutTime > 0 && inst->m_inactivityTime > wsSettings->NoInteractivityTimeoutTime)
    {
        ServerPlayer* player = inst->GetPlayer();

        // Check if player is host
        if (!g_program->m_isDedicatedServer)
        {
            ClientPlayer* clientPlayer = ClientGameContext::Get()->GetPlayerManager()->GetLocalPlayer(LocalPlayerId_0);
            if (clientPlayer && clientPlayer->m_name && player->m_name && strcmp(clientPlayer->m_name, player->m_name) == 0)
            {
                return;
            }
        }

        ServerConnection* serverConnection = g_program->m_server->GetServerGameContext()->m_serverPeer->GetConnectionForPlayer(player);
        serverConnection->SafeDisconnect("AFK timeout threshold exceeded.", SecureReason_InteractivityTimeout);

        g_program->m_server->SendConsoleMessage(
            "Kicked " + std::string(player->m_name) + " (" + std::to_string(player->m_onlineId.m_nativeData) + ") for being inactive.");
    }
}

void* CreatePresenceBackendHk(__int64* a1, __int64 a2, int backend, __int64 a4, __int64 a5)
{
    static const auto trampoline = HookManager::Call(CreatePresenceBackendHk);
    KYBER_LOG(Trace, "[Presence] Creating presence with backend 0x" << std::hex << backend);

    // The game crashes without this, presumably trying to use a
    // Blaze presence backend for dedicated servers or something
    // which has been cooked out
    backend = 0xB8566ABC; // OnlineBackend_Local

    // Online.IsServerPresenseEnable

    // NetObjectSystemSettings* netObjectSettings = Settings<NetObjectSystemSettings>("NetObjectSystem");
    // netObjectSettings->DeltaCompressionSettings.IsEnabled = false;

    return trampoline(a1, a2, backend, a4, a5);
}

SocketManager* GetSocketManagerHk(void* inst)
{
    g_program->m_server->m_socketManager->m_info = g_program->m_server->m_socketSpawnInfo;
    return g_program->m_server->m_socketManager;
}

bool MessageStreamAddMessageHk(void* inst, TypeObject* message)
{
    static const auto trampoline = HookManager::Call(MessageStreamAddMessageHk);
    KYBER_LOG(Debug, "[Engine] Sending message: " << message->getType()->getName());
    return trampoline(inst, message);
}

void ServerUpdatePassPreFrameHk(void* inst, const UpdateParameters& params)
{
    static const auto trampoline = HookManager::Call(ServerUpdatePassPreFrameHk);
    trampoline(inst, params);

    if (g_program->m_entityManager != nullptr)
    {
        g_program->m_entityManager->UpdateEntities(Realm_Server, params);
    }

    g_threadExecutor->Process(GameThread_Server);
    g_program->m_server->m_eventManager->ProcessEventQueue();

    if (g_program->m_server->IsRunning())
    {
        g_program->GetAPI()->Update();
    }

    if (g_program->m_scriptManager != nullptr)
    {
        g_program->m_scriptManager->GetEventManager().Fire("Server:UpdatePre", params.simulationDeltaTime.toSecondsAsFloat());
    }

    GenericUpdateManager::Get().Call(UpdateType_Server_PreFrame, params);
}

// Only for in-proc servers.
__int64 ServerLevelUpdateLoadHk(void* inst, __int64 loadInfo)
{
    static const auto trampoline = HookManager::Call(ServerLevelUpdateLoadHk);
    __int64 result = trampoline(inst, loadInfo);

    uint32_t loadState = *reinterpret_cast<uint32_t*>(loadInfo + 0x6E8);
    if (loadState == 7 && g_program->m_server->m_creationInfo) // ServerLoadState_Done
    {
        KYBER_LOG(Info, "[Server] Level loaded, executing startup commands");

        if (g_program->m_server->m_runningHosted)
        {
            g_program->m_server->OnLevelLoaded();
        }

        for (const auto& command : g_program->m_server->m_creationInfo->loadCommands)
        {
            g_program->m_console->EnqueueCommand(command.c_str());
        }

        g_program->m_server->m_creationInfo->loadCommands.clear();
    }

    return result;
}

bool ServerConnectionOnCreatePlayerMessageHk(ServerConnection* inst, NetworkCreatePlayerMessage* message)
{
    static const auto trampoline = HookManager::Call(ServerConnectionOnCreatePlayerMessageHk);
    if (!g_program->m_server->m_runningHosted && !g_program->m_isDedicatedServer)
    {
        return trampoline(inst, message);
    }

    // Verify again on the authoritative server after the Launcher preflight.
    if (message->playerName == nullptr || strlen(message->playerName) == 0)
    {
        inst->SafeDisconnect("Choose a nickname in the Launcher before joining.");
        return false;
    }
    auto* manager = g_program->m_server->m_playerManager;
    auto* currentPlayer = inst->GetPlayer(LocalPlayerId_0, true);
    const auto duplicateName = [&](const auto& players) {
        for (auto* player : players)
        {
            if (player != nullptr && player != currentPlayer && !player->IsAIPlayer() && player->m_name != nullptr &&
                _stricmp(player->m_name, message->playerName) == 0)
            {
                return true;
            }
        }
        return false;
    };
    if (manager != nullptr && (duplicateName(manager->m_players) || duplicateName(manager->m_spectators)))
    {
        inst->SafeDisconnect("This nickname is already in use. Change your nickname in the Launcher and reconnect.");
        return false;
    }
    KYBER_LOG(Info, "[Server] [LAN] " << message->playerName << " joined (Spectator: " << message->isSpectator << ")");
    bool result = trampoline(inst, message);

    ServerPlayer* player = inst->GetPlayer();
    if (player != nullptr)
    {
        // Keep the native ID already replicated to both clients. Replacing
        // it with a hash here desynchronizes the team roster and scoreboard.
        KYBER_LOG(Info, "[Server] [LAN] Native player ID for " << player->m_name
            << ": " << player->m_onlineId.m_nativeData);

        g_program->m_server->InitializePlayer(player);

        if (g_program->m_scriptManager != nullptr)
        {
            g_program->m_scriptManager->GetEventManager().Fire("ServerPlayer:Joined", player);
        }

        ServerPlayerAuthenticatedEvent* event = new ServerPlayerAuthenticatedEvent();
        event->connection = inst;
        event->groupId = 0;
        g_program->m_server->m_eventManager->QueueEvent(event);
    }

    return result;
}

void Server::InitializePlayer(ServerPlayer* player)
{
    // Set up inactivity timer
    player->GetOnlineServerPlayerExtent()->m_enableInactivityTimer = true;
    player->GetOnlineServerPlayerExtent()->m_unusedChatFilterDisabled = false;

    if (m_currentMode == "Mode3" && !player->IsAIPlayer() && !player->IsSpectator())
    {
        EnsureEwokHuntTeams();
    }
}

void Server::EnsureEwokHuntTeams()
{
    if (m_currentMode != "Mode3" || !IsRunning() || m_playerManager == nullptr)
    {
        return;
    }

    std::vector<ServerPlayer*> humans;
    size_t team1Count = 0;
    size_t team2Count = 0;
    for (ServerPlayer* player : m_playerManager->m_players)
    {
        if (player == nullptr || player->IsAIPlayer() || player->IsSpectator())
        {
            continue;
        }
        humans.push_back(player);
        if (player->m_teamId == Team1)
        {
            ++team1Count;
        }
        else if (player->m_teamId == Team2)
        {
            ++team2Count;
        }
    }

    if (humans.size() < 2 || (team1Count > 0 && team2Count > 0))
    {
        return;
    }

    // Keep at least one human on both Team 1 (Ewoks) and Team 2 (Stormtroopers).
    int targetTeam = (team1Count == 0) ? Team1 : Team2;
    ServerPlayer* candidate = humans.back();
    candidate->SetTeam(targetTeam);
    KYBER_LOG(Info, "[Mode3] Assigned '" << (candidate->m_name ? candidate->m_name : "<null>")
        << "' to Team " << targetTeam << " to keep both Ewok Hunt teams populated");
}

void Server::NoteMode3Activity()
{
    if (m_currentMode != "Mode3" || !m_levelLoaded || m_mode3RoundHasSpawned)
    {
        return;
    }

    m_mode3RoundHasSpawned = true;
    m_mode3FirstSpawnTime = std::chrono::steady_clock::now();
    KYBER_LOG(Info, "[Mode3] First human spawn detected; starting post-spawn grace window");
}

bool Server::ShouldDelayMode3RoundOver()
{
    if (m_currentMode != "Mode3")
    {
        return false;
    }

    if (!m_levelLoaded)
    {
        return true;
    }

    if (!m_mode3RoundHasSpawned && m_playerManager != nullptr)
    {
        for (ServerPlayer* player : m_playerManager->m_players)
        {
            if (player != nullptr && !player->IsAIPlayer() && !player->IsSpectator() && player->IsAlive())
            {
                NoteMode3Activity();
                break;
            }
        }
    }

    auto now = std::chrono::steady_clock::now();
    auto sinceLoad = std::chrono::duration_cast<std::chrono::seconds>(now - m_roundLoadedTime).count();
    if (sinceLoad < 50)
    {
        return true;
    }

    if (!m_mode3RoundHasSpawned && sinceLoad < 75)
    {
        return true;
    }

    if (m_mode3RoundHasSpawned)
    {
        auto sinceSpawn = std::chrono::duration_cast<std::chrono::seconds>(now - m_mode3FirstSpawnTime).count();
        if (sinceSpawn < 25)
        {
            return true;
        }
    }

    return false;
}

bool Server::ShouldOverrideMode3TeamChange(ServerPlayer* player, int requestedTeam, int& outTeam)
{
    if (m_currentMode != "Mode3" || !IsRunning() || m_playerManager == nullptr || player == nullptr ||
        player->IsAIPlayer() || player->IsSpectator())
    {
        return false;
    }

    if (requestedTeam != Team1 && requestedTeam != Team2)
    {
        return false;
    }

    const bool inStartupWindow = !m_mode3RoundHasSpawned || ShouldDelayMode3RoundOver();
    const bool protectEmptyEwoks = (requestedTeam == Team2) && (inStartupWindow || player->IsAlive());
    const bool protectEmptyStormtroopers = (requestedTeam == Team1) && inStartupWindow;
    if (!protectEmptyEwoks && !protectEmptyStormtroopers)
    {
        return false;
    }

    size_t otherTeam1 = 0;
    size_t otherTeam2 = 0;
    for (ServerPlayer* p : m_playerManager->m_players)
    {
        if (p == nullptr || p == player || p->IsAIPlayer() || p->IsSpectator())
        {
            continue;
        }
        if (p->m_teamId == Team1)
        {
            ++otherTeam1;
        }
        else if (p->m_teamId == Team2)
        {
            ++otherTeam2;
        }
    }

    if (otherTeam1 + otherTeam2 == 0)
    {
        return false;
    }

    if (protectEmptyStormtroopers && otherTeam2 == 0)
    {
        outTeam = Team2;
        return true;
    }

    if (protectEmptyEwoks && otherTeam1 == 0)
    {
        outTeam = Team1;
        return true;
    }

    return false;
}

void Server::OnEvent(const Event& event)
{
    if (event.is<MainLoopInitStartServerEvent>())
    {
        const auto& e = event.as<MainLoopInitStartServerEvent>();
        m_creationInfo = e.info;
    }
}

void Server::OnSettingsRegistered()
{
}

HookTemplate clientServerHookOffsets[] = {
    { OFFSET_SERVER_CONSTRUCTOR, ServerCtorHk },
    { OFFSET_SERVER_START, ServerStartHk },
    { OFFSET_SERVERPLAYER_SETTEAMID, ServerPlayerSetTeamIdHk },
    { OFFSET_APPLY_SETTINGS, SettingsManagerApplyHk },
    { HOOK_OFFSET(0x1478F8440), PresenceBackendManagerAddBackendHk },
    { HOOK_OFFSET(0x1418CA790), LoadSomethingHk },
    //{ HOOK_OFFSET(0x145FE09E0), ProtoHttpControlHk },
    //{ HOOK_OFFSET(0x145FE1920), ProtoHttpPostHk },
    //{ HOOK_OFFSET(0x145FE2990), ProtoHttpUpdateHk },
    //{ HOOK_OFFSET(0x145FEEA40), ProtoSSLUpdateRecvServerCertHk },
    { HOOK_OFFSET(0x140D4E1D0), MessageStreamAddMessageHk },
    { OFFSET_SERVERCONNECTION_ONCREATEPLAYERMESSAGE, ServerConnectionOnCreatePlayerMessageHk },
    { OFFSET_SERVER_UPDATEPASSPREFRAME, ServerUpdatePassPreFrameHk },
    { OFFSET_SERVERLEVEL_UPDATELOAD, ServerLevelUpdateLoadHk },
    { HOOK_OFFSET(0x140BCF350), ServerLoadLevelMessagePostHk },
    { HOOK_OFFSET(0x14193DA20), ServerSendChatMessageHk },
    { HOOK_OFFSET(0x14843AF70), OnlineServerPlayerExtentUpdateHk },
};

HookTemplate dedicatedServerHookOffsets[] = {
    { OFFSET_SERVER_CONSTRUCTOR, ServerCtorHk },
    { OFFSET_SERVERPLAYER_SETTEAMID, ServerPlayerSetTeamIdHk },
    { HOOK_OFFSET(0x1484213F0), GetSocketManagerHk },
    { HOOK_OFFSET(0x1478F8440), PresenceBackendManagerAddBackendHk },
    { HOOK_OFFSET(0x1418CA790), LoadSomethingHk },
    //{ OFFSET_SERVERCONNECTION_KICKPLAYER, ServerConnectionKickPlayerHk },
    { HOOK_OFFSET(0x140D4E1D0), MessageStreamAddMessageHk },
    { HOOK_OFFSET(0x1418D3380), CreatePresenceBackendHk },
    //{ OFFSET_APPLY_SETTINGS, SettingsManagerApplyHk },
    { OFFSET_SERVERCONNECTION_ONCREATEPLAYERMESSAGE, ServerConnectionOnCreatePlayerMessageHk },
    { OFFSET_SERVER_UPDATEPASSPREFRAME, ServerUpdatePassPreFrameHk },
    { HOOK_OFFSET(0x140BCF350), ServerLoadLevelMessagePostHk },
    { HOOK_OFFSET(0x14193DA20), ServerSendChatMessageHk },
    { HOOK_OFFSET(0x14843AF70), OnlineServerPlayerExtentUpdateHk },
};

void Server::InitializeGameHooks()
{
    if (g_program->m_isDedicatedServer)
    {
        for (HookTemplate& hook : dedicatedServerHookOffsets)
        {
            HookManager::CreateHook(hook.offset, hook.hook);
        }
    }
    else
    {
        for (HookTemplate& hook : clientServerHookOffsets)
        {
            HookManager::CreateHook(hook.offset, hook.hook);
        }
    }

    if (m_squadManager != nullptr)
    {
        m_squadManager->InitializeHooks();
    }

    ChatFilter::InitializeHooks();

    Hook::ApplyQueuedActions();
    KYBER_LOG(Debug, "[Server] Initialized Server Hooks");
}

void Server::EnableGameHooks()
{
    m_hooksRemoved = false;
}

void Server::DisableGameHooks()
{
    m_hooksRemoved = true;
}

void Server::InitializeGamePatches()
{
    BYTE dataPatch[] = { 0xEB };
    MemoryUtils::Patch(HOOK_OFFSET(0x1454DCC9D), (void*)dataPatch, sizeof(dataPatch));

    if (g_program->m_isDedicatedServer)
    {
        MemoryUtils::Nop(HOOK_OFFSET(0x146860582), 3);
        MemoryUtils::Nop(HOOK_OFFSET(0x1418E3F3C), 16);
        MemoryUtils::Nop(HOOK_OFFSET(0x1453B2163), 3);

        BYTE ptch[] = { 0xE9, 0xEF, 0x00 };
        MemoryUtils::Patch(HOOK_OFFSET(0x14183D533), (void*)ptch, sizeof(ptch));
        MemoryUtils::Patch(HOOK_OFFSET(0x140249606), (void*)dataPatch, sizeof(dataPatch));
        return;
    }

    BYTE ptch[] = { 0xB9, 0x01, 0x00, 0x00, 0x00 };
    MemoryUtils::Patch((void*)OFFSET_SERVER_PATCH, (void*)ptch, sizeof(ptch));
    BYTE ptch2[] = { 0x90, 0x90 };
    MemoryUtils::Patch((void*)(OFFSET_SERVER_PATCH + 0x5), (void*)ptch2, sizeof(ptch2));
}

void Server::OnClientStartup()
{
    static bool firstStartup = true;
    if (!firstStartup)
    {
        return;
    }

    if (!m_creationInfo)
    {
        return;
    }

    firstStartup = false;
    Start(*m_creationInfo, false);
}

void Server::SendConsoleMessage(const std::string& message)
{}

void Server::Stop()
{
    KYBER_LOG(Info, "[Server] Stopping Kyber server...");

    m_runningHosted = false;
    m_playerManager = nullptr;
    m_serverInstance = nullptr;

    m_serverId.clear();

    UDPSocket* socket = m_socketManager->m_sockets.back();
    m_socketManager->Close(socket);
    socket->Close();
}
} // namespace Kyber
