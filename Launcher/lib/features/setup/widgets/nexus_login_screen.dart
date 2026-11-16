import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';

class NexusLoginScreen extends StatefulWidget {
  const NexusLoginScreen({
    required this.onShowOverlay,
    required this.onSuccess,
    super.key,
  });

  final void Function(bool showOverlay) onShowOverlay;
  final void Function() onSuccess;

  @override
  State<NexusLoginScreen> createState() => _NexusLoginScreenState();
}

class _NexusLoginScreenState extends State<NexusLoginScreen> {
  InAppWebViewController? controller;
  Timer? _apiKeyPollTimer;
  bool _isValidatingKey = false;
  final Set<String> _rejectedCandidates = {};

  static const String _extractPersonalApiKeyJs = r'''
(() => {
  const tokenRegex = /^[A-Za-z0-9+/=_-]{32,}$/;
  const clean = (v) => (v || '').trim();

  // 1. Find the "Personal API Key" section/heading and inspect inputs/code inside its container.
  const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, p, span, div, label'));
  const personalLabel = headings.find((el) => {
    const txt = (el.textContent || '').trim().toLowerCase();
    return txt === 'personal api key' || txt.startsWith('personal api key');
  });

  if (personalLabel) {
    let container = personalLabel.parentElement;
    for (let depth = 0; depth < 6 && container; depth++) {
      const inputs = container.querySelectorAll('input, textarea');
      for (const inp of inputs) {
        const val = clean(inp.value);
        if (tokenRegex.test(val)) return val;
      }
      const codes = container.querySelectorAll('code, pre, [data-api-key]');
      for (const c of codes) {
        const val = clean(c.getAttribute('data-api-key') || c.textContent);
        if (tokenRegex.test(val)) return val;
      }
      container = container.parentElement;
    }
  }

  // 2. Fallback: look for readonly inputs that look like a NexusMods API key.
  const readonlyInputs = document.querySelectorAll('input[readonly], input[type="text"], input[type="password"]');
  for (const inp of readonlyInputs) {
    const val = clean(inp.value);
    if (tokenRegex.test(val)) return val;
  }

  return null;
})();
''';

  static const String _scrollToPersonalApiKeyJs = r'''
(() => {
  const els = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, p, span, label'));
  const target = els.find((el) => (el.textContent || '').trim().toLowerCase().includes('personal api key'));
  if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
})();
''';

  void _startApiKeyPolling(InAppWebViewController webController) {
    _apiKeyPollTimer?.cancel();
    _apiKeyPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _isValidatingKey) return;

      try {
        final result = await webController.evaluateJavascript(
          source: _extractPersonalApiKeyJs,
        );
        if (result is! String) return;

        final candidate = result.trim();
        if (candidate.isEmpty || _rejectedCandidates.contains(candidate)) {
          return;
        }

        _isValidatingKey = true;
        if (mounted) {
          widget.onShowOverlay(true);
        }

        final ok = await sl.get<NexusModsService>().loginWithApiKey(candidate);
        if (ok) {
          _apiKeyPollTimer?.cancel();
          if (mounted) {
            widget.onSuccess();
          }
          return;
        }

        _rejectedCandidates.add(candidate);
        _isValidatingKey = false;
        if (mounted) {
          widget.onShowOverlay(false);
        }
      } catch (e) {
        _isValidatingKey = false;
        Logger.root.fine('API key poll iteration error: $e');
      }
    });
  }

  @override
  void dispose() {
    _apiKeyPollTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(
        url: WebUri('https://users.nexusmods.com/auth/sign_in'),
      ),
      initialSettings: InAppWebViewSettings(
        forceDark: ForceDark.ON,
        isInspectable: true,
      ),
      onWebViewCreated: (controller) async {
        this.controller = controller;
        await CookieManager.instance(
          webViewEnvironment: webViewEnvironment,
        ).deleteAllCookies();
      },
      onLoadStart: (controller, url) async {
        final uri = url.toString();

        if (uri.startsWith('https://users.nexusmods.com')) {
          widget.onShowOverlay(true);
          return;
        }
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        if (!mounted) return;
        widget.onShowOverlay(false);

        if (errorResponse.contentType != 'text/html') {
          NotificationService.error(
            message:
                'An error occurred while loading the page. Please try again later.',
          );
          return;
        }

        Logger.root.severe(
          'http error: ${String.fromCharCodes(errorResponse.data ?? [])} (code: ${errorResponse.statusCode}, url: ${request.url})',
        );
      },
      onLoadStop: (controller, url) async {
        if (!mounted) return;

        final uri = url.toString();
        if (uri.startsWith('https://users.nexusmods.com/account') ||
            uri.startsWith('https://users.nexusmods.com/account/security') ||
            uri == 'https://www.nexusmods.com/' ||
            uri.startsWith('https://www.nexusmods.com/?')) {
          widget.onShowOverlay(true);
          await controller.loadUrl(
            urlRequest: URLRequest(
              url: WebUri('https://www.nexusmods.com/settings/api-keys'),
            ),
          );
          return;
        }

        if (uri.startsWith('https://users.nexusmods.com/auth') ||
            uri.startsWith('https://users.nexusmods.com/register')) {
          _apiKeyPollTimer?.cancel();
          widget.onShowOverlay(false);
          return;
        }

        if (uri.startsWith('https://www.nexusmods.com/settings/api-keys')) {
          widget.onShowOverlay(false);
          await controller.evaluateJavascript(source: _scrollToPersonalApiKeyJs);
          _startApiKeyPolling(controller);
          return;
        }
      },
    );
  }
}
