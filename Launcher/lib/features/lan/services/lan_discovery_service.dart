// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/features/lan/services/lan_mod_server_service.dart';
import 'package:logging/logging.dart';

class _DiscoveredLanServer {
  _DiscoveredLanServer({
    required this.server,
    required this.lastSeen,
  });

  final Server server;
  DateTime lastSeen;
}

class LanDiscoveryService {
  static const int kDiscoveryPort = 25201;
  static const String _kAnnounceMagic = 'KYBER_OUTPOST_LAN_V1';
  static const String _kProbeMagic = 'KYBER_OUTPOST_DISCOVER_V1';
  static const Duration _kBroadcastInterval = Duration(seconds: 3);
  static const Duration _kServerTtl = Duration(seconds: 12);

  final Logger _logger = Logger('lan_discovery');
  final Map<String, _DiscoveredLanServer> _discovered =
      <String, _DiscoveredLanServer>{};

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Map<String, dynamic>? _hostedPayload;

  Future<void> startListening() async {
    if (_socket != null) {
      return;
    }

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onSocketEvent);
      _logger.info('LAN UDP discovery listening on 0.0.0.0:$kDiscoveryPort');
    } catch (e, s) {
      _logger.warning('Failed to bind LAN UDP discovery socket: $e', e, s);
    }
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _hostedPayload = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> startBroadcasting({
    required String serverId,
    required String name,
    required String description,
    required String creator,
    required bool requiresPassword,
    required int maxPlayers,
    required LevelSetup levelSetup,
    required List<ServerMod> mods,
    int? gamePort,
    int? httpPort,
  }) async {
    await startListening();

    _hostedPayload = <String, dynamic>{
      'magic': _kAnnounceMagic,
      'id': serverId,
      'name': name,
      'description': description,
      'creator': creator,
      'port': gamePort ?? InstanceManager.gamePort,
      'httpPort': httpPort ?? InstanceManager.httpPort,
      'requiresPassword': requiresPassword,
      'maxPlayers': maxPlayers,
      'playerCount': 1,
      'map': levelSetup.map,
      'mode': levelSetup.mode,
      'mapName': levelSetup.mapName,
      'modeName': levelSetup.modeName,
      'mods': <Map<String, dynamic>>[
        for (var i = 0; i < mods.length; i++)
          <String, dynamic>{
            'index': i,
            'name': mods[i].name,
            'version': mods[i].version,
            'fileSize': mods[i].fileSize.toInt(),
            'link': mods[i].link,
          },
      ],
    };

    _broadcastTimer?.cancel();
    _sendBroadcastPacket(_hostedPayload!);
    _broadcastTimer = Timer.periodic(_kBroadcastInterval, (_) {
      if (_hostedPayload != null) {
        _sendBroadcastPacket(_hostedPayload!);
      }
    });
  }

  void stopBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _hostedPayload = null;
  }

  void sendDiscoveryProbe() {
    if (_socket == null) {
      unawaited(startListening());
      return;
    }

    _sendBroadcastPacket(const <String, dynamic>{'magic': _kProbeMagic});
  }

  List<Server> getDiscoveredServers() {
    final now = DateTime.now();
    _discovered.removeWhere(
      (_, entry) => now.difference(entry.lastSeen) > _kServerTtl,
    );
    return _discovered.values.map((e) => e.server).toList();
  }

  void registerManualServer(Server server) {
    _discovered[server.id] = _DiscoveredLanServer(
      server: server,
      lastSeen: DateTime.now().add(const Duration(minutes: 30)),
    );
  }

  Future<Server> queryServerByIp(
    String rawInput, {
    int defaultGamePort = InstanceManager.baseGamePort,
    int? defaultHttpPort,
  }) async {
    var hostIp = rawInput.trim();
    var gamePort = defaultGamePort;

    if (hostIp.contains(':')) {
      final parts = hostIp.split(':');
      hostIp = parts.first.trim();
      gamePort = int.tryParse(parts.last.trim()) ?? defaultGamePort;
    }

    // Each instance's HTTP mod server port is derived from its game port.
    final httpPort =
        defaultHttpPort ?? InstanceManager.httpPortForGamePort(gamePort);

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final response = await dio.get<Map<String, dynamic>>(
        'http://$hostIp:$httpPort/lan/info',
      );
      final data = response.data;
      if (data != null) {
        final server = _serverFromMap(
          data,
          senderIp: hostIp,
          fallbackPort: gamePort,
          fallbackHttpPort: httpPort,
        );
        registerManualServer(server);
        return server;
      }
    } catch (e) {
      _logger.fine(
        'Could not fetch /lan/info from $hostIp:$httpPort, '
        'creating direct LAN server entry: $e',
      );
    }

    final fallbackServer = Server(
      id: 'lan_$hostIp:$gamePort',
      name: 'LAN Server ($hostIp)',
      description: 'Direct LAN connection to $hostIp:$gamePort',
      creator: 'LAN Host',
      creatorId: '0',
      ip: hostIp,
      port: gamePort,
      maxPlayerCount: 40,
      playerCount: 1,
      requiresPassword: false,
      requiresProxy: false,
      official: false,
      region: 'LAN',
      levelSetup: LevelSetup(
        map: 'Levels/MP/Geonosis_01/Geonosis_01',
        mode: 'PlanetaryBattles',
        mapName: 'Geonosis',
        modeName: 'Galactic Assault',
      ),
      mods: const <ServerMod>[],
      meta: <String, String>{
        'lan': 'true',
        'lan_http_port': httpPort.toString(),
      }.entries,
    );
    registerManualServer(fallbackServer);
    return fallbackServer;
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) {
      return;
    }

    final datagram = _socket!.receive();
    if (datagram == null) {
      return;
    }

    try {
      final message = utf8.decode(datagram.data, allowMalformed: true);
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final magic = decoded['magic'] as String?;
      if (magic == _kProbeMagic) {
        if (_hostedPayload != null) {
          final bytes = utf8.encode(jsonEncode(_hostedPayload));
          _socket?.send(bytes, datagram.address, datagram.port);
        }
        return;
      }

      if (magic != _kAnnounceMagic) {
        return;
      }

      final senderIp = datagram.address.address;
      final server = _serverFromMap(decoded, senderIp: senderIp);
      _discovered[server.id] = _DiscoveredLanServer(
        server: server,
        lastSeen: DateTime.now(),
      );
    } catch (e) {
      _logger.fine('Ignored malformed LAN discovery packet: $e');
    }
  }

  Server _serverFromMap(
    Map<String, dynamic> map, {
    required String senderIp,
    int fallbackPort = 25200,
    int fallbackHttpPort = LanModServerService.kDefaultPort,
  }) {
    final port = (map['port'] as num?)?.toInt() ?? fallbackPort;
    final httpPort = (map['httpPort'] as num?)?.toInt() ?? fallbackHttpPort;
    final serverId = (map['id'] as String?)?.isNotEmpty ?? false
        ? map['id'] as String
        : 'lan_$senderIp:$port';

    final rawMods = (map['mods'] as List<dynamic>?) ?? const <dynamic>[];
    final parsedMods = <ServerMod>[];

    for (var i = 0; i < rawMods.length; i++) {
      final raw = rawMods[i];
      if (raw is! Map<String, dynamic>) {
        continue;
      }

      final modName = (raw['name'] as String?) ?? '';
      final modVersion = (raw['version'] as String?) ?? '';
      if (modName.isEmpty) {
        continue;
      }

      final fileSize = (raw['fileSize'] as num?)?.toInt() ?? 0;
      final originalLink = (raw['link'] as String?) ?? '';

      parsedMods.add(
        ServerMod(
          name: modName,
          version: modVersion,
          fileSize: Int64(fileSize),
          link: originalLink,
        ),
      );
    }

    return Server(
      id: serverId,
      name: (map['name'] as String?) ?? 'LAN Outpost ($senderIp)',
      description: (map['description'] as String?) ?? 'LAN Server',
      creator: (map['creator'] as String?) ?? 'LAN Host',
      creatorId: '0',
      ip: senderIp,
      port: port,
      maxPlayerCount: (map['maxPlayers'] as num?)?.toInt() ?? 40,
      playerCount: (map['playerCount'] as num?)?.toInt() ?? 1,
      requiresPassword: (map['requiresPassword'] as bool?) ?? false,
      requiresProxy: false,
      official: false,
      region: 'LAN',
      levelSetup: LevelSetup(
        map: (map['map'] as String?) ?? 'Levels/MP/Geonosis_01/Geonosis_01',
        mode: (map['mode'] as String?) ?? 'PlanetaryBattles',
        mapName: map['mapName'] as String?,
        modeName: map['modeName'] as String?,
      ),
      mods: parsedMods,
      meta: <String, String>{
        'lan': 'true',
        'lan_http_port': httpPort.toString(),
      }.entries,
    );
  }

  void _sendBroadcastPacket(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) {
      return;
    }

    final bytes = utf8.encode(jsonEncode(payload));
    try {
      socket.send(
        bytes,
        InternetAddress('255.255.255.255'),
        kDiscoveryPort,
      );
    } catch (_) {}

    unawaited(_sendSubnetBroadcasts(socket, bytes));
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> bytes,
  ) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final raw = addr.rawAddress;
          if (raw.length == 4 && raw[0] != 127) {
            final subnetBroadcast = InternetAddress(
              '${raw[0]}.${raw[1]}.${raw[2]}.255',
            );
            try {
              socket.send(bytes, subnetBroadcast, kDiscoveryPort);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
