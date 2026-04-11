import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/services/notification_service.dart';
import 'package:lattice/features/notifications/services/push_service.dart';
import 'package:lattice/features/notifications/services/web_focus_listener.dart';
import 'package:lattice/features/notifications/services/web_push_service_export.dart';
import 'package:provider/provider.dart';

class NotificationLifecycleObserver extends StatefulWidget {
  const NotificationLifecycleObserver({
    required this.matrixService,
    required this.preferencesService,
    required this.callService,
    required this.router,
    required this.child,
    super.key,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final CallService callService;
  final GoRouter router;
  final Widget child;

  @override
  State<NotificationLifecycleObserver> createState() =>
      _NotificationLifecycleObserverState();
}

class _NotificationLifecycleObserverState
    extends State<NotificationLifecycleObserver> with WidgetsBindingObserver {
  NotificationService? _notificationService;
  PushService? _pushService;
  WebPushService? _webPushService;
  bool _wasLoggedIn = false;
  String? _lastSelectedRoomId;
  Object? _focusListenerHandle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.matrixService.addListener(_onMatrixChanged);
    unawaited(_initServices());
    if (kIsWeb) {
      _focusListenerHandle = registerWindowFocusListeners(
        onFocus: () => _notificationService?.isAppResumed = true,
        onBlur: () => _notificationService?.isAppResumed = false,
      );
    }
  }

  Future<void> _initServices() async {
    final notificationService = NotificationService(
      matrixService: widget.matrixService,
      preferencesService: widget.preferencesService,
      router: widget.router,
    );
    await notificationService.init();

    final pushService = PushService(
      matrixService: widget.matrixService,
      preferencesService: widget.preferencesService,
      notificationService: notificationService,
      callService: widget.callService,
    );
    await pushService.init();

    final webPushService = WebPushService(
      matrixService: widget.matrixService,
      preferencesService: widget.preferencesService,
    );

    final loggedIn = widget.matrixService.isLoggedIn;
    if (loggedIn) {
      notificationService.startListening();
      unawaited(pushService.register());
      if (kIsWeb) {
        unawaited(_registerWebPush(webPushService));
        webPushService.listenForSubscriptionChanges();
      }
    }

    if (mounted) {
      setState(() {
        _notificationService = notificationService;
        _pushService = pushService;
        _webPushService = webPushService;
        _wasLoggedIn = loggedIn;
      });
    }
  }

  Future<void> _registerWebPush(WebPushService service) async {
    if (!widget.preferencesService.webPushEnabled) return;
    await service.register();
  }

  void _onMatrixChanged() {
    final roomId = widget.matrixService.selection.selectedRoomId;
    if (roomId != null && roomId != _lastSelectedRoomId) {
      unawaited(_notificationService?.cancelForRoom(roomId));
    }
    _lastSelectedRoomId = roomId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notificationService?.isAppResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      final roomId = widget.matrixService.selection.selectedRoomId;
      if (roomId != null) {
        unawaited(_notificationService?.cancelForRoom(roomId));
      }
    }
  }

  @override
  void didUpdateWidget(covariant NotificationLifecycleObserver old) {
    super.didUpdateWidget(old);
    if (old.matrixService != widget.matrixService) {
      old.matrixService.removeListener(_onMatrixChanged);
      widget.matrixService.addListener(_onMatrixChanged);
      _notificationService?.dispose();
      _notificationService = null;
      _pushService?.dispose();
      _pushService = null;
      _webPushService?.dispose();
      _webPushService = null;
      unawaited(_initServices());
      return;
    }
    final loggedIn = widget.matrixService.isLoggedIn;
    if (loggedIn != _wasLoggedIn) {
      _wasLoggedIn = loggedIn;
      if (loggedIn) {
        _notificationService?.startListening();
        unawaited(_pushService?.register());
        if (kIsWeb && _webPushService != null) {
          unawaited(_registerWebPush(_webPushService!));
        }
      } else {
        _notificationService?.stopListening();
        unawaited(_notificationService?.cancelAll());
        unawaited(_pushService?.unregister());
        unawaited(_webPushService?.unregister());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.matrixService.removeListener(_onMatrixChanged);
    unregisterWindowFocusListeners(_focusListenerHandle);
    _notificationService?.dispose();
    _pushService?.dispose();
    _webPushService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var child = widget.child;
    final webPush = _webPushService;
    if (webPush != null) {
      child = Provider<WebPushService>.value(
        value: webPush,
        child: child,
      );
    }
    final pushService = _pushService;
    if (pushService != null) {
      child = Provider<PushService>.value(
        value: pushService,
        child: child,
      );
    }
    return child;
  }
}
