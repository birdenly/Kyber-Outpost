// Created for Kyber Outpost (LAN Edition) - 2026-11-11.
import 'dart:io';

import 'package:kyber_launcher/features/lan/models/lan_nickname.dart';

/// Manages dynamic LAN ports for multiple instances (e.g. Nucleus Coop LAN play).
///
/// Ports can be configured via environment variables (such as `KYBER_SERVER_PORT`
/// or `KYBER_INSTANCE` / `PLAYER_INDEX` passed by Nucleus Coop) or dynamically
/// resolved by checking local socket availability on the host.
class InstanceManager {
  static const int baseGamePort = 25200;
  static const int baseHttpPort = 25202;
  static const int _portStride = 10;
  static const int _maxInstances = 16;

  static int _index = 0;
  static int _gamePort = baseGamePort;
  static int _httpPort = baseHttpPort;
  static String? _playerNameOverride;

  /// Zero-based instance index.
  static int get index => _index;

  /// Optional player nickname override supplied via `--name` / `-n`.
  static String? get playerNameOverride => _playerNameOverride;

  /// UDP port used for the local Battlefront II server.
  static int get gamePort => _gamePort;

  /// TCP port used for the local .fbmod HTTP server.
  static int get httpPort => _httpPort;

  /// Derives the HTTP mod server port matching a given game port.
  static int httpPortForGamePort(int gamePort) =>
      gamePort - baseGamePort + baseHttpPort;

  /// Suffix for the default player name (empty for instance 0).
  static String get nameSuffix => _index == 0 ? '' : ' ${_index + 1}';

  /// Extracts a valid `--name` or `-n` CLI nickname override from [args].
  static String? parsePlayerNameArg(List<String> args) {
    String? candidate;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if ((arg == '--name' || arg == '-n') && i + 1 < args.length) {
        candidate = args[++i];
      } else if (arg.startsWith('--name=')) {
        candidate = arg.substring('--name='.length);
      } else if (arg.startsWith('-n=')) {
        candidate = arg.substring('-n='.length);
      }
    }
    if (candidate == null) return null;
    final trimmed = candidate.trim();
    return validateLanNickname(trimmed) == null ? trimmed : null;
  }

  /// Picks the initial LAN nickname with CLI `--name` > saved Hive > default.
  static String resolveInitialNickname({
    String? savedName,
    String? overrideName,
    String? suffix,
  }) {
    final cliOverride = overrideName ?? _playerNameOverride;
    if (cliOverride != null && validateLanNickname(cliOverride) == null) {
      return cliOverride.trim();
    }
    if (savedName != null && validateLanNickname(savedName) == null) {
      return savedName.trim();
    }
    return 'Jedha${suffix ?? nameSuffix}';
  }

  /// Resolves CLI overrides and the dynamic game and HTTP ports.
  static Future<void> initialize([List<String> args = const []]) async {
    _playerNameOverride = parsePlayerNameArg(args);
    // 1. Check explicit port override from environment (e.g. from Nucleus Coop)
    final envPort =
        int.tryParse(Platform.environment['KYBER_SERVER_PORT'] ?? '');
    if (envPort != null && envPort > 0 && envPort < 65536) {
      _gamePort = envPort;
      _httpPort =
          int.tryParse(Platform.environment['KYBER_HTTP_PORT'] ?? '') ??
          httpPortForGamePort(_gamePort);
      _index = ((_gamePort - baseGamePort) ~/ _portStride).clamp(0, 99);
      return;
    }

    // 2. Check explicit instance index override (e.g. from Nucleus Coop PLAYER_INDEX)
    final envInstance = int.tryParse(
      Platform.environment['KYBER_INSTANCE'] ??
          Platform.environment['PLAYER_INDEX'] ??
          '',
    );
    if (envInstance != null && envInstance >= 0) {
      _index = envInstance;
      _gamePort = baseGamePort + _index * _portStride;
      _httpPort = baseHttpPort + _index * _portStride;
      return;
    }

    // 3. Dynamically probe socket availability on localhost
    for (var i = 0; i < _maxInstances; i++) {
      final testGamePort = baseGamePort + i * _portStride;
      final testHttpPort = baseHttpPort + i * _portStride;
      if (await _isPortAvailable(testGamePort, testHttpPort)) {
        _index = i;
        _gamePort = testGamePort;
        _httpPort = testHttpPort;
        return;
      }
    }
  }

  static Future<bool> _isPortAvailable(int udpPort, int tcpPort) async {
    try {
      final udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: false,
      );
      udpSocket.close();

      final tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        tcpPort,
      );
      await tcpServer.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
