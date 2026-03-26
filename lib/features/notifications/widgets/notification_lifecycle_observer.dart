import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/notifications/services/notification_service.dart';

class NotificationLifecycleObserver extends StatefulWidget {
  const NotificationLifecycleObserver({
    required this.matrixService,
    required this.preferencesService,
    required this.router,
    required this.child,
    super.key,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final GoRouter router;
  final Widget child;

  @override
  State<NotificationLifecycleObserver> createState() =>
      _NotificationLifecycleObserverState();
}

class _NotificationLifecycleObserverState extends State<NotificationLifecycleObserver>
    with WidgetsBindingObserver {
  NotificationService? _notificationService;
  bool _wasLoggedIn = false;
  String? _lastSelectedRoomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.matrixService.addListener(_onMatrixChanged);
    unawaited(_initNotifications());
  }

  Future<void> _initNotifications() async {
    final service = NotificationService(
      matrixService: widget.matrixService,
      preferencesService: widget.preferencesService,
      router: widget.router,
    );
    await service.init();
    final loggedIn = widget.matrixService.isLoggedIn;
    if (loggedIn) {
      service.startListening();
    }
    if (mounted) {
      setState(() {
        _notificationService = service;
        _wasLoggedIn = loggedIn;
      });
    }
  }

  void _onMatrixChanged() {
    final roomId = widget.matrixService.selectedRoomId;
    if (roomId != null && roomId != _lastSelectedRoomId) {
      unawaited(_notificationService?.cancelForRoom(roomId));
    }
    _lastSelectedRoomId = roomId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notificationService?.isAppResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      final roomId = widget.matrixService.selectedRoomId;
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
      unawaited(_initNotifications());
      return;
    }
    final loggedIn = widget.matrixService.isLoggedIn;
    if (loggedIn != _wasLoggedIn) {
      _wasLoggedIn = loggedIn;
      if (loggedIn) {
        _notificationService?.startListening();
      } else {
        _notificationService?.stopListening();
        unawaited(_notificationService?.cancelAll());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.matrixService.removeListener(_onMatrixChanged);
    _notificationService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
