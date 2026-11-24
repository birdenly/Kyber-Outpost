// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dio/dio.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/api/outpost.dart';
import 'package:kyber_cli/models/maxima_instance.dart';
import 'package:kyber_cli/utils/collection_helper.dart';
import 'package:kyber_cli/utils/env_helper.dart';
import 'package:kyber_cli/utils/extensions/server_mod_extension.dart';
import 'package:kyber_cli/utils/kyber_grpc_server.dart';
import 'package:kyber_cli/utils/mod_helper.dart';
import 'package:kyber_cli/utils/services/level_declaration_service.dart';
import 'package:kyber_cli/utils/types/raw_mods.dart';
import 'package:kyber_cli/utils/windows_env.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart';

class StartGameCommand extends Command<int> {
  StartGameCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Player nickname for LAN mode',
        valueHelp: 'Jedha',
      )
      ..addOption(
        'connect-ip',
        help: 'Connect directly to a LAN server IP[:port]',
        valueHelp: '192.168.1.10:25200',
      )
      ..addFlag('spectate', help: 'Starts the game in spectate mode')
      ..addOption(
        'raw-mods',
        help: 'Specify a list of mods to use',
        valueHelp: 'path/to/mod_file.json',
      )
      ..addOption(
        'collection-file',
        help: 'Specify the Mod Collection file to use',
        valueHelp: 'path/to/collection.kmodcollection',
      )
      ..addOption('game-path', help: 'Specify the game path')
      ..addMultiOption(
        'game-args',
        help: 'Specify the game arguments',
        valueHelp: '[arg1, arg2, ...]',
      )
      ..addOption(
        'module-path',
        help: 'Specify a custom directory to use for the Kyber module',
        valueHelp: 'path/to/module',
      )
      ..addOption('interface-port', valueHelp: '9000')
      ..addOption(
        'http-port',
        help:
            'Override LAN host HTTP mod server port (default: server port + 2)',
        valueHelp: '25202',
      )
      ..addOption(
        'server-port',
        help:
            'Local KYBER_SERVER_PORT override to avoid conflicts on the same PC',
        valueHelp: '25201',
      );
  }

  @override
  String get description => '''Starts Battlefront and injects Kyber''';

  @override
  String get name => 'start_game';

  final Logger _logger;

  @override
  Future<int> run() async {
    final modulePath = EnvHelper.getModulePath(
      argResults?['module-path'] as String?,
    );
    EnvHelper.setPath(modulePath);
    Env.set('KYBER_MODULE_PATH', join(modulePath, 'Kyber.dll'));

    final customName = argResults?['name'] as String?;
    _logger.info('Initializing the local player profile...');
    late ServicePlayer player;
    try {
      player = await getLocalProfile(name: customName ?? 'Jedha');
    } catch (e) {
      if (e is PanicException || e is AnyhowException) {
        final err = e is PanicException
            ? e.message
            : (e as AnyhowException).message;
        if (err.contains('unknown variant `NO_SUCH_USER`')) {
          _logger.err('Login failed: The specified user does not exist');
        } else {
          _logger.err('Login failed: $err');
        }
        return ExitCode.usage.code;
      }

      _logger.err('Login failed: $e');
      return ExitCode.usage.code;
    }

    _logger.success('Ready as ${customName ?? player.displayName}.');
    _logger.info('Running in Kyber Outpost LAN mode (offline).');

    final rawModsPath = argResults?['raw-mods'] as String?;
    File? collectionFile;
    if (argResults?['collection-file'] != null) {
      collectionFile = File(argResults?['collection-file'] as String);
      if (!collectionFile.existsSync()) {
        _logger.err('Collection file does not exist');
        return ExitCode.usage.code;
      }

      await CollectionHelper().useCollection(collectionFile);
    }

    JoinServerRequest? joinServerByIP;
    final connectIpArg = argResults?['connect-ip'] as String?;
    if (connectIpArg != null && connectIpArg.trim().isNotEmpty) {
      final parts = connectIpArg.trim().split(':');
      final targetIp = parts.first;
      final targetPort = parts.length > 1
          ? (int.tryParse(parts[1]) ?? 25200)
          : 25200;
      joinServerByIP = JoinServerRequest(
        id: '',
        ip: targetIp,
        port: targetPort,
        spectate: argResults?['spectate'] as bool? ?? false,
        type: JoinServerType.DIRECT,
        joinToken: '',
      );
      _logger.info('Configured direct LAN connection to $targetIp:$targetPort');
    }

    if (joinServerByIP != null &&
        !Platform.environment.containsKey('KYBER_SERVER_PORT')) {
      final localPortArg = int.tryParse(
        argResults?['server-port'] as String? ?? '',
      );
      final localPort = localPortArg ?? await _findAvailableGamePort();
      Env.set('KYBER_SERVER_PORT', localPort.toString());
    }

    final kyberPort =
        argResults?['interface-port'] as String? ??
        (await KyberNetworkHelper.findAvailablePort()).toString();
    Env.set('KYBER_INTERFACE_PORT', kyberPort);

    ModData? modData;
    var gameplayMods = <FrostyMod>[];
    if (collectionFile != null) {
      final metaData = await ModCollection.readCollection(collectionFile);
      final dir = CollectionHelper().getModsDirectory();
      final mods = CollectionHelper().getModsList(metaData);
      (gameplayMods, modData) = _buildModData(dir, mods);
    } else if (rawModsPath != null) {
      final rawModsFile = File(rawModsPath);
      if (!rawModsFile.existsSync()) {
        _logger.err('The specified raw-mods file does not exist');
        return ExitCode.usage.code;
      }

      final data = rawModsFile.readAsStringSync();
      final rawMods = RawMods.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
      (gameplayMods, modData) = _buildModData(
        rawMods.basePath,
        rawMods.modPaths,
      );
    } else if (joinServerByIP != null) {
      final httpPortArg = int.tryParse(
        argResults?['http-port'] as String? ?? '',
      );
      final synced = await _syncLanMods(
        joinServerByIP.ip,
        httpPortArg ?? (joinServerByIP.port + 2),
      );
      if (synced != null) {
        (gameplayMods, modData) = synced;
      }
    }

    // Same mod-loader gate as the Launcher's maxima_helper: the module only
    // checks KYBER_DISABLE_MODLOADER, and without VanillaBundleAggregation.kb
    // the mod loader stalls the game instead of failing.
    if (modData?.modPaths.isNotEmpty ?? false) {
      final aggregation = File(
        join(modulePath, 'VanillaBundleAggregation.kb'),
      );
      if (!aggregation.existsSync()) {
        _logger.err(
          'VanillaBundleAggregation.kb is required to load mods. '
          'Expected it at ${aggregation.path}',
        );
        return ExitCode.unavailable.code;
      }
      if (Platform.environment.containsKey('KYBER_DISABLE_MODLOADER')) {
        Env.delete('KYBER_DISABLE_MODLOADER');
      }
    } else {
      Env.set('KYBER_DISABLE_MODLOADER', '1');
    }

    final modEntries = <String, ModEntry>{};
    for (final mod in gameplayMods.where(
      (element) =>
          kRequiredCategories.contains(
            element.details.category.toLowerCase(),
          ) &&
          element.customFrostyData != null,
    )) {
      final modes = mod.customFrostyData!.modes
          .map(
            (e) => CustomMode(
              e.name,
              e.id,
              e.maxPlayers ?? -1,
              base64.decode(e.image),
            ),
          )
          .toList();
      final maps = mod.customFrostyData!.maps
          .map(
            (e) => CustomMap(
              e.name,
              e.id,
              e.supportedModes ?? [],
              base64.decode(e.image),
            ),
          )
          .toList();

      modEntries[mod.filename] = ModEntry(
        maps,
        modes,
        mod.customFrostyData!.modeMappings ?? {},
        mod.customFrostyData!.modeNameOverrides ?? {},
      );
    }

    sl
      ..registerSingleton<LevelDeclarationService>(LevelDeclarationService())
      ..get<LevelDeclarationService>().set(modEntries);

    final grpcServer = KyberGRPCServer();
    await grpcServer.start();
    grpcServer.setInitializeRequest(
      InitializeRequest(joinServer: joinServerByIP, modData: modData),
    );

    _logger.info('Kyber will listen on port $kyberPort');
    final pid = await startGame(
      gameSlug: 'star-wars-battlefront-2',
      gamePathOverride: argResults?['game-path'] as String?,
      gameArgs: argResults?['game-args'] as List<String>? ?? [],
    );

    final kyberDllPath = join(modulePath, 'Kyber.dll');
    _logger.info('Injecting Kyber from $kyberDllPath...');
    await waitForKyberModule(pid: pid, path: kyberDllPath);

    sl.registerSingleton<MaximaGameInstance>(
      MaximaGameInstance(
        pid: pid,
        mods: gameplayMods,
      ),
    );

    _logger.info('Waiting for Kyber (PID: $pid)');
    final completion = Completer<void>();
    gameEvents(pid: pid).distinct().listen(
      (event) async {
        if (event != 'GameRunning') {
          return;
        }

        _logger.success('Kyber started');
      },
      onDone: completion.complete,
      onError: completion.complete,
    );

    try {
      await completion.future;
    } catch (e) {
      _logger.err('Error: $e');
    }

    return ExitCode.success.code;
  }

  (List<FrostyMod>, ModData) _buildModData(
    String basePath,
    List<String> modPaths,
  ) {
    final normalizedBase = normalize(basePath);
    final fbMods = ModHelper.readFrostyMods(
      modPaths.map((e) => join(normalizedBase, e)).toList(),
    );
    final gameplayMods = ModHelper.filterGameplayMods(fbMods);
    final modData = ModData(
      basePath: normalizedBase,
      modPaths: modPaths,
      mods: gameplayMods.map((e) => e.toServerMod()),
      explodedMods: ModHelper.expandMods(
        gameplayMods,
      ).map((e) => e.toServerMod()),
    );
    return (gameplayMods, modData);
  }

  Future<int> _findAvailableGamePort() async {
    for (var port = 25201; port < 25300; port++) {
      try {
        final sock = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: false,
        );
        sock.close();
        return port;
      } catch (_) {}
    }
    return 25201;
  }

  Future<(List<FrostyMod>, ModData)?> _syncLanMods(
    String hostIp,
    int httpPort,
  ) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://$hostIp:$httpPort',
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      final resp = await dio.get<dynamic>('/lan/info');
      final data = resp.data;
      if (data is! Map<String, dynamic>) return null;
      final rawMods = data['mods'];
      if (rawMods is! List || rawMods.isEmpty) return null;

      final modsDir = CollectionHelper().getModsDirectory();
      await Directory(modsDir).create(recursive: true);

      final modPaths = <String>[];
      for (final item in rawMods) {
        if (item is! Map) continue;
        final rawFilename = item['filename']?.toString();
        final index = item['index'];
        final expectedSize = (item['fileSize'] as num?)?.toInt();
        if (rawFilename == null || rawFilename.isEmpty || index == null) {
          continue;
        }

        final safeName = basename(rawFilename);
        final destFile = File(join(modsDir, safeName));
        final needsDownload =
            !destFile.existsSync() ||
            (expectedSize != null &&
                expectedSize > 0 &&
                destFile.lengthSync() != expectedSize);
        if (needsDownload) {
          _logger.info(
            'Downloading LAN mod $safeName from $hostIp:$httpPort...',
          );
          final tmpPath = '${destFile.path}.downloading';
          await dio.download('/lan/mods/$index', tmpPath);
          final tmpFile = File(tmpPath);
          if (destFile.existsSync()) destFile.deleteSync();
          await tmpFile.rename(destFile.path);
        }
        modPaths.add(safeName);
      }

      if (modPaths.isEmpty) return null;
      _logger.info('Synced ${modPaths.length} LAN mod(s) from host.');
      return _buildModData(modsDir, modPaths);
    } catch (e) {
      _logger.detail('No LAN mod manifest fetched from $hostIp:$httpPort ($e)');
      return null;
    } finally {
      dio.close();
    }
  }
}
