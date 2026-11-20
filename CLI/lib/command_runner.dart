import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:get_it/get_it.dart';
import 'package:kyber_cli/commands/start_game.dart';
import 'package:kyber_cli/commands/start_server_command.dart';
import 'package:kyber_cli/gen/api/outpost.dart' as mx;
import 'package:mason_logger/mason_logger.dart';

final sl = GetIt.instance;
const version = '2.0.0-beta9+1';
const executableName = 'kyber_cli';
const packageName = 'kyber_cli';
const description = 'A CLI for Kyber.';

class KyberCliCommandRunner extends CompletionCommandRunner<int> {
  String customInfoStyle(String level, String? message) {
    final x = '[$level] - $message';
    return "[${DateTime.now().toString().split('.').first}] $x";
  }

  KyberCliCommandRunner({Logger? logger}) : super(executableName, description) {
    _logger =
        logger ??
        Logger(
          theme: LogTheme(
            alert: (message) => customInfoStyle('alert', message),
            detail: (message) => customInfoStyle('detail', message),
            err: (message) => customInfoStyle('error', message),
            info: (message) => customInfoStyle('info', message),
            success: (message) => customInfoStyle('info', message),
            warn: (message) => customInfoStyle('warn', message),
          ),
        );

    _logger.level = Level.info;

    mxLogs = mx.setupLogStream().asBroadcastStream();

    argParser
      ..addFlag('version', negatable: false, help: 'Print the current version.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
      )
      ..addFlag('debug', help: 'Enable local runtime debug logs.');

    addCommand(StartServerCommand(logger: _logger));
    addCommand(StartGameCommand(logger: _logger));
  }

  @override
  void printUsage() => _logger.info(usage);

  late Logger _logger;

  late Stream<mx.LogEntry> mxLogs;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['verbose'] == true) {
        _logger.level = Level.verbose;
      }

      final mxDebug = topLevelResults['debug'] == true;

      mxLogs.listen((event) {
        final loggerName = event.lbl.isEmpty ? 'root' : event.lbl;
        final message = '[$loggerName] - ${event.msg}';
        switch (event.logLevel) {
          case mx.Level.debug:
          case mx.Level.trace:
            if (!mxDebug) {
              return;
            }

            _logger.detail(message);
          case mx.Level.error:
            _logger.err(message);
          case mx.Level.info:
            _logger.info(message);
          case mx.Level.warn:
            _logger.warn(message);
        }
      });

      if (topLevelResults.command != null &&
          !topLevelResults.arguments.contains('--help')) {
        await mx.initializeRuntime();
      }

      return await runCommand(topLevelResults) ?? ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      _logger
        ..err(e.message)
        ..err('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    _logger
      ..detail('Argument information:')
      ..detail('  Top level options:');
    for (final option in topLevelResults.options) {
      if (topLevelResults.wasParsed(option)) {
        _logger.detail('  - $option: ${topLevelResults[option]}');
      }
    }
    if (topLevelResults.command != null) {
      final commandResult = topLevelResults.command!;
      _logger
        ..detail('  Command: ${commandResult.name}')
        ..detail('    Command options:');
      for (final option in commandResult.options) {
        if (commandResult.wasParsed(option)) {
          _logger.detail('    - $option: ${commandResult[option]}');
        }
      }
    }

    final int? exitCode;
    if (topLevelResults['version'] == true) {
      print(version);
      exitCode = ExitCode.success.code;
    } else {
      exitCode = await super.runCommand(topLevelResults);
    }

    return exitCode;
  }
}
