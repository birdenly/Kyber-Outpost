import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/nexusmods/dialogs/nexusmods_login.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/features/settings/dialogs/change_background_dialog.dart';
import 'package:kyber_launcher/features/settings/screens/settings.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
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
                    Preferences.nexusMods.refreshToken = null;
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
                                child: Assets.icons.kyberLogo.svg(
                                  height: 40,
                                ),
                              ),
                              applicationLegalese: '© 2024 ArmchairDevelopers',
                              applicationName: 'KYBER Launcher',
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
              if (context.read<MaximaCubit>().state.entitlements!.contains(
                UserEntitlement.admin,
              )) ...[
                KyberTableItem.button(
                  title: 'Set Background Image',
                  text: 'Set Image',
                  onClick: () async {
                    final result = await showKyberDialog<String?>(
                      context: context,
                      builder: (_) => const ChangeBackgroundDialog(),
                    );

                    if (result == null) {
                      return;
                    }

                    if (result.isEmpty) {
                      Preferences.customization.backgroundImage = null;
                      return;
                    }

                    Preferences.customization.backgroundImage = result;
                  },
                ),
                KyberTableItem.switchButton(
                  title: 'Dummy Server',
                  onChange: (value) => Preferences.admin.dummyServer = value,
                  value: Preferences.admin.dummyServer,
                ),
                KyberTableItem.switchButton(
                  title: 'Remove Background',
                  value: Preferences.admin.removeBackground,
                  onChange: (value) =>
                      Preferences.admin.removeBackground = value,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
