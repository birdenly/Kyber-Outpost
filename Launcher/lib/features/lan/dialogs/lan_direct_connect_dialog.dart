// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_input.dart';

class LanDirectConnectDialog extends StatefulWidget {
  const LanDirectConnectDialog({super.key});

  @override
  State<LanDirectConnectDialog> createState() => _LanDirectConnectDialogState();
}

class _LanDirectConnectDialogState extends State<LanDirectConnectDialog> {
  final TextEditingController _ipController = TextEditingController(
    text: '127.0.0.1:25200',
  );
  bool _loading = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final input = _ipController.text.trim();
    if (input.isEmpty) {
      NotificationService.error(message: 'Please enter a valid LAN Host IP');
      return;
    }

    setState(() => _loading = true);
    try {
      final server = await sl.get<LanDiscoveryService>().queryServerByIp(input);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop<Server>(server);
    } catch (e) {
      NotificationService.error(
        message: 'Failed to query LAN server at $input: $e',
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: const Text('DIRECT LAN CONNECT'),
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 280),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the IP address (and optional port) of the LAN Host:',
            style: TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 15,
              color: kWhiteColor,
            ),
          ),
          const SizedBox(height: 15),
          KyberInput(
            placeholder: '192.168.1.50:25200',
            controller: _ipController,
          ),
          const SizedBox(height: 10),
          const Text(
            'Note: Kyber Outpost will automatically query the HTTP port '
            '(game port + 2) for the server mod list and Frostbite load order before connecting.',
            style: TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 13,
              color: kInactiveColor,
            ),
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: 'CANCEL',
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
        ),
        KyberButton(
          text: _loading ? 'CONNECTING...' : 'CONNECT',
          onPressed: _loading ? null : _connect,
        ),
      ],
    );
  }
}
