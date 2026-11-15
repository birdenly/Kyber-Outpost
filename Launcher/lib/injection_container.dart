// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/rich_presence.dart';
import 'package:kyber_launcher/core/services/vivox_sdk_service.dart';
import 'package:kyber_launcher/core/services/voip_service.dart';
import 'package:kyber_launcher/features/download_manager/services/download_orchestrator.dart';
import 'package:kyber_launcher/features/download_manager/services/mod_bridge_service.dart';
import 'package:kyber_launcher/features/kyber/services/kyber_grpc_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_mod_server_service.dart';
import 'package:kyber_launcher/features/map_rotation/services/custom_rotation_service.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mods/services/level_declaration_service.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/features/plugin_manager/services/plugin_manager.dart';

final GetIt sl = GetIt.instance;

void initializeDependencies() {
  final lanDiscoveryService = LanDiscoveryService();
  unawaited(lanDiscoveryService.startListening());

  sl
    ..registerSingleton<KyberGRPCService>(
      KyberGRPCService.local(),
    )
    ..registerSingleton<LanModServerService>(LanModServerService())
    ..registerSingleton<LanDiscoveryService>(lanDiscoveryService)
    ..registerSingleton<RichPresence>(RichPresence())
    ..registerSingleton<MaximaInstanceService>(MaximaInstanceService())
    ..registerSingleton<KyberGRPCServer>(KyberGRPCServer())
    ..registerSingleton<ModBridgeGRPCService>(
      ModBridgeGRPCService.fromEnv(Preferences.admin.apiEnv),
    )
    ..registerSingleton<VoipService>(VoipService().getInstance())
    ..registerSingleton<PluginManager>(PluginManager())
    ..registerSingleton<LevelDeclarationService>(LevelDeclarationService())
    ..registerSingletonAsync<ModService>(ModService.getInstance)
    ..registerSingletonAsync<DownloadOrchestrator>(
      DownloadOrchestrator.getInstance,
    )
    ..registerSingletonAsync<KyberMapService>(KyberMapService().getInstance)
    ..registerSingletonAsync<VivoxService>(VivoxService().getInstance)
    ..registerSingletonAsync<NexusModsService>(NexusModsService().getInstance);
}
