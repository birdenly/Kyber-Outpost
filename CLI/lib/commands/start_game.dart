// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart' hide ProxyList;
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
      ..addFlag(
        'lan',
        defaultsTo: true,
        help: 'Starts the game in LAN/Offline mode',
      )
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
        'game-data-path',
        help: 'Specify the game data path',
        valueHelp: 'path',
        callback: (p0) => p0 is String ? Directory(p0) : null,
      )
      ..addOption(
        'module-branch',
        help: 'Specify the branch to use for the Kyber module',
        valueHelp: 'branch',
      )
      ..addOption(
        'module-path',
        help: 'Specify a custom directory to use for the Kyber module',
        valueHelp: 'path/to/module',
      )
      ..addOption('interface-port', valueHelp: '9000');
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

    if (argResults?['lan'] == false) {
      _logger.err('This build only supports LAN. Use --connect-ip and --name.');
      return ExitCode.usage.code;
    }
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

    Env.set('KYBER_ONLINE_MODE', '0');
    Env.set('KYBER_API_TOKEN', 'lan_offline_token');
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

    final kyberPort =
        argResults?['interface-port'] as String? ??
        (await KyberNetworkHelper.findAvailablePort()).toString();
    Env.set('KYBER_INTERFACE_PORT', kyberPort);
    Env.set('KYBER_API_HOSTNAME', sl.get<KyberGRPCService>().host);
    Env.set('KYBER_HTTP_HOSTNAME', sl.get<KyberGRPCService>().httpHostname);

    ModData? modData;
    var gameplayMods = <FrostyMod>[];
    if (collectionFile != null) {
      final metaData = await ModCollection.readCollection(collectionFile);
      final dir = CollectionHelper().getModsDirectory();
      final mods = CollectionHelper().getModsList(metaData);
      final fbMods = ModHelper.readFrostyMods(
        mods.map((e) => join(dir, e)).toList(),
      );

      gameplayMods = ModHelper.filterGameplayMods(fbMods);

      modData = ModData(
        basePath: normalize(dir),
        modPaths: mods,
        mods: gameplayMods.map((e) => e.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((e) => e.toServerMod()),
      );
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
      final fbMods = ModHelper.readFrostyMods(
        rawMods.modPaths.map((e) => join(rawMods.basePath, e)).toList(),
      );

      gameplayMods = ModHelper.filterGameplayMods(fbMods);

      modData = ModData(
        basePath: rawMods.basePath,
        modPaths: rawMods.modPaths,
        mods: gameplayMods.map((e) => e.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((e) => e.toServerMod()),
      );
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
      gameArgs: [],
    );

    _logger.info(
      'Injecting Kyber from ${FileHelper.getModuleDirectory().path}/Kyber.dll...',
    );
    await waitForKyberModule(
      pid: pid,
      path: FileHelper.getModuleDirectory().path + "\\Kyber.dll",
    );

    sl.registerSingleton<MaximaGameInstance>(
      MaximaGameInstance(
        pid: pid,
        isDedicated: true,
        clientService: ClientGRPCService('', 0),
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
}
