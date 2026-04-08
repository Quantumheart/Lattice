import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/app_router.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/core/theme/lattice_theme.dart';
import 'package:lattice/core/theme/theme_presets.dart';
import 'package:lattice/core/utils/vodozemac_init.dart';
import 'package:lattice/features/auth/services/sso_web_init.dart';
import 'package:lattice/features/calling/services/push_to_talk_service.dart';
import 'package:lattice/features/calling/services/ringtone_service.dart';
import 'package:lattice/features/calling/widgets/incoming_call_overlay.dart';
import 'package:lattice/features/chat/services/media_playback_service.dart';
import 'package:lattice/features/chat/services/opengraph_service.dart';
import 'package:lattice/features/e2ee/widgets/verification_request_listener.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:lattice/features/notifications/widgets/notification_lifecycle_observer.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initVodozemac();
  await AppConfig.load();
  final clientManager = ClientManager();
  await clientManager.init();

  final pendingSso = await checkPendingSsoLogin();
  if (pendingSso != null) {
    await clientManager.activeService.completeSsoLogin(
      homeserver: pendingSso.homeserver,
      loginToken: pendingSso.loginToken,
    );
  }

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
  MatrixService? _routerMatrixService;
  final ringtoneService = RingtoneService();

  /// Rebuild the router when the active [MatrixService] changes (account
  /// switch) so that `refreshListenable` points at the right instance.
  GoRouter _ensureRouter(MatrixService matrix) {
    if (_routerMatrixService != matrix) {
      _router?.dispose();
      _router = buildRouter(matrix);
      _routerMatrixService = matrix;
    }
    return _router!;
  }

  @override
  void dispose() {
    _router?.dispose();
    unawaited(ringtoneService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClientManager>.value(
          value: widget.clientManager,
        ),
        ChangeNotifierProvider(
          create: (_) {
            final prefs = PreferencesService();
            unawaited(prefs.init());
            return prefs;
          },
        ),
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

              return ChangeNotifierProvider<MatrixService>.value(
                value: matrix,
                child: ChangeNotifierProvider<SelectionService>.value(
                value: matrix.selection,
                child:
                    ChangeNotifierProxyProvider<MatrixService, InboxController>(
                  create: (ctx) => InboxController(
                    client: ctx.read<MatrixService>().client,
                  ),
                  update: (_, matrix, previous) {
                    if (previous == null) {
                      return InboxController(client: matrix.client);
                    }
                    previous.updateClient(matrix.client);
                    return previous;
                  },
                  child:
                      ChangeNotifierProxyProvider<MatrixService, CallService>(
                    create: (ctx) {
                      final cs = CallService(
                        client: ctx.read<MatrixService>().client,
                        ringtoneService: ringtoneService,
                      )..preferencesService = prefs;
                      if (ctx.read<MatrixService>().isLoggedIn) cs.init();
                      return cs;
                    },
                    update: (_, matrix, previous) {
                      if (previous == null) {
                        final cs = CallService(
                          client: matrix.client,
                          ringtoneService: ringtoneService,
                        )..preferencesService = prefs;
                        if (matrix.isLoggedIn) cs.init();
                        return cs;
                      }
                      previous
                        ..updateClient(matrix.client)
                        ..preferencesService = prefs;
                      if (matrix.isLoggedIn) {
                        previous.init();
                      }
                      return previous;
                    },
                    child: ChangeNotifierProvider(
                      create: (ctx) => PushToTalkService(
                        callService: ctx.read<CallService>(),
                        prefs: prefs,
                        ringtoneService: ringtoneService,
                      ),
                      child: Builder(
                      builder: (context) {
                        final callService = context.read<CallService>();
                        final isCustom = prefs.themePreset == 'custom';
                        final preset =
                            isCustom ? null : getPreset(prefs.themePreset);
                        final customScheme =
                            isCustom ? prefs.customTheme : null;

                        final theme = customScheme != null
                            ? LatticeTheme.light(
                                dynamic: customScheme.toColorScheme(
                                  Brightness.light,
                                ),
                              )
                            : LatticeTheme.light(
                                dynamic: lightDynamic,
                                preset: preset,
                              );
                        final darkTheme = customScheme != null
                            ? LatticeTheme.dark(
                                dynamic: customScheme.toColorScheme(
                                  Brightness.dark,
                                ),
                              )
                            : LatticeTheme.dark(
                                dynamic: darkDynamic,
                                preset: preset,
                              );

                        final themeMode = isCustom
                            ? prefs.customThemeMode
                            : (preset?.forcedMode ?? prefs.themeMode);

                        return NotificationLifecycleObserver(
                          matrixService: matrix,
                          preferencesService: prefs,
                          callService: callService,
                          router: router,
                          child: MaterialApp.router(
                            title: 'Lattice',
                            debugShowCheckedModeBanner: false,
                            theme: theme,
                            darkTheme: darkTheme,
                            themeMode: themeMode,
                            routerConfig: router,
                            builder: (context, child) =>
                                VerificationRequestListener(
                              router: router,
                              child: IncomingCallOverlay(
                                router: router,
                                child: child ?? const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
