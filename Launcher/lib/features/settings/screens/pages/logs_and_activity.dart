import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/utils/custom_logger.dart';
import 'package:kyber_launcher/features/settings/dialogs/debug_logging_warning_dialog.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class LogsAndActivity extends StatelessWidget {
  const LogsAndActivity({super.key});

  @override
  Widget build(BuildContext context) {
    return HiveListener(
      box: box,
      keys: const ['discordRPC'],
      builder: (bx) => SuperListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(8).copyWith(left: 20),
            child: Text(
              'Logging'.toUpperCase(),
              style: FluentTheme.of(context).typography.title!.copyWith(
                fontWeight: FontWeight.bold,
                color: kInactiveColor,
                fontFamily: FontFamily.battlefrontUI,
              ),
            ),
          ),
          HiveListener(
            box: box,
            keys: const [
              'frbDebugLogs',
              'moduleDebugLogs',
              'grpcDebugLogs',
            ],
            builder: (_) => KyberTable(
              items: [
                KyberTableItem.button(
                  title: 'Logs',
                  text: 'Export Logs',
                  onClick: () async {
                    await CustomLogger.requestLogExport();
                  },
                ),
                KyberTableItem.switchButton(
                  title: 'Launcher Debug Mode',
                  value: Preferences.debug.frbDebugLogs,
                  onChange: (value) async {
                    if (value) {
                      await showKyberDialog(
                        context: context,
                        builder: (_) => const DebugLoggingWarningDialog(),
                      );
                    }

                    if (!kDebugMode) {
                      PlatformInAppWebViewController
                              .debugLoggingSettings
                              .enabled =
                          value;
                      PlatformInAppWebViewController
                              .debugLoggingSettings
                              .usePrint =
                          value;
                    }

                    Logger.root.info(
                      '${value ? 'Enabled' : 'Disabled'} debug logs',
                    );
                    Logger.root.level = value ? Level.ALL : Level.INFO;
                    Preferences.debug.frbDebugLogs = value;
                    if (!value) {
                      CustomLogger.clearLogFile();
                    }
                  },
                ),
                KyberTableItem.switchButton(
                  title: 'Module Debug Mode',
                  value: Preferences.debug.moduleDebugLogs,
                  onChange: (value) async {
                    if (value) {
                      await showKyberDialog(
                        context: context,
                        builder: (_) => const DebugLoggingWarningDialog(),
                      );
                    }

                    Logger.root.info(
                      '${value ? 'Enabled' : 'Disabled'} module debug logs',
                    );
                    Preferences.debug.moduleDebugLogs = value;
                  },
                ),
                KyberTableItem.switchButton(
                  title: 'Module RPC Debug Mode',
                  value: Preferences.debug.grpcDebugLogs,
                  onChange: (value) async {
                    if (value) {
                      await showKyberDialog(
                        context: context,
                        builder: (_) => const DebugLoggingWarningDialog(),
                      );
                    }

                    Logger.root.info(
                      '${value ? 'Enabled' : 'Disabled'} module debug logs',
                    );
                    Preferences.debug.grpcDebugLogs = value;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
