import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';
import '../widgets/registration_controller.dart';
import '../widgets/registration_views.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _homeserverCtrl = TextEditingController(text: 'matrix.org');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _confirmPasswordError;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final RegistrationController _controller;
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

    _controller = RegistrationController(
      matrixService: context.read<MatrixService>(),
      homeserver: _homeserverCtrl.text,
    );
    _controller.addListener(_onControllerChanged);
    _controller.checkServer();

    _homeserverCtrl.addListener(_onHomeserverChanged);
    _confirmPasswordCtrl.addListener(_onConfirmPasswordChanged);
    _passwordCtrl.addListener(_onConfirmPasswordChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _homeserverCtrl.removeListener(_onHomeserverChanged);
    _passwordCtrl.removeListener(_onConfirmPasswordChanged);
    _confirmPasswordCtrl.removeListener(_onConfirmPasswordChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _fadeCtrl.dispose();
    _homeserverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.state == RegistrationState.done) {
      // Registration complete — pop back so the root MaterialApp
      // rebuilds with HomeShell (isLoggedIn is now true).
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  void _onConfirmPasswordChanged() {
    if (_confirmPasswordError != null) {
      setState(() => _confirmPasswordError = null);
    }
  }

  void _onHomeserverChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _controller.updateHomeserver(_homeserverCtrl.text);
    });
  }

  Future<void> _submit() async {
    _confirmPasswordError = null;

    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _confirmPasswordError = 'Passwords do not match');
      return;
    }

    await _controller.submitForm(
      username: _usernameCtrl.text,
      password: _passwordCtrl.text,
      token: _tokenCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isChecking = _controller.state == RegistrationState.checkingServer;
    final isRegistering = _controller.state == RegistrationState.registering;
    final isLoading = isChecking || isRegistering;
    final isUiaStage = _controller.state == RegistrationState.enterEmail ||
        _controller.state == RegistrationState.recaptcha ||
        _controller.state == RegistrationState.acceptTerms;
    final formEnabled = _controller.serverReady && !isLoading && !isUiaStage;

    // Server-level error shown below homeserver field.
    String? homeserverError;
    if (_controller.state == RegistrationState.registrationDisabled) {
      homeserverError = 'This server does not support registration';
    } else if (_controller.state == RegistrationState.error &&
        !isUiaStage &&
        _controller.usernameError == null &&
        _controller.passwordError == null) {
      homeserverError = _controller.error;
    }

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
                    'Create an account on the Matrix network',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 40),

                  // ── Homeserver ──
                  TextField(
                    controller: _homeserverCtrl,
                    decoration: InputDecoration(
                      prefixIcon:
                          Icon(Icons.dns_outlined, color: cs.onSurfaceVariant),
                      hintText: 'Homeserver',
                      errorText: homeserverError,
                      suffixIcon: isChecking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),

                  // ── Registration Token ──
                  if (_controller.requiresToken)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextField(
                        controller: _tokenCtrl,
                        enabled: formEnabled,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.vpn_key_outlined,
                              color: cs.onSurfaceVariant),
                          hintText: 'Registration token',
                          errorText: _controller.tokenError,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),

                  // ── Username ──
                  TextField(
                    controller: _usernameCtrl,
                    enabled: formEnabled,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.person_outline,
                          color: cs.onSurfaceVariant),
                      hintText: 'Username',
                      errorText: _controller.usernameError,
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),

                  // ── Password ──
                  TextField(
                    controller: _passwordCtrl,
                    enabled: formEnabled,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      prefixIcon:
                          Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
                      hintText: 'Password',
                      errorText: _controller.passwordError,
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
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),

                  // ── Confirm Password ──
                  TextField(
                    controller: _confirmPasswordCtrl,
                    enabled: formEnabled,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      prefixIcon:
                          Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
                      hintText: 'Confirm password',
                      errorText: _confirmPasswordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () => setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: formEnabled ? (_) => _submit() : null,
                  ),
                  const SizedBox(height: 8),

                  // ── UIA stage content ──
                  if (isUiaStage)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buildUiaContent(
                            context: context,
                            controller: _controller,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _controller.cancelRegistration,
                            child: Text(
                              'Cancel registration',
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ── Register button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: formEnabled ? _submit : null,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isRegistering
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('Create Account'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Already have an account? Sign in',
                      style: TextStyle(color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
