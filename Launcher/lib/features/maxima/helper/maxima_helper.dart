// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:grpc/grpc.dart' show CallOptions, GrpcError;
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/windows_env.dart';
import 'package:kyber_launcher/features/frosty/dialogs/frosty_pack_selector_dialog.dart';
import 'package:kyber_launcher/features/game/dialogs/mod_limit_dialog.dart';
import 'package:kyber_launcher/features/kyber/services/kyber_grpc_service.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_start_game_dialog.dart';
import 'package:kyber_launcher/features/maxima/extensions/server_mod.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mod_collections/extensions/mod_collection_extension.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/gen/rust/api/outpost.dart' as outpost;
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

class MaximaHelper {
  static final Logger _logger = Logger('maxima_helper');

  static Future<void> _waitForKyber(
    ClientGRPCService gameClient, {
    required bool requireServer,
  }) async {
    final elapsed = Stopwatch()..start();
    final limit = Duration(seconds: requireServer ? 300 : 60);
    const rpcLimit = Duration(seconds: 60);
    const attemptTimeout = Duration(seconds: 2);
    const retryDelay = Duration(milliseconds: 500);
    var rpcResponded = false;

    while (elapsed.elapsed < limit) {
      final remaining = limit - elapsed.elapsed;
      final request = gameClient.commonClient.getInfo(
        Empty(),
        options: CallOptions(
          timeout: remaining < attemptTimeout ? remaining : attemptTimeout,
        ),
      );
      try {
        final state = await request;
        rpcResponded = true;
        if (!requireServer ||
            (state.hasServer() &&
                state.server.levelSetup.map.trim().isNotEmpty)) {
          return;
        }
      } on GrpcError {
        // The DLL may still be initializing its local RPC interface.
      } finally {
        await request.cancel();
      }

      if (!rpcResponded && elapsed.elapsed >= rpcLimit) {
        break;
      }
      final delayRemaining = limit - elapsed.elapsed;
      if (delayRemaining > Duration.zero) {
        await Future<void>.delayed(
          delayRemaining < retryDelay ? delayRemaining : retryDelay,
        );
      }
    }

    if (requireServer && rpcResponded) {
      throw TimeoutException(
        'Kyber local RPC responded, but the LAN server did not start a map '
        'within 300 seconds. Check the game window and the Kyber log.',
      );
    }
    throw TimeoutException(
      'Kyber.dll was loaded, but its local RPC did not respond within '
      '60 seconds. Check the game window and the Kyber log.',
    );
  }

  static Future<void> requestGameLaunch(
    BuildContext context, {
    ModCollectionMetaData? modCollection,
    bool showCollectionSelector = true,
    InitializeRequest? initializeRequest,
  }) async {
    if (modCollection == null && showCollectionSelector) {
      modCollection = await showKyberDialog<ModCollectionMetaData?>(
        context: context,
        builder: (_) => const FrostyPackSelectorDialog(),
      );

      if (modCollection == null) {
        _logger.fine('User cancelled selection. Aborting requestGameLaunch');
        return;
      }
    }

    initializeRequest ??= InitializeRequest();
    if (modCollection != null) {
      if (modCollection.getLocalMods().contains(null)) {
        NotificationService.error(
          message:
              'Some mods in your collection are missing. Please check your mod collection.',
        );
        return;
      }

      final modPaths = modCollection.getModPaths();
      const modLimit = 1739;
      if (modPaths.length >= modLimit) {
        _logger.warning('Mod limit reached: ${modPaths.length}');

        if (context.mounted) {
          await showKyberDialog(
            context: context,
            builder: (_) => const ModLimitDialog(),
          );
        }

        return;
      }

      initializeRequest.modData = ModData(
        basePath: ModService.getBasePath(),
        modPaths: modPaths,
        mods: modCollection
            .getLocalMods(onlyGameplay: true)
            .whereType<FrostyMod>()
            .map(ServerMod().fromFrostyMod)
            .toList(),
        explodedMods: modCollection
            .getLocalMods(
              onlyGameplay: true,
              expandCollections: true,
            )
            .whereType<FrostyMod>()
            .where((e) => !e.isCollection)
            .map(ServerMod().fromFrostyMod)
            .toList(),
      );
    }

    if (!context.mounted) {
      _logger.warning('Context is not mounted, aborting requestGameLaunch');
      return;
    }

    // final gameConfig = await ConfigParser.parseConfig();
    // if (gameConfig.enableDx12) {
    //   _logger.warning('Launching game with DirectX 12 enabled');
    //   NotificationService.warning(
    //     message:
    //     'DirectX 12 is enabled. This can cause instability and issues with Kyber.',
    //   );
    // }

    if (initializeRequest.startupCommands.isNotEmpty) {
      _logger.fine(
        'Starting game with startup commands: ${initializeRequest.startupCommands}',
      );
    }

    if (!context.mounted) {
      _logger.warning('Context is not mounted, aborting requestGameLaunch');
      return;
    }

    await showKyberDialog(
      context: context,
      builder: (_) => MaximaStartGameDialog(
        initializeRequest: initializeRequest,
        mods: modCollection?.getLocalMods().whereType<FrostyMod>().toList(),
      ),
    );
  }

  static Future<MaximaGameInstance> startGame({
    InitializeRequest? initializeRequest,
    String? gameSlug,
    String? gamePath,
    String? gameDataPath,
    List<FrostyMod>? mods,
  }) async {
    final path = Platform.environment['PATH'];

    if (path == null) {
      throw Exception('PATH environment variable is not set');
    }

    final moduleDirectory = ModuleVersionService.selectedModuleDirectory;
    final moduleFile = File(p.join(moduleDirectory.path, 'Kyber.dll'));
    final vivoxFile = File(p.join(moduleDirectory.path, 'vivoxsdk.dll'));
    if (!moduleFile.existsSync() || !vivoxFile.existsSync()) {
      throw FileSystemException(
        'The local Kyber module is incomplete. Kyber.dll and vivoxsdk.dll '
        'must be present before starting the game.',
        moduleDirectory.path,
      );
    }
    _logger.info('Using local Kyber module: ${moduleFile.path}');
    final hasMods = initializeRequest?.modData.modPaths.isNotEmpty ?? false;
    if (hasMods) {
      final aggregation = File(
        p.join(moduleDirectory.path, 'VanillaBundleAggregation.kb'),
      );
      if (!aggregation.existsSync()) {
        throw FileSystemException(
          'VanillaBundleAggregation.kb is required to load mods.',
          aggregation.path,
        );
      }
      ProcessEnv.delete('KYBER_DISABLE_MODLOADER');
    } else {
      ProcessEnv.set('KYBER_DISABLE_MODLOADER', '1');
    }
    ProcessEnv.set('KYBER_MODULE_PATH', moduleFile.path);

    final grpcDebug = Preferences.debug.grpcDebugLogs;
    final moduleDebug = Preferences.debug.moduleDebugLogs;
    final newPath = '${moduleFile.parent.path};$path';
    final interfacePort = await KyberNetworkHelper.findAvailablePort();
    String? cubitPlayerName;
    try {
      if (sl.isRegistered<MaximaCubit>()) {
        cubitPlayerName = sl
            .get<MaximaCubit>()
            .state
            .servicePlayer
            ?.displayName;
      }
    } catch (_) {}
    final playerName =
        cubitPlayerName ?? 'OutpostPlayer${InstanceManager.nameSuffix}';
    await outpost.getLocalProfile(name: playerName);
    ProcessEnv.set('KYBER_ONLINE_MODE', '0');
    ProcessEnv.set('KYBER_SERVER_PORT', InstanceManager.gamePort.toString());
    ProcessEnv.set('KYBER_API_TOKEN', 'lan_offline_token');
    ProcessEnv.set('EALaunchEAID', playerName);
    ProcessEnv.set('EALaunchUserAuthToken', 'lan_offline_token');
    ProcessEnv.set(
      'KYBER_MODULE_VERSION',
      (await VersionModule.module.getCurrentVersion()) ?? '0.0.0-lan',
    );
    ProcessEnv.set('KYBER_INTERFACE_PORT', interfacePort.toString());
    ProcessEnv.set(
      'KYBER_HTTP_HOSTNAME',
      sl.get<KyberGRPCService>().httpHostname,
    );
    ProcessEnv.set('PATH', newPath);
    ProcessEnv.set('KYBER_API_HOSTNAME', sl.get<KyberGRPCService>().host);

    if (grpcDebug) {
      ProcessEnv.set('GRPC_TRACE', 'all');
      ProcessEnv.set('GRPC_VERBOSITY', 'debug');
    } else {
      ProcessEnv.delete('GRPC_TRACE');
      ProcessEnv.delete('GRPC_VERBOSITY');
    }

    if (moduleDebug) {
      ProcessEnv.set('KYBER_LOG_LEVEL', 'debug');
    } else {
      ProcessEnv.delete('KYBER_LOG_LEVEL');
    }

    if (Preferences.general.disableForceDX11) {
      ProcessEnv.set('KYBER_EXPERIMENTAL_DISABLE_FORCE_DX11', '1');
    } else {
      ProcessEnv.delete('KYBER_EXPERIMENTAL_DISABLE_FORCE_DX11');
    }

    if (Preferences.general.disableForceNoHDR) {
      ProcessEnv.set('KYBER_EXPERIMENTAL_DISABLE_FORCE_NOHDR', '1');
    } else {
      ProcessEnv.delete('KYBER_EXPERIMENTAL_DISABLE_FORCE_NOHDR');
    }

    sl.get<KyberGRPCServer>().setInitializeRequest(
      initializeRequest ?? InitializeRequest(),
    );
    final gamePID = await outpost.startGame(
      gameSlug: gameSlug ?? 'star-wars-battlefront-2',
      gamePathOverride: gamePath,
    );
    _logger.info(
      'Offline game process started with PID: $gamePID',
    );

    final gameClient = ClientGRPCService(
      '127.0.0.1',
      interfacePort,
      connectTimeout: const Duration(seconds: 2),
    );

    final instance = MaximaGameInstance(
      pid: gamePID,
      clientService: gameClient,
      isDedicated: false,
      mods: mods ?? [],
    );

    try {
      _logger.info(
        'Waiting for the offline emulator to load: ${moduleFile.path}',
      );
      await outpost.waitForKyberModule(pid: gamePID, path: moduleFile.path);
      await _waitForKyber(
        gameClient,
        requireServer: initializeRequest?.hasStartServer() ?? false,
      );
    } on Object catch (error, stackTrace) {
      _logger.severe('Game startup failed for PID $gamePID', error, stackTrace);
      try {
        await outpost.stopGame(pid: gamePID);
      } on Object catch (cleanupError, cleanupStack) {
        _logger.warning(
          'Could not terminate failed game PID $gamePID',
          cleanupError,
          cleanupStack,
        );
      }
      try {
        await gameClient.channel.shutdown();
        await instance.closeStream();
      } on Object catch (cleanupError, cleanupStack) {
        _logger.warning(
          'Could not release failed game resources for PID $gamePID',
          cleanupError,
          cleanupStack,
        );
      }
      rethrow;
    }

    if (sl.isRegistered<MaximaGameInstance>()) {
      await sl.unregister<MaximaGameInstance>();
    }
    sl.registerSingleton<MaximaGameInstance>(instance);
    sl.get<MaximaInstanceService>().addInstance(instance);
    _logger.info(
      'Kyber is ready with PID: $gamePID and local RPC port $interfacePort',
    );

    return instance;
  }
}
