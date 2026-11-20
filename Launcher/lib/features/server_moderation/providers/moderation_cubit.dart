// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

class ModerationCubit extends Cubit<ModerationServerState> {
  ModerationCubit() : super(const ModerationServerState()) {
    botChangeStream = ReplaySubject<(int, int)>();
    botChangeStream!.debounceTime(const Duration(milliseconds: 300)).listen((
      event,
    ) {
      sendCommand('/AutoPlayers.AllowAddAutoFillPlayers 1');
      sendCommand('/AutoPlayers.ForceApplyGameplayBotsCount 1');
      sendCommand(
        '/AutoPlayers.ForceFillGameplayBotsTeam${event.$1} ${event.$2}',
      );
    });
  }

  final _logger = Logger('moderation_cubit');
  Timer? _keepAliveTimer;

  ReplaySubject<(int, int)>? botChangeStream;

  int _loadId = 0;

  @override
  Future<void> close() {
    unloadServer();
    return super.close();
  }

  Future<void> loadModerators() async {
    emit(state.copyWith(moderators: const []));
  }

  Future<void> loadPunishments() async {
    emit(state.copyWith(punishments: const []));
  }

  Future<void> unbanPlayer(String id) async {
    _logger.info('Unbanning player $id in LAN mode');
  }

  Future<void> promotePlayer(String id) async {
    _logger.info('Promoting player $id in LAN mode');
  }

  Future<void> demotePlayer(String id) async {
    _logger.info('Demoting player $id in LAN mode');
  }

  Future<void> banPlayer({
    required String id,
    required String reason,
    required Duration duration,
  }) async {
    final banReason = reason.isEmpty ? 'Banned by host' : reason;
    _logger.info('Banning/kicking player $id in LAN mode ($banReason)');
    sendCommand('/Kyber.KickById $id $banReason');
  }

  void swapTeam(ServerPlayer player) {
    _logger.info('Swapping team for player ${player.id}');

    final team = player.teamId == 1 ? 2 : 1;
    sendCommand('/Kyber.SetTeamById ${player.id} $team');
  }

  Future<void> kickPlayer(
    String id, {
    String? reason = 'Kicked by moderator',
  }) async {
    final kickReason = (reason == null || reason.isEmpty)
        ? 'Kicked by host'
        : reason;
    _logger.info('Kicking player $id in LAN mode ($kickReason)');
    sendCommand('/Kyber.KickById $id $kickReason');
  }

  void sendCommand(String input) {
    final command = switch (input) {
      final command when command.startsWith('/') => command.substring(1),
      _ => 'Kyber.Broadcast $input',
    };

    _logger.info('Sending local LAN command: $command');
    if (sl.isRegistered<MaximaGameInstance>()) {
      unawaited(
        sl
            .get<MaximaGameInstance>()
            .clientService
            .commonClient
            .runCommand(RunCommandRequest(command: command))
            .catchError((Object e) {
              _logger.warning('Failed to run local command: $e');
              return Empty();
            }),
      );
    }
  }

  void unloadServer() {
    _logger.info('Unloading server');

    _loadId++;
    _keepAliveTimer?.cancel();

    emit(const ModerationServerState());

    if (isClosed) {
      return;
    }
  }

  Future<void> loadServer(Server server) async {
    emit(ModerationServerState(id: server.id, server: server));
  }

  Future<void> selectServer({String? serverId}) async {
    if (state.server == null && serverId == null) {
      return;
    }

    final loadId = ++_loadId;
    _keepAliveTimer?.cancel();

    try {
      final id = serverId ?? state.id ?? 'lan_local';
      _logger.info('Loading LAN server $id');
      emit(ModerationServerState(id: id, selected: true));
      final discoveredServers = sl
          .get<LanDiscoveryService>()
          .getDiscoveredServers();
      final server =
          discoveredServers.firstWhereOrNull((s) => s.id == id) ??
          ((id == 'lan_server' || id == 'lan_local')
              ? discoveredServers.firstOrNull
              : null) ??
          state.server ??
          Server(
            id: id,
            name: Preferences.hostServer.name.isNotEmpty
                ? Preferences.hostServer.name
                : 'LAN Server',
            description: Preferences.hostServer.description,
            creator: 'LAN Host',
            ip: '127.0.0.1',
            port: InstanceManager.gamePort,
            maxPlayerCount: Preferences.hostServer.maxPlayers,
            playerCount: 1,
            requiresProxy: false,
            official: false,
            region: 'LAN',
            levelSetup: LevelSetup(
              map: 'Levels/MP/Geonosis_01/Geonosis_01',
              mode: 'PlanetaryBattles',
            ),
          );
      if (loadId != _loadId || isClosed) {
        return;
      }
      emit(state.copyWith(id: id, server: server));

      hostingForm.currentState?.fields['serverName']?.didChange(server.name);

      Future<void> pollLocalPlayers() async {
        if (!sl.isRegistered<MaximaGameInstance>() ||
            loadId != _loadId ||
            isClosed) {
          return;
        }
        try {
          final client = sl.get<MaximaGameInstance>().clientService;
          final data = await client.commonClient.getInfo(Empty());
          if (data.hasServer() && loadId == _loadId && !isClosed) {
            emit(state.copyWith(players: data.server.playerList));
          }
        } catch (_) {}
      }

      await pollLocalPlayers();
      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: 3),
        (timer) {
          if (loadId != _loadId || isClosed) {
            timer.cancel();
            return;
          }
          unawaited(pollLocalPlayers());
        },
      );
    } on GrpcError catch (e, s) {
      if (loadId != _loadId) {
        return;
      }
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message:
            e.message ??
            'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on SocketException catch (e, s) {
      if (loadId != _loadId) {
        return;
      }
      _logger.severe('Socket error:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } catch (e, s) {
      if (loadId != _loadId) {
        return;
      }
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    }
  }
}

class ModerationServerState {
  const ModerationServerState({
    this.id,
    this.server,
    this.players = const [],
    this.commands = const [],
    this.moderators = const [],
    this.punishments = const [],
    this.selected = false,
  });

  final String? id;
  final bool selected;
  final Server? server;
  final List<ServerPlayer> players;
  final List<Punishment> punishments;
  final List<String> commands;
  final List<KyberPlayer> moderators;

  bool isModerator(String userId) {
    return moderators.any((moderator) => moderator.id == userId);
  }

  ModerationServerState copyWith({
    String? id,
    Server? server,
    List<KyberPlayer>? moderators,
    List<ServerPlayer>? players,
    List<String>? commands,
    List<Punishment>? punishments,
    bool? selected,
  }) {
    return ModerationServerState(
      id: id ?? this.id,
      server: server ?? this.server,
      players: players ?? this.players,
      commands: commands ?? this.commands,
      punishments: punishments ?? this.punishments,
      selected: selected ?? this.selected,
      moderators: moderators ?? this.moderators,
    );
  }
}
