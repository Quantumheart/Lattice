import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/app_router.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/theme/lattice_theme.dart';
import 'package:lattice/features/calling/widgets/incoming_call_overlay.dart';
import 'package:lattice/features/chat/services/media_playback_service.dart';
import 'package:lattice/features/chat/services/opengraph_service.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:lattice/features/notifications/services/notification_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await vod.init();
  final clientManager = ClientManager();
  await clientManager.init();
  runApp(LatticeApp(clientManager: clientManager));
}

class LatticeApp extends StatefulWidget {
  const LatticeApp({required this.clientManager, super.key});

  final ClientManager clientManager;

  @override
  State<LatticeApp> createState() => _LatticeAppState();
}

class _LatticeAppState extends State<LatticeApp> {
  GoRouter? _router;
  MatrixService? _routerService;

  /// Rebuild the router when the active [MatrixService] changes (account
  /// switch) so that `refreshListenable` points at the right instance.
  GoRouter _ensureRouter(MatrixService matrix) {
    if (_routerService != matrix) {
      _router?.dispose();
      _router = buildRouter(matrix);
      _routerService = matrix;
    }
    return _router!;
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClientManager>.value(
            value: widget.clientManager,),
        ChangeNotifierProvider(create: (_) {
          final prefs = PreferencesService();
          unawaited(prefs.init());
          return prefs;
        },),
        ChangeNotifierProvider(create: (_) => MediaPlaybackService()),
        Provider(
          create: (_) => OpenGraphService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer2<ClientManager, PreferencesService>(
            builder: (context, manager, prefs, _) {
              final matrix = manager.activeService;
              final router = _ensureRouter(matrix);

              return _NotificationServiceHolder(
                matrixService: matrix,
                preferencesService: prefs,
                child: ChangeNotifierProvider<MatrixService>.value(
                  value: matrix,
                  child: ChangeNotifierProxyProvider<MatrixService, InboxController>(
                    create: (ctx) => InboxController(
                      client: ctx.read<MatrixService>().client,
                    ),
                    update: (_, matrix, previous) {
                      if (previous == null) return InboxController(client: matrix.client);
                      previous.updateClient(matrix.client);
                      return previous;
                    },
                    child: ChangeNotifierProxyProvider<MatrixService, CallService>(
                      create: (ctx) => CallService(client: ctx.read<MatrixService>().client),
                      update: (_, matrix, previous) {
                        if (previous == null) return CallService(client: matrix.client);
                        previous.updateClient(matrix.client);
                        return previous;
                      },
                      child: Builder(
                        builder: (context) {
                          final theme = LatticeTheme.light(lightDynamic);
                          final darkTheme = LatticeTheme.dark(darkDynamic);

                          return MaterialApp.router(
                            title: 'Lattice',
                            debugShowCheckedModeBanner: false,
                            theme: theme,
                            darkTheme: darkTheme,
                            themeMode: prefs.themeMode,
                            routerConfig: router,
                            builder: (context, child) => IncomingCallOverlay(
                              child: child ?? const SizedBox.shrink(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Notification service lifecycle ──────────────────────────────

class _NotificationServiceHolder extends StatefulWidget {
  const _NotificationServiceHolder({
    required this.matrixService,
    required this.preferencesService,
    required this.child,
  });

  final MatrixService matrixService;
  final PreferencesService preferencesService;
  final Widget child;

  @override
  State<_NotificationServiceHolder> createState() =>
      _NotificationServiceHolderState();
}

class _NotificationServiceHolderState
    extends State<_NotificationServiceHolder> with WidgetsBindingObserver {
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
    // Only cancel when the selected room actually changes — canceling on
    // every sync races with _showLinuxNotification (the notification hasn't
    // been stored yet when the sync triggers notifyListeners).
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
  void didUpdateWidget(covariant _NotificationServiceHolder old) {
    super.didUpdateWidget(old);
    if (old.matrixService != widget.matrixService) {
      old.matrixService.removeListener(_onMatrixChanged);
      widget.matrixService.addListener(_onMatrixChanged);
      _notificationService?.dispose();
      _notificationService = null;
      unawaited(_initNotifications());
      return;
    }
    // Only start/stop on actual login state transitions.
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
