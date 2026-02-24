import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'services/client_manager.dart';
import 'services/matrix_service.dart';
import 'services/notification_service.dart';
import 'services/preferences_service.dart';
import 'theme/lattice_theme.dart';
import 'screens/homeserver_screen.dart';
import 'screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await vod.init();
  final clientManager = ClientManager();
  await clientManager.init();
  runApp(LatticeApp(clientManager: clientManager));
}

class LatticeApp extends StatelessWidget {
  const LatticeApp({super.key, required this.clientManager});

  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClientManager>.value(value: clientManager),
        ChangeNotifierProvider(create: (_) => PreferencesService()..init()),
      ],
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          return Consumer2<ClientManager, PreferencesService>(
            builder: (context, manager, prefs, _) {
              return _NotificationServiceHolder(
                matrixService: manager.activeService,
                preferencesService: prefs,
                child: ChangeNotifierProvider<MatrixService>.value(
                  value: manager.activeService,
                  child: Consumer<MatrixService>(
                    builder: (context, matrix, _) {
                      final theme = LatticeTheme.light(lightDynamic);
                      final darkTheme = LatticeTheme.dark(darkDynamic);

                      return MaterialApp(
                        title: 'Lattice',
                        debugShowCheckedModeBanner: false,
                        theme: theme,
                        darkTheme: darkTheme,
                        themeMode: prefs.themeMode,
                        home: matrix.isLoggedIn
                            ? const HomeShell()
                            : HomeserverScreen(key: ObjectKey(matrix)),
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
