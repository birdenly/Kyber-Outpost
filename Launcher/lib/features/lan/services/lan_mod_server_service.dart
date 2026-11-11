// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

class LanHostedModEntry {
  const LanHostedModEntry({
    required this.index,
    required this.name,
    required this.version,
    required this.filename,
    required this.filePath,
    required this.fileSize,
    required this.link,
  });

  final int index;
  final String name;
  final String version;
  final String filename;
  final String filePath;
  final int fileSize;
  final String link;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'index': index,
    'name': name,
    'version': version,
    'filename': filename,
    'fileSize': fileSize,
    'link': link,
  };
}

class LanModServerService {
  static const int kDefaultPort = 25202;
  static const int _maxConcurrentDownloads = 2;

  final Logger _logger = Logger('lan_mod_server');

  HttpServer? _server;
  int _activePort = kDefaultPort;
  int _activeDownloads = 0;
  final List<Completer<void>> _downloadWaitQueue = <Completer<void>>[];

  /// Strict allowlist of mods currently exposed over LAN HTTP.
  final List<LanHostedModEntry> _allowedMods = <LanHostedModEntry>[];

  Map<String, dynamic> _hostedServerMetadata = <String, dynamic>{};

  bool get isRunning => _server != null;

  int get port => _activePort;

  List<LanHostedModEntry> get allowedMods => List.unmodifiable(_allowedMods);

  Future<void> start({int preferredPort = kDefaultPort}) async {
    if (_server != null) {
      return;
    }

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        preferredPort,
        shared: true,
      );
      _activePort = _server!.port;
    } catch (e) {
      _logger.warning(
        'Failed to bind LAN HTTP mod server on port $preferredPort, '
        'binding ephemeral port: $e',
      );
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
      _activePort = _server!.port;
    }

    _logger.info('LAN HTTP mod server listening on 0.0.0.0:$_activePort');
    unawaited(_serveLoop(_server!));
  }

  Future<void> stop() async {
    _allowedMods.clear();
    _hostedServerMetadata = <String, dynamic>{};
    await _server?.close(force: true);
    _server = null;
  }

  /// Configures the allowlist of `.fbmod` files for the currently hosted LAN
  /// server in the exact Frostbite load order.
  Future<void> configureHostedServer({
    required String serverId,
    required String serverName,
    required String description,
    required String creator,
    required bool requiresPassword,
    required int maxPlayers,
    required LevelSetup levelSetup,
    required List<FrostyMod> orderedMods,
    int gamePort = 25200,
  }) async {
    await start();

    _allowedMods.clear();
    final basePath = ModService.getBasePath();

    for (var i = 0; i < orderedMods.length; i++) {
      final mod = orderedMods[i];
      if (mod.isCollection) {
        continue;
      }

      final fullPath = p.normalize(p.join(basePath, mod.filename));
      if (!p.isWithin(p.normalize(basePath), fullPath)) {
        _logger.warning('Skipping mod outside base path: $fullPath');
        continue;
      }

      final file = File(fullPath);
      if (!file.existsSync()) {
        continue;
      }

      final safeFilename = p.basename(fullPath);
      if (!safeFilename.toLowerCase().endsWith('.fbmod')) {
        continue;
      }

      _allowedMods.add(
        LanHostedModEntry(
          index: _allowedMods.length,
          name: mod.details.name,
          version: mod.details.version,
          filename: safeFilename,
          filePath: fullPath,
          fileSize: file.lengthSync(),
          link: mod.details.link,
        ),
      );
    }

    _hostedServerMetadata = <String, dynamic>{
      'id': serverId,
      'name': serverName,
      'description': description,
      'creator': creator,
      'port': gamePort,
      'httpPort': _activePort,
      'requiresPassword': requiresPassword,
      'maxPlayers': maxPlayers,
      'playerCount': 1,
      'map': levelSetup.map,
      'mode': levelSetup.mode,
      'mapName': levelSetup.mapName,
      'modeName': levelSetup.modeName,
      'mods': _allowedMods.map((m) => m.toJson()).toList(),
    };

    _logger.info(
      'Configured LAN HTTP mod allowlist with ${_allowedMods.length} .fbmod files',
    );
  }

  /// Enables Peer Seed Mode so a player on the LAN who already downloaded
  /// mods can serve their installed `.fbmod` files to other LAN peers.
  Future<void> enablePeerModSeeding() async {
    await start();
    if (_hostedServerMetadata.isNotEmpty) {
      return;
    }

    _allowedMods.clear();
    final basePath = ModService.getBasePath();
    final installedMods = sl.get<ModService>().mods;

    for (final mod in installedMods) {
      if (mod.isCollection) {
        continue;
      }

      final fullPath = p.normalize(p.join(basePath, mod.filename));
      if (!p.isWithin(p.normalize(basePath), fullPath)) {
        continue;
      }

      final file = File(fullPath);
      if (!file.existsSync()) {
        continue;
      }

      final safeFilename = p.basename(fullPath);
      if (!safeFilename.toLowerCase().endsWith('.fbmod')) {
        continue;
      }

      _allowedMods.add(
        LanHostedModEntry(
          index: _allowedMods.length,
          name: mod.details.name,
          version: mod.details.version,
          filename: safeFilename,
          filePath: fullPath,
          fileSize: file.lengthSync(),
          link: mod.details.link,
        ),
      );
    }
  }

  Future<void> _serveLoop(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _acquireDownloadSlot() async {
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads++;
      return;
    }

    final completer = Completer<void>();
    _downloadWaitQueue.add(completer);
    await completer.future;
  }

  void _releaseDownloadSlot() {
    if (_downloadWaitQueue.isNotEmpty) {
      final next = _downloadWaitQueue.removeAt(0);
      next.complete();
      return;
    }

    if (_activeDownloads > 0) {
      _activeDownloads--;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length == 2 &&
          pathSegments[0] == 'lan' &&
          pathSegments[1] == 'info') {
        response.headers.contentType = ContentType.json;
        final payload = _hostedServerMetadata.isNotEmpty
            ? _hostedServerMetadata
            : <String, dynamic>{
                'httpPort': _activePort,
                'mods': _allowedMods.map((m) => m.toJson()).toList(),
              };
        response.write(jsonEncode(payload));
        await response.close();
        return;
      }

      if (pathSegments.length >= 3 &&
          pathSegments[0] == 'lan' &&
          pathSegments[1] == 'mods') {
        LanHostedModEntry? entry;

        if (pathSegments[2] == 'by-name') {
          final name = request.uri.queryParameters['name'];
          final version = request.uri.queryParameters['version'];
          if (name != null) {
            entry = _allowedMods.firstWhereOrNull(
              (m) =>
                  m.name == name &&
                  (version == null || version.isEmpty || m.version == version),
            );
          }
        } else {
          final index = int.tryParse(pathSegments[2]);
          if (index != null && index >= 0 && index < _allowedMods.length) {
            entry = _allowedMods[index];
          }
        }

        if (entry == null) {
          response.statusCode = HttpStatus.notFound;
          response.write('Mod not in LAN allowlist');
          await response.close();
          return;
        }

        await _streamModFile(request, entry);
        return;
      }

      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (e, s) {
      _logger.warning('Error handling LAN HTTP request: $e', e, s);
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _streamModFile(
    HttpRequest request,
    LanHostedModEntry entry,
  ) async {
    final response = request.response;
    final file = File(entry.filePath);
    if (!file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final totalLength = file.lengthSync();
    var start = 0;
    var end = totalLength - 1;
    var isPartial = false;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty) {
        final parsedStart = int.tryParse(parts[0]);
        final parsedEnd = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (parsedStart != null &&
            parsedStart >= 0 &&
            parsedStart < totalLength) {
          start = parsedStart;
          if (parsedEnd != null &&
              parsedEnd >= start &&
              parsedEnd < totalLength) {
            end = parsedEnd;
          }
          isPartial = true;
        }
      }
    }

    final contentLength = (end - start) + 1;
    final safeHeaderFilename = entry.filename.replaceAll('"', '');
    response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(
        'Content-Disposition',
        'attachment; filename="$safeHeaderFilename"',
      )
      ..contentLength = contentLength;

    if (isPartial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$totalLength',
      );
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    await _acquireDownloadSlot();
    try {
      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    } finally {
      _releaseDownloadSlot();
    }
  }

  static String buildDirectModUrl({
    required String hostIp,
    required int httpPort,
    required ServerMod mod,
    int? index,
  }) {
    final safeName = mod.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    final safeVersion = mod.version
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    final fileName = Uri.encodeComponent('$safeName ($safeVersion).fbmod');

    if (index != null && index >= 0) {
      return 'http://$hostIp:$httpPort/lan/mods/$index/$fileName';
    }

    final query = Uri(
      queryParameters: <String, String>{
        'name': mod.name,
        'version': mod.version,
      },
    ).query;
    return 'http://$hostIp:$httpPort/lan/mods/by-name/$fileName?$query';
  }
}
