import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../widgets/login_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.homeserver,
    required this.capabilities,
  });

  final String homeserver;
  final ServerAuthCapabilities capabilities;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _controller = LoginController(
      matrixService: context.read<MatrixService>(),
      clientManager: context.read<ClientManager>(),
      homeserver: widget.homeserver,
      capabilities: widget.capabilities,
    );
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _fadeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.state == LoginState.done) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  Future<void> _login() async {
    await _controller.login(
      username: _usernameCtrl.text,
      password: _passwordCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isLoggingIn = _controller.state == LoginState.loggingIn;
    final isSsoInProgress = _controller.state == LoginState.ssoInProgress;
    final formEnabled = _controller.state == LoginState.formReady;

    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
      ),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Homeserver chip ──
                  ActionChip(
                    avatar: Icon(Icons.dns_outlined, size: 18,
                        color: cs.onSurfaceVariant),
                    label: Text(widget.homeserver),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to ${widget.homeserver}',
                    style: tt.titleMedium,
                  ),
                  const SizedBox(height: 24),

                  // ── SSO waiting state ──
                  if (isSsoInProgress) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Complete sign-in in your browser,\n'
                      'then return to Lattice.',
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _controller.cancelSso,
                      child:
                          Text('Cancel', style: TextStyle(color: cs.error)),
                    ),
                  ],

                  // ── Username & Password ──
                  if (_controller.supportsPassword && !isSsoInProgress) ...[
                    TextField(
                      controller: _usernameCtrl,
                      enabled: formEnabled,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.person_outline,
                            color: cs.onSurfaceVariant),
                        hintText: 'Username',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordCtrl,
                      enabled: formEnabled,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.lock_outline,
                            color: cs.onSurfaceVariant),
                        hintText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: formEnabled ? (_) => _login() : null,
                    ),
                    const SizedBox(height: 8),

                    // ── Error ──
                    if (_controller.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          _controller.error!,
                          style: tt.bodyMedium?.copyWith(color: cs.error),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ── Login button ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: formEnabled ? _login : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoggingIn
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Text('Sign In'),
                      ),
                    ),
                  ],

                  // ── SSO-only error ──
                  if (!_controller.supportsPassword &&
                      _controller.supportsSso &&
                      !isSsoInProgress &&
                      _controller.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _controller.error!,
                        style: tt.bodyMedium?.copyWith(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // ── SSO Buttons ──
                  if (_controller.supportsSso && !isSsoInProgress) ...[
                    const SizedBox(height: 8),
                    if (_controller.supportsPassword) ...[
                      Row(children: [
                        Expanded(child: Divider(color: cs.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or', style: tt.bodySmall),
                        ),
                        Expanded(child: Divider(color: cs.outlineVariant)),
                      ]),
                      const SizedBox(height: 14),
                    ],
                    if (_controller.ssoProviders.isNotEmpty)
                      ..._controller.ssoProviders.map(
                        (provider) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: formEnabled
                                  ? () => _controller.startSsoLogin(
                                      providerId: provider.id)
                                  : null,
                              icon: const Icon(Icons.open_in_browser),
                              label: Text('Sign in with ${provider.name}'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: formEnabled
                                ? () => _controller.startSsoLogin()
                                : null,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Sign in with SSO'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
