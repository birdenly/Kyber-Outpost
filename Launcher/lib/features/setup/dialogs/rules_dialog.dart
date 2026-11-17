import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

const _rules = '''
When using Kyber Outpost (LAN Edition), keep the following guidelines in mind:

- **Play Only With Trusted People**:  
  Only host or join LAN / virtual LAN rooms and download shared mods from players you know and trust. Avoid exposing LAN ports (25200–25202) to untrusted public networks.

- **Lawful Use Only**:  
  You will use Kyber Outpost only for lawful, non-commercial, private LAN sessions with a legitimate copy of STAR WARS™ Battlefront™ II, and never for malicious or unauthorized activities.

- **Fair Play & Respect**:  
  Respect everyone in your room and avoid griefing, exploits, or unapproved tampering inside shared matches.

Special thanks to the original **KYBER** team, **Armchair Developers**, and all upstream contributors whose open-source work made this project possible. Kyber Outpost is an independent LAN fork and is not affiliated with or supported by Armchair Developers or Electronic Arts (EA).

Please also review the STAR WARS™ Battlefront™ II [EULA](https://www.ea.com/legal/user-agreement).''';

Future<void> showRulesDialog(BuildContext context) async {
  if (Preferences.general.acceptedRules) {
    return;
  }
  final result = await showKyberDialog<bool?>(
    context: context,
    builder: (_) => const RulesDialog(),
  );
  if (result == null || !result) {
    return showRulesDialog(context);
  }

  Preferences.general.acceptedRules = true;
}

class RulesDialog extends StatefulWidget {
  const RulesDialog({super.key});

  @override
  State<RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<RulesDialog> {
  int countdown = 5;
  late Timer timer;

  @override
  void initState() {
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown == 0) {
        return t.cancel();
      }

      setState(() => countdown--);
    });
    super.initState();
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: const Text('LAN NOTICE'),
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
      content: Container(
        padding: const EdgeInsets.only(top: 4),
        width: 800,
        child: SingleChildScrollView(
          child: MarkdownBody(
            data: _rules,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                color: kWhiteColor,
              ),
              a: TextStyle(
                color: kActiveColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
      actions: [
        KyberButton(
          icon: countdown == 0
              ? const Icon(mt.Icons.check)
              : Text(countdown.toString()),
          text: 'ACCEPT',
          onPressed: countdown != 0
              ? null
              : () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
