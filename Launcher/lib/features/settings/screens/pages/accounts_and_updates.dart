import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/nexusmods/dialogs/nexusmods_login.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/features/settings/screens/settings.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class AccountsAndUpdates extends StatelessWidget {
  const AccountsAndUpdates({super.key});

  @override
  Widget build(BuildContext context) {
    return SuperListView(
      children: [
        const SettingsHeader(title: 'ACCOUNTS'),
        HiveListener(
          box: box,
          keys: const ['nexusmods_login'],
          builder: (bx) => KyberTable(
            items: [
              KyberTableItem.button(
                title: 'NexusMods',
                onClick: () async {
                  if (Preferences.nexusMods.isLoggedIn) {
                    try {
                      await sl.get<NexusModsService>().deleteToken();
                    } catch (_) {}
                    try {
                      await CookieManager.instance(
                        webViewEnvironment: webViewEnvironment,
                      ).deleteAllCookies();
                    } catch (_) {}
                    Preferences.nexusMods.isLoggedIn = false;
                    Preferences.nexusMods.apiToken = null;
                  } else {
                    await showKyberDialog(
                      context: context,
                      builder: (_) => const NexusmodsLogin(),
                      routeSettings: const RouteSettings(
                        name: 'nexusmods_login',
                      ),
                    );
                  }
                },
                text: Preferences.nexusMods.isLoggedIn ? 'Logout' : 'Login',
              ),
            ],
          ),
        ),
        const SettingsHeader(title: 'OTHER'),
        HiveListener(
          box: box,
          keys: const [
            'removeBackground',
            'window',
            'disableHeadless',
            'dummyServer',
            'developerMode',
          ],
          builder: (_) => KyberTable(
            items: [
              KyberTableItem.switchButton(
                title: 'Remember Window Position',
                value: Preferences.customization.rememberWindowPosition,
                onChange: (value) async {
                  Preferences.customization.rememberWindowPosition = value;
                },
              ),
              KyberTableItem.button(
                title: 'Licenses',
                onClick: () {
                  Navigator.of(context).push(
                    mt.MaterialPageRoute<void>(
                      builder: (_) => mt.Theme(
                        data: mt.ThemeData(
                          brightness: FluentTheme.of(context).brightness,
                          primaryColor: kActiveColor,
                          colorScheme: mt.ColorScheme.dark(
                            primary: kActiveColor,
                            brightness: FluentTheme.of(context).brightness,
                          ),
                        ),
                        child: FutureBuilder(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const mt.Center(
                                child: ProgressRing(),
                              );
                            }

                            return mt.LicensePage(
                              applicationIcon: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Image.asset(
                                  'assets/logos/outpost_icon.png',
                                  height: 40,
                                ),
                              ),
                              applicationLegalese:
                                  'GPLv3 — Kyber Outpost (based on KYBER)',
                              applicationName: 'Kyber Outpost',
                              applicationVersion: snapshot.data?.version,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                text: 'Show Licenses',
              ),
              KyberTableItem.switchButton(
                title: 'Developer Mode',
                value: Preferences.general.developerMode,
                onChange: (value) {
                  Preferences.general.developerMode = value;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
