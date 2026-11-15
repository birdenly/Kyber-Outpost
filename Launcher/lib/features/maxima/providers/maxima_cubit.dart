// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/windows_env.dart';
import 'package:kyber_launcher/features/ea/services/search_service.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_status_helper.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_api_status_cubit.dart';
import 'package:kyber_launcher/features/lightswitch/models/status.dart';
import 'package:kyber_launcher/features/lan/models/lan_nickname.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/gen/rust/api/outpost.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:window_to_front/window_to_front.dart';

part '../models/maxima_state.dart';

class MaximaCubit extends Cubit<MaximaState> {
  MaximaCubit() : super(MaximaState.initial()) {
    if (!sl.isRegistered<MaximaCubit>()) {
      sl.registerSingleton<MaximaCubit>(this);
    }
    init();
  }

  final logger = Logger('outpost_profile');

  Timer? _updateTimer;

  bool _loggingIn = false;

  @override
  Future<void> close() async {
    if (sl.isRegistered<MaximaCubit>()) {
      sl.unregister<MaximaCubit>();
    }
    _updateTimer?.cancel();
    await super.close();
  }

  String? getUsername() => state.servicePlayer?.displayName;

  Future<void> setLanNickname(String name) async {
    final validation = validateLanNickname(name);
    if (validation != null) throw StateError(validation);
    if (sl.isRegistered<MaximaGameInstance>()) {
      throw StateError('Close your game before changing your nickname.');
    }
    final nickname = name.trim();
    final profile = await getLocalProfile(name: nickname);
    await box.put('lanPlayerName', nickname);
    emit(state.copyWith(servicePlayer: profile));
  }

  Future<void> verifyToken([int tries = 0]) async {
    return;
  }

  void removeDiscordData() {
    emit(
      MaximaState(
        status: state.status,
        error: state.error,
        entitlements: state.entitlements,
        loggedIn: state.loggedIn,
        gameRunning: state.gameRunning,
        isPatron: state.isPatron,
        servicePlayer: state.servicePlayer,
      ),
    );
  }

  Future<void> init({bool skipSetupCheck = false}) async {
    if (state.status == MaximaStatus.loaded ||
        !skipSetupCheck && !Preferences.general.setup) {
      return;
    }

    emit(state.copyWith(status: MaximaStatus.starting));
    try {
      await initializeRuntime();
    } on Object catch (error, stackTrace) {
      logger.severe('Could not initialize Outpost', error, stackTrace);
      emit(MaximaState(status: MaximaStatus.error, error: error.toString()));
      rethrow;
    }

    await requestLogin(skipMaximaCheck: true);
    if (state.status == .error) {
      return;
    }

    emit(
      state.copyWith(
        loggedIn: true,
        servicePlayer: state.servicePlayer,
        status: .loaded,
      ),
    );
  }

  Future<void> logout() async {
    // There is no EA account to log out of in a local session.
    exit(0);
  }

  Future<void> downloadFiles() async {
    emitError(
      'Copy the complete Outpost Release package next to the game executable.',
    );
  }

  void emitError(String error) {
    emit(
      MaximaState(
        status: .error,
        error: error,
        servicePlayer: state.servicePlayer,
      ),
    );
  }

  Future<void> requestLogin({bool skipMaximaCheck = false}) async {
    if (_loggingIn) {
      return Future.error('Already logging in');
    }

    final cubit = navigatorKey.currentContext!.read<LightswitchCubit>();
    late LightswitchStatus status;
    if (!cubit.firstRequestCompleter.isCompleted) {
      status = await cubit.firstRequestCompleter.future;
    } else {
      status = cubit.state;
    }

    if (status.status == KyberStatusEnum.down) {
      _updateTimer?.cancel();

      logger.severe('Kyber is down... Skipping login');

      return emit(
        MaximaState(
          status: .error,
          error: 'KyberDown',
          servicePlayer: state.servicePlayer,
        ),
      );
    }

    if (state.status != .loaded && !skipMaximaCheck) {
      await init(skipSetupCheck: true);
    }

    _loggingIn = true;
    ServicePlayer? servicePlayer;
    try {
      logger.info('Requesting login (LAN Mode)');

      emit(state.copyWith(status: MaximaStatus.loading));

      final savedName = box.get('lanPlayerName') as String?;
      final nickname =
          savedName != null && validateLanNickname(savedName) == null
          ? savedName
          : 'OutpostPlayer${InstanceManager.nameSuffix}';
      servicePlayer = await getLocalProfile(name: nickname);

      await WindowToFront.activate();

      logger.info(
        'Initialized LAN session as ${servicePlayer.displayName}',
      );

      ProcessEnv.set('KYBER_ONLINE_MODE', '0');
      ProcessEnv.set('KYBER_API_TOKEN', 'lan_offline_token');

      emit(
        state.copyWith(
          loggedIn: true,
          entitlements: UserEntitlement.values
              .where((e) => e != UserEntitlement.staff)
              .toList(),
          servicePlayer: servicePlayer,
          status: MaximaStatus.loaded,
          isPatron: false,
        ),
      );

      if (Preferences.customization.customBackground && !state.canUsePerks()) {
        Preferences.customization.customBackground = false;
      }

      if (state.canUsePerks() &&
          Preferences.customization.activeColor != kDefaultActiveColor) {
        kActiveColor = Preferences.customization.activeColor;
        Preferences.customization.activeColor = kActiveColor;
      }

      _loggingIn = false;

      logger.info('Initialized (LAN Mode)');

      if (!sl.isRegistered<SearchService>()) {
        sl.registerSingleton<SearchService>(
          SearchService(),
        );
      }

      return;
    } on Object catch (error, stackTrace) {
      logger.severe(
        'Could not initialize the local profile',
        error,
        stackTrace,
      );
      emit(
        MaximaState(
          status: MaximaStatus.error,
          error: error is AnyhowException ? error.message : error.toString(),
          servicePlayer: servicePlayer,
        ),
      );
    } finally {
      _loggingIn = false;
    }

    return Future.error('Login failed');
  }
}
