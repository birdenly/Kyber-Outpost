// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class IngameViewCubit extends Cubit<IngameViewState> {
  IngameViewCubit() : super(const IngameViewState());

  final _logger = Logger('ingame_view_cubit');
  Timer? _keepAliveTimer;

  WebSocketChannel? _channel;

  int _loadId = 0;

  @override
  Future<void> close() {
    unloadServer();
    return super.close();
  }

  void unloadServer() {
    _logger.info('Unloading server');

    _loadId++;
    _channel?.sink.close();
    _channel = null;
    _keepAliveTimer?.cancel();

    emit(const IngameViewState());

    if (isClosed) {
      return;
    }
  }

  Future<void> loadServer(Server server) async {
    emit(IngameViewState(id: server.id, server: server));
    await selectServer(serverId: server.id);
  }

  Future<void> selectServer({String? serverId}) async {
    if (state.server == null && serverId == null) {
      return;
    }

    final loadId = ++_loadId;
    unawaited(_channel?.sink.close());
    _channel = null;
    _keepAliveTimer?.cancel();

    try {
      final id = serverId ?? state.id;
      _logger.info('Loading LAN server $id');
      final server =
          state.server ??
          sl
              .get<LanDiscoveryService>()
              .getDiscoveredServers()
              .firstWhereOrNull((s) => s.id == id) ??
          Server(
            id: id ?? 'lan_local',
            name: 'LAN Server',
            creator: 'LAN Host',
            ip: '127.0.0.1',
            port: InstanceManager.gamePort,
            maxPlayerCount: 40,
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
      return;
    } on WebSocketException catch (e, s) {
      if (loadId != _loadId) {
        return;
      }
      var error = 'Failed to connect to websocket';
      switch (e.httpStatusCode ?? 0) {
        case 401:
          error = 'Failed to connect to websocket: Unauthorized';
        case 404:
          error = 'The specified server was not found';
      }

      _logger.severe('Failed to connect to websocket', e, s);
      NotificationService.error(message: error);
      unloadServer();
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

class IngameViewState {
  const IngameViewState({
    this.id,
    this.server,
    this.players = const [],
    this.commands = const [],
  });

  final String? id;
  final Server? server;
  final List<ServerPlayer> players;
  final List<String> commands;

  IngameViewState copyWith({
    String? id,
    Server? server,
    List<ServerPlayer>? players,
    List<String>? commands,
  }) {
    return IngameViewState(
      id: id ?? this.id,
      server: server ?? this.server,
      players: players ?? this.players,
      commands: commands ?? this.commands,
    );
  }
}
