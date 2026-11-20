// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

enum VersionModule {
  //launcher,
  module,
  installer,
}

extension VersionModuleExtension on VersionModule {
  Future<String?> getCurrentVersion() async {
    switch (this) {
      case VersionModule.module:
        final x = File(
          join(ModuleVersionService.selectedModuleDirectory.path, 'VERSION'),
        );

        if (!x.existsSync()) {
          return _bundledModuleVersion;
        }

        return x.readAsStringSync();
      case VersionModule.installer:
        final info = await PackageInfo.fromPlatform();

        return '${info.version}+${info.buildNumber}';
    }
  }

  Future<String> getDownloadDir() async {
    switch (this) {
      case VersionModule.installer:
        final tmpDir = await getTemporaryDirectory();

        return join(
          tmpDir.path,
          'kyber_launcher_${DateTime.now().millisecondsSinceEpoch}',
        );
      case VersionModule.module:
        return FileHelper.getModuleDirectory().path;
    }
  }

  Future<void> setReleaseChannel(String channel) async {
    await box.put('${name}_release_channel', channel);
  }

  String get releaseChannel {
    return box.get('${name}_release_channel') as String? ?? 'stable';
  }

  List<String> get requiredFiles {
    switch (this) {
      case VersionModule.installer:
        return [];
      case VersionModule.module:
        final modulePath = ModuleVersionService.selectedModuleDirectory.path;
        return [
          '$modulePath/VanillaBundleAggregation.kb',
          '$modulePath/Kyber.dll',
        ];
    }
  }

  String get name {
    switch (this) {
      case VersionModule.installer:
        return 'kyber-installer-win64';
      case VersionModule.module:
        return 'kyber-module';
    }
  }
}

const _bundledModuleVersion = '2.0.0-outpost-lan';

class ModuleVersionService {
  static Directory get selectedModuleDirectory {
    final bundleDirectory = Directory(dirname(Platform.resolvedExecutable));
    if (File(join(bundleDirectory.path, 'Kyber.dll')).existsSync()) {
      return bundleDirectory;
    }

    return FileHelper.getModuleDirectory();
  }

  bool isStandalone() {
    // TODO: find a fix for this
    return false;
    /* RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: _launcherInstallerKey,
      );

      final installationPath = key.getStringValue('InstallLocation');
      if (installationPath == null) {
        return true;
      }

      return normalize(installationPath) !=
          dirname(Platform.resolvedExecutable);
    } on WindowsException catch (_) {
      return true;
    } catch (e) {
      _logger.warning('Failed to check if standalone: $e');
      return false;
    } finally {
      key?.close();
    }*/
  }

  Future<bool> checkChannel({
    required VersionModule module,
    required String channel,
  }) async {
    return true;
  }

  Future<bool> updateAvailable({
    required VersionModule module,
    String? channel,
  }) async {
    // LAN builds load the bundled DLL directly, without installing to ProgramData.
    return false;
  }

  Future<void> updateVersion({
    required VersionModule module,
    String? channel,
    String? token,
    void Function(int, int)? onProgress,
  }) async {
    // Kyber Outpost (LAN Edition): never contact Kyber Cloud for updates.
    return;
  }

  Future<String?> getLatestLauncherVersion([String? releaseChannel]) async {
    return null;
  }
}
