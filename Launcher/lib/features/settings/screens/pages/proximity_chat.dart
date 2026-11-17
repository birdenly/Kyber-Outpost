import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/settings/screens/settings.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class ProximityChat extends StatelessWidget {
  const ProximityChat({super.key});

  @override
  Widget build(BuildContext context) {
    return SuperListView(
      children: [
        const SettingsHeader(title: 'INGAME'),
        HiveListener(
          box: box,
          keys: const ['ingameHotkeyEnabled'],
          builder: (context) {
            return KyberTable(
              items: [
                KyberTableItem.switchButton(
                  title: 'Ingame Hotkey (Moderation Menu)',
                  value: Preferences.general.ingameHotkeyEnabled,
                  onChange: (value) async {
                    Preferences.general.ingameHotkeyEnabled = value;
                    if (sl.isRegistered<MaximaGameInstance>()) {
                      NotificationService.showNotification(
                        message: 'To apply changes, restart the game',
                      );
                    }
                  },
                  enabledText: 'Enabled',
                  disabledText: 'Disabled',
                ),
              ],
            );
          },
        ),
        const SettingsHeader(title: 'EXPERIMENTAL SETTINGS'),
        HiveListener(
          box: box,
          keys: const ['disableForceNoHDR', 'disableForceDX11'],
          builder: (context) {
            return KyberTable(
              items: [
                KyberTableItem.switchButton(
                  title: 'Disable Force No HDR',
                  value: Preferences.general.disableForceNoHDR,
                  onChange: (value) async {
                    Preferences.general.disableForceNoHDR = value;
                    if (sl.isRegistered<MaximaGameInstance>()) {
                      NotificationService.showNotification(
                        message: 'To apply changes, restart the game',
                      );
                    }
                  },
                ),
                KyberTableItem.switchButton(
                  title: 'Disable Force DX11',
                  value: Preferences.general.disableForceDX11,
                  onChange: (value) async {
                    Preferences.general.disableForceDX11 = value;
                    if (sl.isRegistered<MaximaGameInstance>()) {
                      NotificationService.showNotification(
                        message: 'To apply changes, restart the game',
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
