// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';

class KyberProxyCubit extends Cubit<KyberProxyState> {
  KyberProxyCubit() : super(KyberProxyState(loading: true)) {
    loadProxies();
  }

  Future<void>? _ready;
  bool _loading = true;

  bool get isLoading => _loading;

  Future<void> ensureReady() => _ready ?? Future<void>.value();

  void selectProxy(String proxyId) {
    Preferences.general.proxy = proxyId;
    emit(state.copyWith(selectedProxy: proxyId));
  }

  Future<void> loadProxies({List<ProxyInfo>? initialProxies}) {
    return _ready = _loadProxies(initialProxies: initialProxies)
        .whenComplete(() => _loading = false);
  }

  Future<void> _loadProxies({List<ProxyInfo>? initialProxies}) async {
    final lanInfo = ProxyInfo(
      name: 'LAN Direct (P2P)',
      ip: '127.0.0.1',
      flag: '',
      id: 'lan_direct',
    );
    final entries = [KyberProxy(ping: 1, proxy: lanInfo)];
    Preferences.general.proxy = 'lan_direct';
    emit(
      state.copyWith(
        proxies: entries,
        selectedProxy: 'lan_direct',
        loading: false,
      ),
    );
  }
}

class KyberProxy {
  KyberProxy({required this.ping, required this.proxy});

  int ping;
  ProxyInfo proxy;
}

class KyberProxyState {
  KyberProxyState({
    this.proxies = const [],
    this.selectedProxy = '',
    this.loading = false,
  });

  List<KyberProxy> proxies;
  String selectedProxy;

  bool loading;

  KyberProxyState copyWith({
    List<KyberProxy>? proxies,
    String? selectedProxy,
    bool? loading,
  }) {
    return KyberProxyState(
      proxies: proxies ?? this.proxies,
      selectedProxy: selectedProxy ?? this.selectedProxy,
      loading: loading ?? this.loading,
    );
  }
}
