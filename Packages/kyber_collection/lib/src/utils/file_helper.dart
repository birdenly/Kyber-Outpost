import 'dart:io';

class FileHelper {
  FileHelper._();

  static Directory getLauncherDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\KyberOutpost\\Launcher'
          : '${Platform.environment['HOME']}/.local/share/kyber-outpost/launcher',
    );

    return baseDir;
  }

  static Directory getArmchairDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\KyberOutpost'
          : '${Platform.environment['HOME']}/.local/share/kyber-outpost',
    );

    return baseDir;
  }

  static Directory getModuleDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\KyberOutpost\\Module'
          : '${Platform.environment['HOME']}/.local/share/kyber-outpost/module',
    );

    return baseDir;
  }

  static Directory getModsDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\KyberOutpost\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber-outpost/mods',
    );

    return baseDir;
  }

  static Directory getCollectionDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\KyberOutpost\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber-outpost/mods',
    );

    return baseDir;
  }
}
