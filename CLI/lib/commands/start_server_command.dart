// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:grpc/grpc.dart';
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

class StartServerCommand extends Command<int> {
  StartServerCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addFlag('show-console', help: 'Shows the Kyber console window.')
      ..addFlag(
        'no-dedicated',
        help: 'Starts a non-dedicated server',
        negatable: false,
      )
      ..addSeparator('Server Options')
      ..addOption('server-name', abbr: 'n', help: 'Specify the server name')
      ..addOption('server-password', abbr: 'p', help: 'Specify the server name')
      ..addOption('server-description', help: 'Specify the server description')
      ..addOption(
        'max-players',
        defaultsTo: '40',
        help: 'Specify the maximum number of players',
      )
      ..addOption('mode', help: 'Specify the mode')
      ..addOption('map', help: 'Specify the map')
      ..addOption('rotation-file', help: 'Specify the rotation file to use')
      ..addOption(
        'startup-commands',
        help: 'Specify a text file with startup commands',
        valueHelp: 'path/to/commands.txt',
      )
      ..addSeparator('Game Options')
      ..addOption(
        'collection-file',
        help: 'Specify the Mod Collection file to use',
        valueHelp: 'path/to/collection.kmodcollection',
      )
      ..addOption(
        'collection-mods-directory',
        help: 'Specify the directory to use for the collection mods',
        valueHelp: 'path/to/mods',
      )
      ..addOption(
        'raw-mods',
        help: 'Specify a list of mods to use',
        valueHelp: 'path/to/mod_file.json',
      )
      ..addOption(
        'mod-folder',
        help:
            'Specify a directory that contains a collection file and all required mods',
        valueHelp: 'path/to/dir',
      )
      ..addOption('game-path', help: 'Specify the game path')
      ..addMultiOption(
        'game-args',
        help: 'Specify the game arguments',
        valueHelp: '[arg1, arg2, ...]',
      )
      ..addSeparator('Local player and module')
      ..addOption(
        'name',
        help: 'Local player nickname',
        valueHelp: 'OutpostPlayer',
      )
      ..addOption(
        'module-path',
        help: 'Specify a custom directory to use for the Kyber module',
        valueHelp: 'path/to/module',
      )
      ..addOption(
        'module-branch',
        help: 'Specify the branch to use for the Kyber module',
        valueHelp: 'branch',
      )
      ..addOption('interface-port', valueHelp: '9000');
  }

  @override
  String get description =>
      '''Starts a dedicated Kyber server with the given options''';

  @override
  String get name => 'start_server';

  final Logger _logger;

  @override
  Future<int> run() async {
    final serverName =
        (Platform.environment['KYBER_SERVER_NAME'] ??
                argResults?['server-name'] ??
                'Kyber Outpost LAN Server')
            as String;

    final modulePath = EnvHelper.getModulePath(
      argResults?['module-path'] as String?,
    );
    EnvHelper.setPath(modulePath);
    Env.set('KYBER_MODULE_PATH', join(modulePath, 'Kyber.dll'));

    _logger.info('Initializing the local player profile...');
    late String playerName;
    try {
      final player = await getLocalProfile(
        name: argResults?['name'] as String? ?? 'OutpostPlayer',
      );
      playerName = player.displayName;
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

    _logger
      ..success('Ready as $playerName.')
      ..info('Starting game...');

    final mapRotation = <LevelSetup>[];
    if (argResults?['rotation-file'] != null ||
        Platform.environment.containsKey('KYBER_MAP_ROTATION')) {
      File? file;
      if ((argResults?['rotation-file'] as String?) != null) {
        final file = File(argResults?['rotation-file'] as String);
        if (!file.existsSync()) {
          _logger.err('The specified rotation file does not exist');
          return ExitCode.usage.code;
        }
      }

      late List<String> data;
      if (Platform.environment.containsKey('KYBER_MAP_ROTATION')) {
        data = utf8
            .decode(base64.decode(Platform.environment['KYBER_MAP_ROTATION']!))
            .split('\n');
      } else {
        data = file!.readAsLinesSync();
      }
      for (final line in data) {
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }

        final split = line.split(';');
        if (split.length != 2) {
          _logger.err('Invalid rotation file');
          return ExitCode.usage.code;
        }

        mapRotation.add(LevelSetup(map: split[1], mode: split[0]));
      }

      _logger.info('Loaded map rotation with ${mapRotation.length} entries');
    }

    File? collectionFile;
    final modFolder =
        Platform.environment['KYBER_MOD_FOLDER'] ??
        argResults?['mod-folder'] as String?;
    if (modFolder != null) {
      final dir = Directory(modFolder);
      if (!dir.existsSync()) {
        _logger.err('The specified mod folder does not exist');
        return ExitCode.usage.code;
      }

      final collectionFiles = dir
          .listSync()
          .whereType<File>()
          .where((e) => e.path.endsWith('.kbcollection'))
          .toList();
      if (collectionFiles.isEmpty) {
        _logger.err(
          'The specified mod folder does not contain a collection file',
        );
        return ExitCode.usage.code;
      }

      if (collectionFiles.length > 1) {
        _logger.err(
          'The specified mod folder contains multiple collection files',
        );
        return ExitCode.usage.code;
      }

      collectionFile = collectionFiles.first;
    } else if (argResults?['collection-file'] != null) {
      collectionFile = File(argResults?['collection-file'] as String);
      await CollectionHelper().useCollection(collectionFile);
    }

    const kToken = 'lan_offline_token';

    Env.set('KYBER_ONLINE_MODE', '0');
    sl.get<KyberGRPCService>().token = kToken;

    Env.delete('KYBER_HIDE_CONSOLE');
    final showConsole = argResults?['show-console'] as bool?;
    if (showConsole != null && showConsole) {
      Env.set('KYBER_HIDE_CONSOLE', '1');
    }

    Env.set('KYBER_API_TOKEN', kToken);

    final noDedicated = argResults?['no-dedicated'] as bool? ?? false;
    Env.set('KYBER_DEDICATED_SERVER', noDedicated ? '0' : '1');
    if (noDedicated) {
      Env.delete('KYBER_DEDICATED_SERVER');
    }

    final kyberPort =
        argResults?['interface-port'] as String? ??
        (await KyberNetworkHelper.findAvailablePort()).toString();
    Env.set('KYBER_INTERFACE_PORT', kyberPort);
    Env.set('KYBER_API_HOSTNAME', sl.get<KyberGRPCService>().host);
    Env.set('KYBER_HTTP_HOSTNAME', sl.get<KyberGRPCService>().httpHostname);

    final rawModsPath = argResults?['raw-mods'] as String?;
    ModData? modData;
    var gameplayMods = <FrostyMod>[];
    if (collectionFile != null) {
      final metaData = await ModCollection.readCollection(collectionFile);
      var modsDir =
          modFolder ??
          argResults?['collection-mods-directory'] as String? ??
          CollectionHelper().getModsDirectory();

      final mods = CollectionHelper().getModsList(
        metaData,
        modDirectory: modsDir,
      );
      final apiMods = CollectionHelper().getModsList(
        metaData,
        listFrostyCollectionMods: false,
      );

      _logger.info('Reading ${mods.length} mods');
      final fbMods = ModHelper.readFrostyMods(
        apiMods.map((e) => join(modsDir, basename(e))).toList(),
      );

      if (Platform.isLinux) {
        modsDir = 'Z:${modsDir.replaceAll('/', r'\')}';
      }

      gameplayMods = ModHelper.filterGameplayMods(fbMods);
      _logger.info(
        'Got ${fbMods.length} and ${gameplayMods.length} gameplay mods from collection',
      );

      modData = ModData(
        basePath: modsDir,
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

      modEntries[mod.filename.replaceAll(r'\', '/')] = ModEntry(
        maps,
        modes,
        mod.customFrostyData!.modeMappings ?? {},
        mod.customFrostyData!.modeNameOverrides ?? {},
      );
    }

    sl
      ..registerSingleton<LevelDeclarationService>(LevelDeclarationService())
      ..get<LevelDeclarationService>().set(modEntries);

    var startupCommands = <String>[];
    if (argResults?['startup-commands'] != null) {
      final file = File(argResults?['startup-commands'] as String);
      if (!file.existsSync()) {
        _logger.err('The specified startup commands file does not exist');
        return ExitCode.usage.code;
      }

      startupCommands = file.readAsLinesSync();
    }

    _logger.info('Kyber is listening on port $kyberPort');

    final server = KyberGRPCServer();
    await server.start();

    final maxPlayers = argResults?['max-players'] != null
        ? int.tryParse(argResults!['max-players'] as String) ?? 40
        : 40;
    server.setInitializeRequest(
      InitializeRequest(
        modData: modData,
        startupCommands: startupCommands,
        startServer: StartServerRequest(
          password:
              (Platform.environment['KYBER_SERVER_PASSWORD'] ??
                      argResults?['server-password'])
                  as String?,
          description:
              (Platform.environment['KYBER_SERVER_DESCRIPTION'] ??
                      argResults?['server-description'])
                  as String?,
          mapRotation: mapRotation.isNotEmpty
              ? mapRotation
              : [
                  LevelSetup(
                    map:
                        argResults?['map'] as String? ??
                        'S5_1/Levels/MP/Geonosis_01/Geonosis_01',
                    mode:
                        argResults?['mode'] as String? ??
                        'HeroesVersusVillains',
                  ),
                ],
          maxPlayers:
              int.tryParse(
                Platform.environment['KYBER_SERVER_MAX_PLAYERS'] ?? '',
              ) ??
              maxPlayers,
          name: serverName,
        ),
      ),
    );

    final pid = await startGame(
      gameSlug: 'star-wars-battlefront-2',
      gamePathOverride: argResults?['game-path'] as String?,
      gameArgs: [],
    );

    final moduleDir = modulePath;
    final moduleFile = join(moduleDir, 'Kyber.dll');
    _logger
      ..info('Game started with PID: $pid')
      ..info('Injecting Kyber from $moduleFile');

    await waitForKyberModule(pid: pid, path: moduleFile);

    sl.registerSingleton<MaximaGameInstance>(
      MaximaGameInstance(
        pid: pid,
        isDedicated: true,
        clientService: ClientGRPCService('', 0),
        mods: gameplayMods,
      ),
    );

    final completion = Completer<void>();
    gameEvents(pid: pid).distinct().listen(
      (event) async {
        if (event == 'GameRunning') {
          _logger.success('Kyber started');
        }
      },
      onDone: completion.complete,
      onError: (e) => completion.complete(),
    );

    await completion.future;

    return ExitCode.success.code;
  }
}
