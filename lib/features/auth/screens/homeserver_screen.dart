import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/matrix_service.dart' show MatrixService;
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/auth/widgets/app_logo_header.dart';
import 'package:kohera/features/auth/widgets/homeserver_controller.dart';
import 'package:provider/provider.dart';

class HomeserverScreen extends StatefulWidget {
  const HomeserverScreen({this.isAddAccount = false, super.key});

  final bool isAddAccount;

  @override
  State<HomeserverScreen> createState() => _HomeserverScreenState();
}

class _HomeserverScreenState extends State<HomeserverScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _homeserverCtrl;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final HomeserverController _controller;
  late final PreferencesService _prefs;
  bool _setAsDefault = false;

  @override
  void initState() {
    super.initState();
    _prefs = context.read<PreferencesService>();
    final saved = _prefs.defaultHomeserver;
    final initial = saved ?? AppConfig.instance.defaultHomeserver;
    _homeserverCtrl = TextEditingController(text: initial);
    _setAsDefault = saved != null;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    unawaited(_fadeCtrl.forward());

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
    unawaited(
      _prefs.setDefaultHomeserver(_setAsDefault ? text : null),
    );
    context.goNamed(
      widget.isAddAccount ? Routes.addAccountServer : Routes.loginServer,
      pathParameters: {'homeserver': text},
      extra: caps,
    );
  }

  void _openRegistration() {
    if (!mounted) return;
    context.goNamed(
      Routes.register,
      extra: _homeserverCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isChecking = _controller.state == HomeserverState.checking;
    final hasError = _controller.state == HomeserverState.error;

    return Scaffold(
      appBar: widget.isAddAccount
          ? AppBar(
              forceMaterialTransparency: true,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.go('/'),
              ),
            )
          : null,
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
                  const AppLogoHeader(
                    subtitle: 'Connect to the Matrix network',
                  ),

                  // ── Homeserver ──
                  TextField(
                    controller: _homeserverCtrl,
                    enabled: !isChecking,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.dns_outlined,
                          color: cs.onSurfaceVariant,),
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
                  const SizedBox(height: 4),

                  // ── Set as default ──
                  Transform.translate(
                    offset: const Offset(-8, 0),
                    child: GestureDetector(
                      onTap: isChecking
                          ? null
                          : () => setState(
                              () => _setAsDefault = !_setAsDefault,),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox.adaptive(
                            value: _setAsDefault,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            splashRadius: 16,
                            onChanged: isChecking
                                ? null
                                : (v) => setState(
                                    () => _setAsDefault = v ?? false,),
                          ),
                          Text(
                            'Set as default',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

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
