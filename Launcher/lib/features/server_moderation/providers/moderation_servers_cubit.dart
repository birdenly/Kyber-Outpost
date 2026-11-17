// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/injection_container.dart';

class ModerationServersCubit extends Cubit<ModerationServersState> {
  ModerationServersCubit() : super(const ModerationServersInitial()) {
    emit(const ModerationServersLoading());
    loadServers();
    _updateTimer = Timer.periodic(
      const Duration(minutes: 1, seconds: 30),
      (_) => loadServers(),
    );
  }

  @override
  Future<void> close() async {
    _updateTimer?.cancel();
    await super.close();
  }

  Timer? _updateTimer;

  Future<void> loadServers() async {
    emit(const ModerationServersLoading());
    try {
      final servers = List<Server>.from(
        sl.get<LanDiscoveryService>().getDiscoveredServers(),
      );

      servers.sort((a, b) => b.playerCount.compareTo(a.playerCount));
      emit(ModerationServersLoaded(servers));
    } catch (_) {
      emit(const ModerationServersLoaded(<Server>[]));
    }
  }
}

abstract class ModerationServersState {
  const ModerationServersState();
}

class ModerationServersInitial extends ModerationServersState {
  const ModerationServersInitial();
}

class ModerationServersLoading extends ModerationServersState {
  const ModerationServersLoading();
}

class ModerationServersLoaded extends ModerationServersState {
  const ModerationServersLoaded(this.servers);

  final List<Server> servers;
}
