import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../widgets/login_controller.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _homeserverCtrl = TextEditingController(text: 'matrix.org');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final LoginController _controller;
  Timer? _debounce;

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
      homeserver: _homeserverCtrl.text,
    );
    _controller.addListener(_onControllerChanged);
    _controller.checkServer();

    _homeserverCtrl.addListener(_onHomeserverChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _homeserverCtrl.removeListener(_onHomeserverChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _fadeCtrl.dispose();
    _homeserverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onHomeserverChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _controller.updateHomeserver(_homeserverCtrl.text);
    });
  }

  void _openRegistration() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
    );
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

    final isChecking = _controller.state == LoginState.checkingServer;
    final isLoggingIn = _controller.state == LoginState.loggingIn;
    final isSsoInProgress = _controller.state == LoginState.ssoInProgress;
    final formEnabled = _controller.state == LoginState.formReady;

    return Scaffold(
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
                  // ── Logo ──
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.hub_rounded,
                      size: 36,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Lattice', style: tt.displayLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to the Matrix network',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 40),

                  // ── Homeserver ──
                  TextField(
                    controller: _homeserverCtrl,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.dns_outlined,
                          color: cs.onSurfaceVariant),
                      hintText: 'Homeserver',
                      errorText: _controller.state == LoginState.serverError
                          ? _controller.error
                          : null,
                      suffixIcon: isChecking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),

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
                    if (_controller.error != null &&
                        _controller.state != LoginState.serverError)
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
                      _controller.error != null &&
                      _controller.state != LoginState.serverError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _controller.error!,
                        style: tt.bodyMedium?.copyWith(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _openRegistration,
                    child: Text(
                      'Create an account',
                      style: TextStyle(color: cs.primary),
                    ),
                  ),

                  // ── SSO Buttons ──
                  if (_controller.supportsSso && !isSsoInProgress) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or', style: tt.bodySmall),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                    ]),
                    const SizedBox(height: 14),
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
