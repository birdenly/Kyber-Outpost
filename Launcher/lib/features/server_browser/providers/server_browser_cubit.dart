// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/gen/Proto/mod_bridge.pb.dart' as mb;
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/download_manager/models/download_link_type.dart'
    as dl;
import 'package:kyber_launcher/features/download_manager/models/download_request.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/download_manager/repositories/download_repository.dart';
import 'package:kyber_launcher/features/download_manager/services/download_orchestrator.dart';
import 'package:kyber_launcher/features/download_manager/services/mod_bridge_service.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_server_helper.dart';
import 'package:kyber_launcher/features/lan/dialogs/lan_mod_download_dialog.dart';
import 'package:kyber_launcher/features/lan/services/lan_mod_server_service.dart';
import 'package:kyber_launcher/features/mod_browser/providers/mod_browser_cubit.dart';
import 'package:kyber_launcher/features/mods/helper/mod_helper.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/nexusmods/dialogs/nexusmods_login.dart';
import 'package:kyber_launcher/features/nexusmods/exceptions/missing_nexus_auth_exception.dart';
import 'package:kyber_launcher/features/nexusmods/services/mod_finder_service.dart';
import 'package:kyber_launcher/features/server_browser/models/server_entry.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';

part 'server_browser_state.dart';

class ServerBrowserCubit extends Cubit<ServerBrowserState> {
  ServerBrowserCubit() : super(const .new());

  Timer? _downloadChecker;
  bool _running = false;
  String? _joiningPassword;
  bool _joiningSpectator = false;
  ModCollectionMetaData? _joiningCollection;
  bool _joining = false;

  @override
  Future<void> close() {
    _downloadChecker?.cancel();
    return super.close();
  }

  void selectServer(ServerEntry? server) {
    emit(state.copyWith(selectedServer: server));
  }

  void clearServer() {
    emit(.new(joiningServer: state.joiningServer));
  }

  Future<void> joinServer({
    bool enabledDownload = true,
    String? serverPassword,
    bool spectator = false,
    ModCollectionMetaData? cosmeticCollection,
    Server? server,
  }) async {
    if (_joining) return;

    final serverInfo = server ?? state.selectedServer?.serverInfo;
    if (serverInfo == null) return;

    _joining = true;
    try {
      await _doJoinServer(
        serverInfo,
        enabledDownload: enabledDownload,
        serverPassword: serverPassword,
        spectator: spectator,
        cosmeticCollection: cosmeticCollection,
      );
    } finally {
      _joining = false;
    }
  }

  Future<void> _doJoinServer(
    Server serverInfo, {
    required bool enabledDownload,
    required bool spectator,
    String? serverPassword,
    ModCollectionMetaData? cosmeticCollection,
  }) async {
    if (hasAllRequiredMods(serverInfo)) {
      await _joinServer(
        serverInfo,
        serverPassword: serverPassword,
        spectator: spectator,
        cosmeticCollection: cosmeticCollection,
      );
    } else if (enabledDownload) {
      final missingMods = serverInfo.mods
          .where((mod) => !ModHelper.isInstalled(mod.name, mod.version))
          .toList();

      var downloadSource = LanModDownloadSource.lanHostWithInternetFallback;
      if (navigatorKey.currentContext != null) {
        final chosenSource = await showKyberDialog<LanModDownloadSource>(
          context: navigatorKey.currentContext!,
          builder: (_) => LanModDownloadDialog(
            server: serverInfo,
            missingMods: missingMods,
          ),
        );
        if (chosenSource == null) {
          return;
        }
        downloadSource = chosenSource;
      }

      _joiningPassword = serverPassword;
      _joiningSpectator = spectator;
      _joiningCollection = cosmeticCollection;
      emit(
        state.copyWith(
          joiningServer: serverInfo,
        ),
      );
      await _startDownloads(downloadSource: downloadSource);
    }
  }

  Future<BanInfo?> _isBanned(Server serverInfo) async {
    return null;
  }

  bool hasAllRequiredMods([Server? serverInfo]) {
    final server =
        serverInfo ?? state.joiningServer ?? state.selectedServer?.serverInfo;
    if (server == null) return false;

    return server.mods.every(
      (mod) => ModHelper.isInstalled(mod.name, mod.version),
    );
  }

  Future<void> _joinServer(
    Server serverInfo, {
    String? serverPassword,
    bool spectator = false,
    ModCollectionMetaData? cosmeticCollection,
  }) async {
    try {
      final server = state.selectedServer;

      await KyberServerHelper.joinServer(
        serverInfo,
        selectedCollection: cosmeticCollection,
        spectator: spectator,
        password: serverPassword,
        queueIfFull: true,
      );

      emit(ServerBrowserState(selectedServer: server));
    } catch (e, s) {
      Logger('server_browser').severe('Error joining server!', e, s);
      emit(const ServerBrowserState());
      if (e is GrpcError) {
        if (e.code == StatusCode.notFound) {
          return NotificationService.showNotification(
            message: 'Server not found!',
            severity: InfoBarSeverity.error,
          );
        }
      }

      NotificationService.showNotification(
        title: 'Error joining server!',
        message: e.toString(),
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<bool> _nexusLogin() async {
    if (!Preferences.nexusMods.isLoggedIn) {
      final result = await showKyberDialog<bool?>(
        context: navigatorKey.currentContext!,
        routeSettings: const RouteSettings(name: 'nexusmods_login'),
        builder: (_) => const NexusmodsLogin(),
      );

      if (result == null || !result) {
        NotificationService.showNotification(
          message: 'You need to login to NexusMods to download mods!',
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _handleDownload(
    mb.Mod mod, {
    required ServerMod serverMod,
  }) async {
    try {
      final downloadUrl = mod.link.contains('https://www.nexusmods')
          ? '${mod.link}&file_id=${mod.fileId}'
          : mod.link;
      final filename = mod.link.split('/').last.split('?').first;

      if (downloadUrl.startsWith('https://www.nexusmods')) {
        final result = await _nexusLogin();
        if (!result) {
          throw MissingNexusAuthException();
        }
      }

      const repository = DownloadRepository();
      final tasks = await repository.getActiveTasks();
      final existingTask = tasks.firstWhereOrNull(
        (e) => e.task.displayName == mod.name,
      );
      if (existingTask != null) {
        if (existingTask.status == TaskStatus.paused) {
          await sl.get<DownloadOrchestrator>().resumeDownload(
            existingTask.taskId,
          );
        }
        return;
      }

      final request = DownloadRequest(
        link: downloadUrl,
        displayName: mod.name,
        linkType: downloadUrl.startsWith('https://www.nexusmods')
            ? dl.DownloadLinkType.nexus
            : dl.DownloadLinkType.direct,
        size: mod.fileSize.toInt(),
        filename: filename,
        priority: 1,
        metadata: {
          'name': serverMod.name,
          'version': serverMod.version,
          'link': serverMod.link,
          'fileSize': serverMod.fileSize.toInt(),
        },
      );

      await sl.get<DownloadOrchestrator>().enqueueDownload(request);
    } on MissingNexusAuthException {
      rethrow;
    } catch (e, s) {
      Logger(
        'server_browser',
      ).severe('Error finding download for ${mod.name}', e, s);
      NotificationService.showNotification(
        message: 'Error finding download for ${mod.name}',
      );
    }
  }

  Future<bool> _tryDownloadFromLanHost(
    Server serverInfo,
    ServerMod serverMod,
    int modIndex,
  ) async {
    final hostIp = serverInfo.ip.isNotEmpty ? serverInfo.ip : '127.0.0.1';
    final httpPort =
        int.tryParse(serverInfo.meta['lan_http_port'] ?? '25202') ??
        LanModServerService.kDefaultPort;

    final directUrl = LanModServerService.buildDirectModUrl(
      hostIp: hostIp,
      httpPort: httpPort,
      mod: serverMod,
      index: modIndex,
    );

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final headResp = await dio.head<void>(directUrl);
      if (headResp.statusCode != 200 && headResp.statusCode != 206) {
        return false;
      }

      final safeName = serverMod.name
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .trim();
      final safeVersion = serverMod.version
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .trim();
      final filename = '$safeName ($safeVersion).fbmod';

      final request = DownloadRequest(
        link: directUrl,
        displayName: '${serverMod.name} (${serverMod.version})',
        linkType: dl.DownloadLinkType.direct,
        size: serverMod.fileSize.toInt(),
        filename: filename,
        priority: 1,
        metadata: {
          'name': serverMod.name,
          'version': serverMod.version,
          'link': serverMod.link,
          'fileSize': serverMod.fileSize.toInt(),
        },
      );

      return sl.get<DownloadOrchestrator>().enqueueDownload(request);
    } catch (e) {
      Logger('server_browser').fine(
        'Mod ${serverMod.name} not available from LAN Host ($directUrl): $e',
      );
      return false;
    }
  }

  Future<void> _startDownloads({
    LanModDownloadSource downloadSource =
        LanModDownloadSource.lanHostWithInternetFallback,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return;
    }

    unawaited(sl.get<LanModServerService>().enablePeerModSeeding());

    var failedMods = 0;

    const repository = DownloadRepository();
    final currentDownload = await repository.getRunningTask();
    if (currentDownload != null) {
      await sl.get<DownloadOrchestrator>().pauseDownload(
        currentDownload.taskId,
      );
      final name = currentDownload.task.displayName;
      NotificationService.info(message: 'Paused download for $name');
    }

    final serverInfo = state.joiningServer ?? server.serverInfo;

    final allMissingServerMods = serverInfo.mods
        .where((mod) => !ModHelper.isInstalled(mod.name, mod.version))
        .toList();

    final remainingForInternet = <ServerMod>[];

    if (downloadSource == LanModDownloadSource.lanHostOnly ||
        downloadSource == LanModDownloadSource.lanHostWithInternetFallback) {
      for (final serverMod in allMissingServerMods) {
        final modIndex = serverInfo.mods.indexOf(serverMod);
        final enqueued = await _tryDownloadFromLanHost(
          serverInfo,
          serverMod,
          modIndex,
        );
        if (!enqueued) {
          if (downloadSource == LanModDownloadSource.lanHostOnly) {
            failedMods++;
          } else {
            remainingForInternet.add(serverMod);
          }
        }
      }
    } else {
      remainingForInternet.addAll(allMissingServerMods);
    }

    if (remainingForInternet.isNotEmpty) {
      final isOnline = await ModBrowserCubit.hasInternetConnection();
      if (!isOnline) {
        for (final serverMod in remainingForInternet) {
          final modIndex = serverInfo.mods.indexOf(serverMod);
          final enqueued = await _tryDownloadFromLanHost(
            serverInfo,
            serverMod,
            modIndex,
          );
          if (!enqueued) {
            failedMods++;
          }
        }
      } else {
        final missingMods = remainingForInternet.map(
          (m) => mb.BridgeMod(
            name: m.name,
            version: m.version,
            id: serverInfo.mods.indexOf(m).toString(),
          ),
        );

        final chunks = missingMods.slices(50);
        final modsToDownload = <mb.Mod>[];
        final notFound = <mb.BridgeMod>[];
        for (final chunk in chunks) {
          final resp = await sl
              .get<ModBridgeGRPCService>()
              .searchClient
              .searchMods(
                mb.SearchModsRequest(mods: chunk),
              )
              .catchError((e) {
                Logger('server_browser').warning(
                  'ModBridge search unavailable, falling back to direct/LAN: $e',
                );
                return mb.SearchModsResponse(notFound: chunk);
              });

          if (resp.mods.isEmpty && resp.notFound.isEmpty) {
            notFound.addAll(chunk);
            continue;
          }

          modsToDownload.addAll(resp.mods);
          notFound.addAll(resp.notFound);
        }

        final finderService = ModFinderService();
        for (final mod in notFound) {
          final serverMod = serverInfo.mods.firstWhere(
            (e) => e.name == mod.name && e.version == mod.version,
          );

          var resolvedFromNexus = false;
          if (serverMod.link.isNotEmpty) {
            try {
              final resp = await finderService.searchMod(
                serverMod.link,
                mod.version,
              );
              if (resp.$2.isNotEmpty) {
                final modId = resp.$1;
                final file = resp.$2.first;
                final link =
                    'https://www.nexusmods.com/starwarsbattlefront22017/mods/$modId?tab=files&file_id=${file.fileId}';
                final fMod = mb.Mod(
                  name: file.name,
                  link: link,
                  modId: .parse(modId),
                  fileId: .parse(file.fileId),
                  id: serverInfo.mods.indexOf(serverMod).toString(),
                );

                modsToDownload.add(fMod);
                resolvedFromNexus = true;
              }
            } catch (_) {}
          }

          if (!resolvedFromNexus) {
            final modIndex = serverInfo.mods.indexOf(serverMod);
            final enqueuedFromLan = await _tryDownloadFromLanHost(
              serverInfo,
              serverMod,
              modIndex,
            );
            if (!enqueuedFromLan) {
              failedMods++;
            }
          }
        }

        var nexusLoginPrompted = false;
        for (final mod in modsToDownload) {
          final serverMod = serverInfo.mods[int.parse(mod.id)];

          if (mod.link.contains('nexusmods') && nexusLoginPrompted) {
            continue;
          }

          try {
            await _handleDownload(mod, serverMod: serverMod);
          } on MissingNexusAuthException {
            nexusLoginPrompted = true;
            continue;
          }
        }
      }
    }

    if (failedMods > 0) {
      NotificationService.showNotification(
        message:
            "For $failedMods ${failedMods > 1 ? "mods" : "mod"} no download could be found. Some mods can be found in the mod browser.",
      );
    }

    _downloadChecker = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (_running) {
        return;
      }

      _running = true;
      await sl<ModService>().refreshCompleter.future;
      if (!hasAllRequiredMods()) {
        final cubit = BlocProvider.of<DownloadCubit>(
          navigatorKey.currentContext!,
        );
        final states = <TaskStatus>[.enqueued, .running, .waitingToRetry];
        final tasks = cubit.state is DownloadLoaded
            ? (cubit.state as DownloadLoaded).tasks
            : <TaskRecord>[];
        final runningTasks = tasks
            .where((e) => states.contains(e.status))
            .toList();

        _running = false;

        if (runningTasks.isEmpty) {
          Logger.root.info('No more running downloads, stopping checker.');
          timer.cancel();
          _downloadChecker = null;
          emit(.new(selectedServer: server));
        }

        return;
      }

      NotificationService.showNotification(
        message: 'All mods downloaded! Joining ${serverInfo.name}...',
      );

      timer.cancel();
      _downloadChecker = null;
      _running = false;

      if (router.routeInformationProvider.value.uri.toString() != '/home') {
        await router.pushReplacement('/home');
      }

      if (state.selectedServer != server) {
        selectServer(server);
      }

      final serverPassword = _joiningPassword;
      final spectator = _joiningSpectator;
      final cosmeticCollection = _joiningCollection;
      _joiningPassword = null;
      _joiningSpectator = false;
      _joiningCollection = null;
      await _joinServer(
        serverInfo,
        serverPassword: serverPassword,
        spectator: spectator,
        cosmeticCollection: cosmeticCollection,
      );
    });
  }
}
