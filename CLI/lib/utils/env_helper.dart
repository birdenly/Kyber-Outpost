import 'dart:io';

import 'package:kyber_cli/utils/windows_env.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:path/path.dart' as p;

class EnvHelper {
  EnvHelper._();

  static String getModulePath([String? customPath]) {
    if (customPath != null) return Directory(customPath).absolute.path;
    final cwd = Directory.current.path;
    if (File(p.join(cwd, 'Kyber.dll')).existsSync()) return cwd;
    final bundled = p.dirname(Platform.resolvedExecutable);
    if (File(p.join(bundled, 'Kyber.dll')).existsSync()) return bundled;
    final parent = p.dirname(bundled);
    if (File(p.join(parent, 'Kyber.dll')).existsSync()) return parent;
    return FileHelper.getModuleDirectory().path;
  }

  static void setPath([String? customPath]) {
    final path = Platform.environment['PATH'];
    if (path == null) {
      throw Exception('PATH environment variable is not set');
    }

    final newPath = '$path;${getModulePath(customPath)}';
    Env.set('PATH', newPath);
  }
}
