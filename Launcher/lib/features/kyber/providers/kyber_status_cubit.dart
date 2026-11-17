// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_mod_server_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class KyberStatusCubit extends Cubit<KyberStatusState> {
  bool joined = false;
  bool _wasHosting = false;

  KyberStatusCubit() : super(KyberStatusInitial()) {
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async => onTick(),
    );

    _rpcServerTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!sl.isRegistered<MaximaGameInstance>()) {
        return;
      }

      final state = await sl
          .get<MaximaGameInstance>()
          .clientService
          .commonClient
          .getInfo(Empty());
      if (!state.hasServer() && !state.client.hasServerId()) {
        return;
      }

      final id = state.hasServer() ? state.server.id : state.client.serverId;
      final server = _resolveLanServer(id, state);
      if (this.state is KyberStatusHosting) {
        emit(
          KyberStatusHosting(
            serverState: (this.state as KyberStatusHosting).serverState,
            server: server,
          ),
        );
      } else if (this.state is KyberStatusPlaying) {
        emit(
          KyberStatusPlaying(
            serverState: (this.state as KyberStatusPlaying).serverState,
            server: server,
            joined: joined,
          ),
        );
      } else {
        emit(KyberStatusNormal());
      }
    });
  }

  Server _resolveLanServer(String id, CommonState commonState) {
    final discoveredServers = sl
        .get<LanDiscoveryService>()
        .getDiscoveredServers();
    final discovered =
        discoveredServers.firstWhereOrNull((s) => s.id == id) ??
        ((id == 'lan_server' || id == 'lan_local' || id.isEmpty)
            ? discoveredServers.firstOrNull
            : null);
    if (discovered != null) {
      return discovered;
    }

    return Server(
      id: id.isNotEmpty ? id : 'lan_local',
      name: 'Kyber Outpost LAN Server',
      levelSetup: commonState.hasServer()
          ? commonState.server.levelSetup
          : LevelSetup(
              map: 'Levels/MP/Geonosis_01/Geonosis_01',
              mode: 'PlanetaryBattles',
            ),
      creator: 'LAN Host',
      ip: '127.0.0.1',
      port: InstanceManager.gamePort,
      maxPlayerCount: 40,
      playerCount: 1,
      requiresProxy: false,
      official: false,
      region: 'LAN',
    );
  }

  Future<void> onTick() async {
    final isRegistered = sl.isRegistered<MaximaGameInstance>();
    if (!isRegistered) {
      _clearHostedServer();
      joined = false;

      return emit(KyberStatusInitial());
    }

    try {
      final client = sl.get<MaximaGameInstance>();
      final data = await client.clientService.commonClient.getInfo(Empty());
      if (data.hasServer()) {
        _wasHosting = true;
        sl.get<LanDiscoveryService>().updateHostedState(data.server);
        sl.get<LanModServerService>().updateHostedState(data.server);
      } else {
        _clearHostedServer();
      }

      final isKyber = data.hasClient() || data.hasServer();
      var server = (state is KyberStatusPlaying || state is KyberStatusHosting)
          ? ((state as dynamic).server as Server?)
          : null;
      if (isKyber &&
          (state is KyberStatusInitial ||
              ((state is KyberStatusPlaying || state is KyberStatusHosting) &&
                  (state as dynamic).server == null))) {
        final id = data.hasServer() ? data.server.id : data.client.serverId;
        server = _resolveLanServer(id, data);
      }

      if (data.hasClient()) {
        emit(
          KyberStatusPlaying(
            serverState: data.server,
            server: server,
            joined: joined,
          ),
        );
      } else if (data.hasServer()) {
        emit(KyberStatusHosting(serverState: data.server, server: server));
      } else {
        emit(KyberStatusNormal());
      }
    } catch (e) {
      if (e is GrpcError) {
        if (e.code == StatusCode.unavailable || e.code == StatusCode.unknown) {
          return;
        }

        _logger.severe('GRPC Error: ${e.message}');
      }

      print(e);
      rethrow;
    }
  }

  final _logger = Logger('status_cubit');

  void _clearHostedServer() {
    if (!_wasHosting) return;
    _wasHosting = false;
    sl.get<LanDiscoveryService>().stopBroadcasting();
    sl.get<LanModServerService>().clearHostedServer();
  }

  @override
  Future<void> close() {
    _statusTimer.cancel();
    _rpcServerTimer.cancel();
    return super.close();
  }

  late Timer _statusTimer;
  late Timer _rpcServerTimer;
}

class KyberStatusState {}

class KyberStatusInitial extends KyberStatusState {}

class KyberStatusNormal extends KyberStatusState {}

class KyberStatusPlaying extends KyberStatusState {
  KyberStatusPlaying({
    required this.serverState,
    this.server,
    this.joined = false,
  });

  final ServerState serverState;
  final Server? server;
  final bool joined;
}

class KyberStatusHosting extends KyberStatusState {
  KyberStatusHosting({required this.serverState, this.server});

  final ServerState serverState;
  final Server? server;
}
