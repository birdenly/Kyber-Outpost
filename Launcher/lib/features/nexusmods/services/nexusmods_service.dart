import 'dart:io';

import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/storage_helper.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:nexus_bridge/nexus_bridge.dart';
import 'package:package_info_plus/package_info_plus.dart';

class NexusModsService {
  NexusBridge? _nexusBridge;
  NexusUser? _nexusUser;

  NexusBridge get nexusBridge => _nexusBridge!;

  NexusUser? get nexusUser => _nexusUser;

  String? get apiToken => Preferences.nexusMods.apiToken;

  final _logger = Logger('nexus_mods_service');

  Future<Dio> _createDio() async {
    final info = await PackageInfo.fromPlatform();
    final osInfo = Platform.operatingSystemVersion.replaceAll(
      RegExp(r'[^\x20-\x7E]'),
      '',
    );
    final dartVersion = Platform.version.replaceAll(
      RegExp(r'[^\x20-\x7E]'),
      '',
    );

    return Dio(
      BaseOptions(
        headers: {
          'User-Agent':
              'KyberLauncher/v${info.version}-#${info.buildNumber} ($osInfo) Dart/$dartVersion',
        },
      ),
    )..interceptors.add(DioCacheInterceptor(options: _cacheOptions));
  }

  Future<NexusModsService> getInstance() async {
    final dio = await _createDio();

    if (apiToken != null) {
      _nexusBridge = await NexusBridge.getInstance(
        apiToken: apiToken,
        dio: dio,
      );
      await fetchUser();
    } else {
      _nexusBridge = await NexusBridge.getInstance(dio: dio);
    }

    return this;
  }

  Future<void> fetchUser() async {
    try {
      _logger.info('Fetching user data');
      _nexusUser = await (await NexusBridge.getInstance(
        apiToken: apiToken,
      )).apiClient.validateUser();
      _logger
        ..fine('User validated: ${_nexusUser!.name}')
        ..fine('User isPremium: ${_nexusUser!.isPremium}');
    } catch (e, s) {
      NotificationService.error(message: 'Failed to load NexusMods user data');
      _logger.severe('Failed to load NexusMods user data:', e, s);
    }
  }

  Future<String> generateDownloadLink(Uri nxmLink) async {
    final service = sl.get<NexusModsService>();
    final gameId = nxmLink.host;
    final modId = nxmLink.pathSegments[1];
    final fileId = nxmLink.pathSegments.last;

    final downloadUrl = await service.nexusBridge.apiClient.getDownloadLink(
      gameId,
      int.parse(modId),
      int.parse(fileId),
      nxmLink.queryParameters['key'],
      int.parse(nxmLink.queryParameters['expires']!),
    );

    if (downloadUrl.isEmpty) {
      throw Exception('Download URL is empty');
    }

    return downloadUrl.first.uri;
  }

  Future<void> deleteToken() async {
    await HiveCacheStore(
      applicationDocumentsDirectory,
      hiveBoxName: 'dio_nexus_cache',
    ).clean();
    Preferences.nexusMods.apiToken = null;
    _nexusBridge = null;
  }

  Future<bool> loginWithApiKey(String token) async {
    try {
      await setApiToken(token);
      final checkResp = await _nexusBridge!.apiClient.validateUser();
      _logger.info('User validated: ${checkResp.name}');
      await fetchUser();
      Preferences.nexusMods.isLoggedIn = true;
      NotificationService.showNotification(
        message: 'Logged in as ${checkResp.name}',
        severity: InfoBarSeverity.success,
      );
      return true;
    } catch (e, s) {
      _logger.warning('Failed to validate NexusMods API key', e, s);
      return false;
    }
  }

  Future<void> setApiToken(String token) async {
    _nexusBridge = await NexusBridge.getInstance(
      apiToken: token,
      dio: await _createDio(),
    );
    Preferences.nexusMods.apiToken = token;
  }
}

final _cacheOptions = CacheOptions(
  store: HiveCacheStore(
    StorageHelper.getCacheDir(),
    hiveBoxName: 'dio_nexus_cache',
  ),
  maxStale: const Duration(hours: 4),
  policy: CachePolicy.forceCache,
);

CacheOptions get cacheOptions => _cacheOptions;
