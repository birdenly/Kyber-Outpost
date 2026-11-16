import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fadein/flutter_fadein.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/setup/widgets/mod_selector.dart';
import 'package:kyber_launcher/features/setup/widgets/nexus_login_screen.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SetupContainer extends StatefulWidget {
  const SetupContainer({
    required this.showWebView,
    required this.page,
    required this.onLocalPlayerSetup,
    required this.localPlayerBusy,
    required this.onNexusLogin,
    required this.onNexusCancel,
    required this.onNexusSuccess,
    super.key,
  });

  final int page;
  final VoidCallback onLocalPlayerSetup;
  final bool localPlayerBusy;
  final VoidCallback onNexusLogin;
  final VoidCallback onNexusCancel;
  final VoidCallback onNexusSuccess;
  final bool showWebView;

  @override
  State<SetupContainer> createState() => _SetupContainerState();
}

class _SetupContainerState extends State<SetupContainer> {
  bool showOverlay = false;
  bool whitelistPrompt = false;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    if (widget.page == 2) {
      return const ModSelector();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackgroundBlur(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: decoColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: BlocBuilder<MaximaCubit, MaximaState>(
            builder: (context, state) {
              if (widget.showWebView) {
                return Stack(
                  children: [
                    NexusLoginScreen(
                      onShowOverlay: (showOverlay) {
                        setState(() {
                          this.showOverlay = showOverlay;
                        });
                      },
                      onSuccess: widget.onNexusSuccess,
                    ),
                    if (showOverlay)
                      Positioned.fill(
                        child: FadeIn(
                          child: Container(
                            color: FluentTheme.of(
                              context,
                            ).micaBackgroundColor.withOpacity(.9),
                            alignment: Alignment.center,
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 30,
                                    width: 30,
                                    child: ProgressRing(),
                                  ),
                                  SizedBox(width: 15),
                                  Text(
                                    'Waiting for Nexus Mods...',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontFamily: FontFamily.battlefrontUI,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SizedBox(
                            height: 40,
                            width: 40,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: BackgroundBlur(
                                child: ButtonBuilder(
                                  builder: (context, hovered) {
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: hovered
                                              ? kActiveColor
                                              : decoColor,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(6),
                                      child: const Icon(
                                        mt.Icons.cancel_rounded,
                                      ),
                                      //child: const Text(
                                      //  'CANCEL LOGIN',
                                      //  style: TextStyle(
                                      //    fontFamily: FontFamily.battlefrontUI,
                                      //    fontSize: 16,
                                      //    height: 1,
                                      //  ),
                                      //),
                                    );
                                  },
                                  onClick: widget.onNexusCancel,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 105,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.page == 0
                                    ? 'LOCAL PLAYER'
                                    : 'SIGN IN: NEXUS MODS',
                                style: TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 28,
                                  color: kActiveColor,
                                ),
                              ),
                              Text(
                                widget.page == 0
                                    ? 'CREATE YOUR PLAYER PROFILE FOR LAN GAMES.'
                                    : 'LINK ACCOUNT AND ACCESS INTEGRATED NEXUS MODS FUNCTIONALITY.',
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 2,
                          color: decoColor,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Builder(
                              builder: (context) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      widget.page == 0
                                          ? 'Choose your player name to continue:'
                                          : 'Open the official Nexus Mods sign in page:',
                                      style: const TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ButtonBuilder(
                                      builder: (context, hovered) {
                                        return AnimatedContainer(
                                          height: 50,
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: hovered
                                                  ? kActiveColor
                                                  : decoColor,
                                              width: 2,
                                            ),
                                          ),
                                          child: AnimatedDefaultTextStyle(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            style: const TextStyle(
                                              color: kWhiteColor,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        if (widget.page == 0)
                                                          const Icon(
                                                            mt.Icons.person,
                                                            color: kWhiteColor,
                                                            size: 30,
                                                          )
                                                        else
                                                          Assets.logos.nexusMods
                                                              .svg(
                                                                color:
                                                                    kWhiteColor,
                                                                height: 30,
                                                              ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          widget.page == 0
                                                              ? 'CHOOSE NAME'
                                                              : 'SIGN IN',
                                                          style: TextStyle(
                                                            fontFamily: FontFamily
                                                                .battlefrontUI,
                                                            fontSize: 20,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 2,
                                                  color: decoColor,
                                                ),
                                                const SizedBox(width: 8),
                                                if (loading ||
                                                    (widget.page == 0 &&
                                                        widget.localPlayerBusy))
                                                  Container(
                                                    width: 30,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 10,
                                                          horizontal: 2,
                                                        ),
                                                    child: const ProgressRing(),
                                                  )
                                                else
                                                  const SizedBox(
                                                    width: 30,
                                                    child: Icon(
                                                      mt.Icons.login,
                                                      size: 24,
                                                    ),
                                                  ),
                                                const SizedBox(width: 10),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      onClick: widget.page == 0
                                          ? widget.localPlayerBusy
                                                ? null
                                                : widget.onLocalPlayerSetup
                                          : widget.onNexusLogin,
                                    ),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.bottomLeft,
                                        child: Text(
                                          widget.page == 0
                                              ? 'Your player profile is stored locally. Outpost does not require an EA sign-in.'
                                              : 'The official Nexus Mods sign in page will open in this window. Skipping this step will disable all integrated Nexus Mods functionality.',
                                          style: const TextStyle(
                                            fontFamily:
                                                FontFamily.battlefrontUI,
                                            fontSize: 17,
                                            color: kGrayColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 2,
                    color: decoColor,
                  ),
                  Expanded(
                    flex: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 105,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'TRANSPARENCY',
                                style: TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 28,
                                ),
                              ),
                              Text(
                                'Outpost local profile'.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 17,
                                  color: kGrayColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 2,
                          color: decoColor,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: SingleChildScrollView(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    const TextSpan(
                                      text: 'OUTPOST\n\n',
                                      style: TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const TextSpan(
                                      text:
                                          'Outpost uses a local player profile for LAN games. No account sign-in is required inside the launcher.',
                                    ),
                                    const TextSpan(
                                      text:
                                          '\n\nThe game must already have a valid activation from its official store. Outpost reuses that local activation for offline play.\n\n',
                                    ),
                                    TextSpan(
                                      text: 'VIEW SOURCE CODE - OUTPOST',
                                      style: TextStyle(
                                        color: kActiveColor,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          launchUrlString(
                                            'https://github.com/birdenly/Kyber-Outpost',
                                          );
                                        },
                                    ),
                                    const TextSpan(
                                      text: '\n\nKYBER',
                                      style: TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const TextSpan(
                                      text:
                                          '\n\nKYBER is a third-party launcher, mod interface, and game server platform for STAR WARS: Battlefront II developed and operated by Armchair Developers.',
                                    ),
                                    const TextSpan(
                                      text:
                                          '\n\nIn the interest of maintaining transparency the entirety of KYBER’s source code is publicly available for viewing.\n\n',
                                    ),
                                    TextSpan(
                                      text: 'VIEW SOURCE CODE - KYBER',
                                      style: TextStyle(
                                        color: kActiveColor,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          launchUrlString(
                                            'https://github.com/ArmchairDevelopers/Kyber',
                                          );
                                        },
                                    ),
                                    const TextSpan(
                                      text: '\n\nARMCHAIR DEVELOPERS',
                                      style: TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const TextSpan(
                                      text:
                                          '\n\nArmchair Developers is independently operated and is not, in any way, affiliated with Electronic Arts (EA).\n\n',
                                    ),
                                    TextSpan(
                                      text: 'LEARN MORE',
                                      style: TextStyle(
                                        color: kActiveColor,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          //launchUrlString('https://docs.flutter.io/flutter/services/UrlLauncher-class.html');
                                        },
                                    ),
                                  ],
                                  style: const TextStyle(
                                    fontFamily: FontFamily.battlefrontUI,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
