import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/lan/models/lan_nickname.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_input.dart';

class LanNicknameDialog extends StatefulWidget {
  const LanNicknameDialog({
    required this.initialName,
    this.duplicate = false,
    this.connectedNames = const [],
    super.key,
  });
  final String initialName;
  final bool duplicate;
  final List<String> connectedNames;

  @override
  State<LanNicknameDialog> createState() => _LanNicknameDialogState();
}

class _LanNicknameDialogState extends State<LanNicknameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    final validation = validateLanNickname(name);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (isLanNicknameInUse(name, widget.connectedNames)) {
      setState(
        () => _error = 'This nickname is already in use. Choose another name.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<MaximaCubit>().setLanNickname(name);
      if (mounted) Navigator.of(context).pop(name);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message.toString()
              : error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => KyberContentDialog(
    title: Text(widget.duplicate ? 'NICKNAME ALREADY IN USE' : 'LAN NICKNAME'),
    constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          widget.duplicate
              ? 'Another player in this room is using your nickname. Choose a different name to connect.'
              : 'This name identifies you in LAN rooms and in the game. Close your game before changing it.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        KyberInput(controller: _controller, placeholder: 'Your nickname'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InfoBar(title: Text(_error!), severity: InfoBarSeverity.error),
        ],
      ],
    ),
    actions: [
      KyberButton(
        text: 'CANCEL',
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      KyberButton(
        text: _saving ? 'SAVING...' : 'SAVE',
        onPressed: _saving ? null : _save,
      ),
    ],
  );
}
