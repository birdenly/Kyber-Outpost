// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_status_helper.dart';
import 'package:kyber_launcher/features/lightswitch/models/status.dart';

class LightswitchCubit extends Cubit<LightswitchStatus> {
  Timer? _refreshTimer;
  DateTime? _nextRefresh;
  final _firstRequestCompleter = Completer<LightswitchStatus>();

  Completer<LightswitchStatus> get firstRequestCompleter =>
      _firstRequestCompleter;

  DateTime? get nextRefresh => _nextRefresh;

  bool isEnabled(KyberFeature feature) =>
      state.isEnabled(feature, environment: Preferences.admin.apiEnv);

  static bool isFeatureEnabled(KyberFeature feature) =>
      navigatorKey.currentContext?.read<LightswitchCubit>().isEnabled(
        feature,
      ) ??
      true;

  LightswitchCubit() : super(LightswitchStatus.defaultStatus()) {
    _refresh();
  }

  Future<void> _refresh() async {
    _nextRefresh = DateTime.now().add(const .new(minutes: 5));
    final status = LightswitchStatus(
      defaultEnvironment: 'prod',
      environments: [],
      status: KyberStatusEnum.up,
      message: 'Kyber Outpost LAN Mode',
    );

    if (!_firstRequestCompleter.isCompleted) {
      _firstRequestCompleter.complete(status);
    }
    emit(status);
  }

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await super.close();
  }
}
