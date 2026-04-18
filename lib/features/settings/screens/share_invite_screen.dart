import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ShareInviteScreen extends StatefulWidget {
  const ShareInviteScreen({super.key});

  @override
  State<ShareInviteScreen> createState() => _ShareInviteScreenState();
}

class _ShareInviteScreenState extends State<ShareInviteScreen> {
  late final TextEditingController _serverCtrl;
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final host =
        context.read<MatrixService>().client.homeserver?.host ?? '';
    _serverCtrl = TextEditingController(text: host);
    _serverCtrl.addListener(_onChanged);
    _tokenCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _serverCtrl
      ..removeListener(_onChanged)
      ..dispose();
    _tokenCtrl
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String get _server => _serverCtrl.text.trim();
  String get _token => _tokenCtrl.text.trim();
  bool get _ready => _server.isNotEmpty && _token.isNotEmpty;

  String get _deepLink => Uri(
        scheme: 'kohera',
        host: 'register',
        queryParameters: {'server': _server, 'token': _token},
      ).toString();

  String get _landingHtml => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="robots" content="noindex,nofollow">
  <title>Opening Kohera…</title>
</head>
<body>
  <p id="fallback" style="display:none">
    If Kohera does not open,
    <a href="https://github.com/Quantumheart/kohera/releases">download it</a>.
  </p>
  <script>
    window.location.replace(${_jsScriptSafeString(_deepLink)});
    setTimeout(function () {
      document.getElementById('fallback').style.display = 'block';
    }, 2500);
  </script>
</body>
</html>
''';

  /// JSON-encodes [s] for embedding inside an HTML `<script>` block.
  /// `jsonEncode` handles quote/backslash/control-char escaping; the extra
  /// `</` → `<\/` replacement prevents the encoded string from prematurely
  /// closing the surrounding `<script>` tag if [s] contains `</script>`.
  static String _jsScriptSafeString(String s) =>
      jsonEncode(s).replaceAll('</', r'<\/');

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Share an invite')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Paste a registration token obtained from your homeserver '
            'admin. Kohera turns it into a link, QR code, or landing-page '
            'snippet you can share. Nothing is sent or stored.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serverCtrl,
            decoration: const InputDecoration(
              labelText: 'Homeserver',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Registration token',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (!_ready)
            Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Enter a homeserver and token to generate outputs.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            _OutputCard(
              icon: Icons.link,
              title: 'Deep link',
              value: _deepLink,
              monospace: true,
              onCopy: () => _copy(_deepLink, 'Link'),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.qr_code_2),
                        const SizedBox(width: 8),
                        Text(
                          'QR code',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: QrImageView(
                        data: _deepLink,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _OutputCard(
              icon: Icons.code,
              title: 'Landing-page HTML',
              value: _landingHtml,
              monospace: true,
              onCopy: () => _copy(_landingHtml, 'HTML'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OutputCard extends StatelessWidget {
  const _OutputCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onCopy,
    this.monospace = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onCopy;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: onCopy,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                value,
                style: monospace
                    ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
