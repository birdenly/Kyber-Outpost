import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/features/kyber/dialogs/kyber_anti_virus_exclusion.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_expired_session_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_locator_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_not_found_dialog.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/features/mods/helper/preloaded_mods_helper.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';

class MaximaStartGameDialog extends StatefulWidget {
  const MaximaStartGameDialog({
    super.key,
    this.gameDataDir,
    this.initializeRequest,
    this.mods,
  });

  final String? gameDataDir;
  final List<FrostyMod>? mods;
  final InitializeRequest? initializeRequest;

  @override
  State<MaximaStartGameDialog> createState() => _MaximaStartGameDialogState();
}

class _MaximaStartGameDialogState extends State<MaximaStartGameDialog> {
  bool updating = false;
  bool preloadingMods = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _startGame());
  }

  Future<void> _startGame() async {
    if (!mounted) {
      return;
    }

    try {
      setState(() => updating = true);
      final available = await ModuleVersionService().updateAvailable(
        module: VersionModule.module,
      );
      if (available) {
        await ModuleVersionService().updateVersion(
          module: VersionModule.module,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() => updating = false);

      final req = widget.initializeRequest ?? InitializeRequest();
      if (Preferences.general.enabledPreloadMods) {
        setState(() => preloadingMods = true);
        final preloadedMods = await PreloadedModsHelper.preloadMods();
        if (!mounted) {
          return;
        }

        req.modData = ModData(
          mods: req.modData.mods,
          explodedMods: req.modData.explodedMods,
          basePath: req.modData.basePath,
          modPaths: [
            ...req.modData.modPaths,
            ...preloadedMods,
          ],
        );
        setState(() => preloadingMods = false);
      }

      await MaximaHelper.startGame(
        gameDataPath: widget.gameDataDir,
        initializeRequest: req,
        mods: widget.mods,
      );
      // startGame only completes after the injected module answers local RPC.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error, stackTrace) {
      await _handleLaunchError(error, stackTrace);
    }
  }

  Future<void> _handleLaunchError(Object error, StackTrace stackTrace) async {
    Logger.root.severe('Failed to start game', error, stackTrace);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();

    final dialogContext = navigatorKey.currentContext;
    if (error is AnyhowException && dialogContext != null) {
      if (error.message.contains('Game not found')) {
        await showKyberDialog(
          context: dialogContext,
          builder: (_) => const MaximaGameNotFoundDialog(),
        );
        return;
      } else if (error.message.contains('Game not installed')) {
        await showKyberDialog(
          context: dialogContext,
          builder: (_) => const MaximaGameLocatorDialog(),
        );
        return;
      } else if (error.message.contains('remote io error')) {
        await showKyberDialog(
          context: dialogContext,
          builder: (_) => const KyberAntiVirusExclusion(),
        );
        return;
      } else if (error.message.contains('invalid redirect')) {
        await showKyberDialog(
          context: dialogContext,
          builder: (_) => const MaximaExpiredSessionDialog(),
        );
        return;
      }
    }

    if (error is PanicException && dialogContext != null) {
      await showKyberDialog(
        context: dialogContext,
        builder: (context) => KyberContentDialog(
          title: Text('Failed to start game'.toUpperCase()),
          content: Text(
            error.message,
            style: const TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 17,
            ),
          ),
          actions: [
            KyberButton(
              onPressed: () => Navigator.of(context).pop(),
              text: 'Close',
            ),
          ],
        ),
      );
      return;
    }

    final message = switch (error) {
      AnyhowException() => error.message,
      TimeoutException() => error.message ?? error.toString(),
      _ => error.toString(),
    };
    NotificationService.showNotification(
      message: 'Failed to start game: $message',
      severity: InfoBarSeverity.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text('GAME LAUNCHING'.toUpperCase()),
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
      content: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 15,
                width: 15,
                child: RepaintBoundary(child: ProgressRing()),
              ),
              const SizedBox(
                width: 15,
              ),
              if (updating)
                Text(
                  'Updating Kyber Module...',
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
              if (!updating)
                Text(
                  preloadingMods ? 'Preloading Mods...' : 'Starting Game...',
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            'Please wait while the game is starting. This may take a few seconds.',
            style: FluentTheme.of(context).typography.body?.copyWith(
              color: kWhiteColor,
            ),
          ),
        ],
      ),
    );
  }
}
