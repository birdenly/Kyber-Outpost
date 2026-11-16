import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/frb_generated.dart';
import 'package:kyber/kyber.dart';

Future<void> main(List<String> args) async {
  LanNetworkPolicy.install();
  final bundledLibrary = File(
    File(
      Platform.resolvedExecutable,
    ).parent.uri.resolve('rust_lib.dll').toFilePath(),
  );
  await RustLib.init(
    externalLibrary: Platform.isWindows && bundledLibrary.existsSync()
        ? ExternalLibrary.open(bundledLibrary.path)
        : null,
  );
  await runZonedGuarded(
    () async {
      await _flushThenExit(await KyberCliCommandRunner().run(args));
    },
    (exception, stackTrace) async {
      print(
        'An error occurred. Please try again later.\n${exception.toString()}\n${stackTrace.toString()}',
      );
      exit(1);
    },
  );
}

Future<void> _flushThenExit(int status) {
  return Future.wait<void>([
    stdout.close(),
    stderr.close(),
  ]).then<void>((_) => exit(status));
}
