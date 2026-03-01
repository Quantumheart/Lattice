import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'routing/app_router.dart';
import 'services/client_manager.dart';
import 'services/matrix_service.dart';
import 'services/notification_service.dart';
import 'services/opengraph_service.dart';
import 'services/preferences_service.dart';
import 'theme/lattice_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await vod.init();
  final clientManager = ClientManager();
  await clientManager.init();
  runApp(LatticeApp(clientManager: clientManager));
}

class LatticeApp extends StatefulWidget {
  const LatticeApp({super.key, required this.clientManager});

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
            value: widget.clientManager),
        ChangeNotifierProvider(create: (_) => PreferencesService()..init()),
        Provider(
          create: (_) => OpenGraphService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          return Consumer2<ClientManager, PreferencesService>(
            builder: (context, manager, prefs, _) {
              final matrix = manager.activeService;
              final router = _ensureRouter(matrix);

              return _NotificationServiceHolder(
                matrixService: matrix,
                preferencesService: prefs,
                child: ChangeNotifierProvider<MatrixService>.value(
                  value: matrix,
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
                      );
                    },
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
    _initNotifications();
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
      _notificationService?.cancelForRoom(roomId);
    }
    _lastSelectedRoomId = roomId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notificationService?.isAppResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      final roomId = widget.matrixService.selectedRoomId;
      if (roomId != null) {
        _notificationService?.cancelForRoom(roomId);
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
      _initNotifications();
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
        _notificationService?.cancelAll();
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
