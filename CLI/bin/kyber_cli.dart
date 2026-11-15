import 'dart:async';
import 'dart:io';

import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/frb_generated.dart';
import 'package:kyber/kyber.dart';

Future<void> main(List<String> args) async {
  LanNetworkPolicy.install();
  await RustLib.init();
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
