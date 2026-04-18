import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/auth/services/deep_link_service.dart';
import 'package:provider/provider.dart';

class DeepLinkListener extends StatefulWidget {
  const DeepLinkListener({
    required this.service,
    required this.router,
    required this.child,
    super.key,
  });

  final DeepLinkService service;
  final GoRouter router;
  final Widget child;

  @override
  State<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends State<DeepLinkListener> {
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.service.start());
    });
  }

  @override
  void dispose() {
    widget.service.removeListener(_onIntent);
    super.dispose();
  }

  void _onIntent() {
    if (widget.service.pending == null) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_handle());
    });
  }

  Future<void> _handle() async {
    if (_handling) return;
    final intent = widget.service.pending;
    if (intent is! RegisterInviteIntent) return;
    _handling = true;
    try {
      final matrix = context.read<MatrixService>();
      if (!matrix.isLoggedIn) {
        _goRegister(intent);
        return;
      }
      await _promptAddAccount(intent);
    } finally {
      widget.service.consume();
      _handling = false;
    }
  }

  void _goRegister(RegisterInviteIntent intent) {
    final uri = Uri(
      path: '/register',
      queryParameters: {'server': intent.server, 'token': intent.token},
    );
    widget.router.go(uri.toString());
  }

  Future<void> _promptAddAccount(RegisterInviteIntent intent) async {
    final navContext =
        widget.router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;
    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this invite?'),
        content: Text(
          'A registration invite for ${intent.server} was shared with '
          'Kohera. Invite tokens are single-use — this one may be '
          'invalidated if it expires or is used elsewhere.\n\n'
          'Create a new account on ${intent.server}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final manager = context.read<ClientManager>();
    try {
      await manager.createLoginService();
    } catch (e) {
      debugPrint('[Kohera] createLoginService failed: $e');
      await _showAddAccountError();
      return;
    }

    if (!mounted) return;
    final uri = Uri(
      path: '/add-account/register',
      queryParameters: {'server': intent.server, 'token': intent.token},
    );
    widget.router.go(uri.toString());
  }

  Future<void> _showAddAccountError() async {
    final navContext =
        widget.router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;
    await showDialog<void>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text("Couldn't start new account"),
        content: const Text(
          'Something went wrong setting up a new account slot. Please '
          'try the invite link again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
