import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Button;
import 'package:kyber_launcher/features/lan/dialogs/lan_nickname_dialog.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_status_cubit.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_rtm_cubit.dart';
import 'package:kyber_launcher/features/navigation_bar/widgets/exit_devplaytest_button.dart';
import 'package:kyber_launcher/features/settings/dialogs/chromium_download_dialog.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';

class SocialBar extends StatefulWidget {
  const SocialBar({super.key});

  @override
  State<SocialBar> createState() => _SocialBarState();
}

class _SocialBarState extends State<SocialBar> {
  @override
  Widget build(BuildContext context) {
    final kyberState = context.watch<KyberStatusCubit>().state;
    final maximaState = context.watch<MaximaCubit>().state;

    return SizedBox(
      height: 50,
      child: Container(
        decoration: BoxDecoration(
          border: .fromLTRB(right: kDefaultBorder),
        ),
        padding: const .only(left: 15),
        alignment: .center,
        child: Row(
          mainAxisAlignment: .end,
          spacing: 15,
          children: [
            const Expanded(flex: 3, child: SizedBox.shrink()),
            const ExitDevPlaytestButton(),
            const VCardSection(),
            const _UserBar(),
            Row(
              children: [
                if (kyberState is KyberStatusPlaying) ...[
                  const VCardSection(),
                  _NavigationBarItem(
                    icon: const Icon(mt.Icons.games_outlined),
                    onClick: () => router.push('/ingame'),
                  ),
                ],
                const VCardSection(),
                _NavigationBarItem(
                  icon: const _DownloadManagerButton(),
                  onClick: () => router.push('/downloads/overview'),
                ),
                const VCardSection(),
                _NavigationBarItem(
                  icon: const Icon(mt.Icons.settings),
                  onClick: () => router.go('/settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationBarItem extends StatelessWidget {
  const _NavigationBarItem({
    required this.icon,
    required this.onClick,
    super.key,
  });

  final Widget icon;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return ButtonBuilder(
      onClick: onClick,
      builder: (context, hovered) {
        final itemColor = switch (hovered) {
          true => kActiveColor,
          false => const Color(0xFFD9D9D9),
        };

        return Container(
          width: 50,
          height: 50,
          alignment: .center,
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: IconTheme(
            data: .new(
              color: itemColor,
            ),
            child: DefaultTextStyle(
              style: .new(
                color: itemColor,
                fontFamily: FontFamily.battlefrontUI,
              ),
              child: icon,
            ),
          ),
        );
      },
    );
  }
}

class _UserBar extends StatelessWidget {
  const _UserBar({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<MaximaCubit>().state.servicePlayer;

    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return ButtonBuilder(
      onClick: () => showKyberDialog(
        context: context,
        builder: (_) => LanNicknameDialog(initialName: currentUser.displayName),
      ),
      builder: (context, hovered) {
        final color = switch (hovered) {
          true => kActiveColor,
          false => decoColor,
        };

        return Container(
          margin: const .symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: .fromBorderSide(.new(color: color, width: 1)),
            borderRadius: const .all(.circular(6)),
            color: Colors.black.withOpacity(0.5),
          ),
          padding: const .symmetric(horizontal: 10, vertical: 5),
          child: Text(
            currentUser.displayName,
            style: const TextStyle(
              fontSize: 16,
              fontFamily: FontFamily.battlefrontUI,
              height: 1.1,
            ),
          ),
        );
      },
    );
  }
}

class _DownloadManagerButton extends StatelessWidget {
  const _DownloadManagerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadManagerState = context.watch<DownloadCubit>().state;

    final isDownloadActive =
        downloadManagerState is DownloadLoaded &&
        downloadManagerState.activeTasks.isNotEmpty;

    if (isDownloadActive) {
      return buildActiveDownloadButton(state: downloadManagerState);
    }

    return buildDownloadButton();
  }

  Widget buildDownloadButton() {
    return const Icon(mt.Icons.download);
  }

  Widget buildActiveDownloadButton({required DownloadLoaded state}) {
    var progress = switch (state.progressUpdate) {
      null => state.currentDownload?.progress ?? 1.0,
      final update => update.progress,
    };
    final progressText = '${(progress * 100).toStringAsFixed(0)}%';

    final expectedSize = switch (state.progressUpdate) {
      null => state.currentDownload?.expectedFileSize ?? 0,
      final update => update.expectedFileSize,
    };
    final remaining = expectedSize - (expectedSize * progress).toInt();
    final remainingSizeText = formatBytes(remaining, 1);

    final isExtracting = state.extractionProgressUpdate != null;
    final extractingTotal = state.extractionProgressUpdate?.total ?? 0;
    final extractingCurrent = state.extractionProgressUpdate?.extracted ?? 0;

    if (isExtracting) {
      if (extractingTotal > 0) {
        progress = extractingCurrent / extractingTotal;
      } else {
        progress = 0.0;
      }
    }

    return SizedBox(
      width: 50,
      child: Stack(
        clipBehavior: .antiAliasWithSaveLayer,
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                Flexible(
                  child: AnimatedFractionallySizedBox(
                    duration: const .new(milliseconds: 200),
                    widthFactor: progress >= 0.0 ? progress : 0.01,
                    child: Container(
                      decoration: BoxDecoration(
                        color: kActiveColor,
                      ),
                      height: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 0,
            child: Builder(
              builder: (context) {
                if (isExtracting) {
                  return _DownloadInfo(
                    title: const Icon(mt.Icons.file_copy),
                    text: Text(
                      progress >= 1.0
                          ? 'FINALIZING'
                          : '$extractingCurrent of $extractingTotal',
                    ),
                  );
                }

                return _DownloadInfo(
                  title: Text(progressText),
                  text: Text(remainingSizeText),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadInfo extends StatelessWidget {
  const _DownloadInfo({required this.title, required this.text, super.key});

  final Widget title;
  final Widget text;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 5,
      mainAxisAlignment: .center,
      children: [
        DefaultTextStyle(
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 18,
            height: 1,
            fontFeatures: [.tabularFigures()],
          ),
          textAlign: .center,
          child: title,
        ),
        DefaultTextStyle(
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 12,
            height: 1,
            fontFeatures: [.tabularFigures()],
          ),
          textAlign: .center,
          child: text,
        ),
      ],
    );
  }
}
