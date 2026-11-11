// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

enum LanModDownloadSource {
  /// Download `.fbmod` files directly from the LAN Host HTTP server (`:25202`),
  /// falling back to Internet (NexusMods) if a mod cannot be fetched from Host.
  lanHostWithInternetFallback,

  /// Download mods from the Internet (NexusMods/ModBridge), falling back to
  /// the LAN Host HTTP server if offline or unavailable.
  internetWithLanFallback,

  /// Strictly download `.fbmod` files from the LAN Host HTTP server (`:25202`)
  /// without making any Internet requests.
  lanHostOnly,
}

class LanModDownloadDialog extends StatelessWidget {
  const LanModDownloadDialog({
    required this.server,
    required this.missingMods,
    super.key,
  });

  final Server server;
  final List<ServerMod> missingMods;

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return 'Unknown size';
    }
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = missingMods.fold<int>(
      0,
      (sum, m) => sum + m.fileSize.toInt(),
    );
    final hostIp = server.ip.isNotEmpty ? server.ip : '127.0.0.1';
    final httpPort = server.meta['lan_http_port'] ?? '25202';

    return KyberContentDialog(
      title: const Text('MISSING SERVER MODS'),
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 460),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are missing ${missingMods.length} mod(s) required to join '
            '"${server.name}" (${_formatBytes(totalBytes)}).',
            style: const TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 16,
              color: kWhiteColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose how you want to download the required .fbmod files:\n'
            '• LAN Host (http://$hostIp:$httpPort) downloads directly over your local network.\n'
            '• Internet (NexusMods) downloads from the web if you have an internet connection.',
            style: const TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 14,
              color: kInactiveColor,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                border: Border.all(color: decoColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: missingMods.length,
                itemBuilder: (context, index) {
                  final mod = missingMods[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${index + 1}. ${mod.name} (${mod.version})',
                      style: const TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 14,
                        color: kWhiteColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        KyberButton(
          text: 'LAN HOST (AUTO FALLBACK)',
          onPressed: () => Navigator.of(context).pop(
            LanModDownloadSource.lanHostWithInternetFallback,
          ),
        ),
        KyberButton(
          text: 'LAN HOST ONLY',
          onPressed: () => Navigator.of(context).pop(
            LanModDownloadSource.lanHostOnly,
          ),
        ),
        KyberButton(
          text: 'INTERNET',
          onPressed: () => Navigator.of(context).pop(
            LanModDownloadSource.internetWithLanFallback,
          ),
        ),
      ],
    );
  }
}
