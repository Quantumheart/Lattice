import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart' show MatrixService;
import '../widgets/homeserver_controller.dart';
import 'login_screen.dart';
import 'registration_screen.dart';

class HomeserverScreen extends StatefulWidget {
  const HomeserverScreen({super.key});

  @override
  State<HomeserverScreen> createState() => _HomeserverScreenState();
}

class _HomeserverScreenState extends State<HomeserverScreen>
    with SingleTickerProviderStateMixin {
  final _homeserverCtrl = TextEditingController(text: 'matrix.org');

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final HomeserverController _controller;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _controller = HomeserverController(
      matrixService: context.read<MatrixService>(),
    );
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _fadeCtrl.dispose();
    _homeserverCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _continue() async {
    final text = _homeserverCtrl.text.trim();
    if (text.isEmpty) return;
    final caps = await _controller.checkServer(text);
    if (!mounted || caps == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          homeserver: text,
          capabilities: caps,
        ),
      ),
    );
  }

  void _openRegistration() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegistrationScreen(
          initialHomeserver: _homeserverCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isChecking = _controller.state == HomeserverState.checking;
    final hasError = _controller.state == HomeserverState.error;

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
                    'Connect to the Matrix network',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 40),

                  // ── Homeserver ──
                  TextField(
                    controller: _homeserverCtrl,
                    enabled: !isChecking,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.dns_outlined,
                          color: cs.onSurfaceVariant),
                      hintText: 'Homeserver',
                      errorText: hasError ? _controller.error : null,
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
                    textInputAction: TextInputAction.done,
                    onSubmitted: isChecking ? null : (_) => _continue(),
                  ),
                  const SizedBox(height: 24),

                  // ── Continue button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: isChecking ? null : _continue,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isChecking
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('Continue'),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
