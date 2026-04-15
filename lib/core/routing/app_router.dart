import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/client_manager.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/auth/screens/homeserver_screen.dart';
import 'package:kohera/features/auth/screens/login_screen.dart';
import 'package:kohera/features/auth/screens/registration_screen.dart';
import 'package:kohera/features/calling/screens/call_pane.dart';
import 'package:kohera/features/calling/screens/call_screen.dart';
import 'package:kohera/features/chat/screens/chat_screen.dart';
import 'package:kohera/features/e2ee/screens/e2ee_setup_screen.dart';
import 'package:kohera/features/home/screens/home_shell.dart';
import 'package:kohera/features/home/widgets/inbox_screen.dart';
import 'package:kohera/features/rooms/widgets/room_details_panel.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/settings/screens/appearance_screen.dart';
import 'package:kohera/features/settings/screens/devices_screen.dart';
import 'package:kohera/features/settings/screens/notification_settings_screen.dart';
import 'package:kohera/features/settings/screens/settings_screen.dart';
import 'package:kohera/features/settings/screens/voice_video_settings_screen.dart';
import 'package:kohera/features/spaces/widgets/space_details_panel.dart';
import 'package:provider/provider.dart';

/// Creates the app router with auth-aware redirects.
///
/// [matrixService] is used as a [Listenable] for `refreshListenable` so that
/// login/logout automatically triggers a redirect evaluation.
GoRouter buildRouter(MatrixService matrixService) {
  return GoRouter(
    refreshListenable: Listenable.merge([matrixService, matrixService.chatBackup]),
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = matrixService.isLoggedIn;
      final loc = state.matchedLocation;
      final onAuthRoute =
          loc.startsWith('/login') || loc.startsWith('/register');
      final onSetupRoute = loc == '/e2ee-setup';
      final onAddAccountRoute = loc.startsWith('/add-account');

      if (!loggedIn && !onAuthRoute) return '/login';
      if (loggedIn && onAuthRoute && !onAddAccountRoute) return '/';

      if (loggedIn &&
          !onSetupRoute &&
          !onAuthRoute &&
          !onAddAccountRoute &&
          matrixService.chatBackup.chatBackupNeeded == true &&
          !matrixService.hasSkippedSetup) {
        return '/e2ee-setup';
      }

      return null;
    },
    routes: [
      // ── Auth routes ──────────────────────────────────────────
      GoRoute(
        path: '/login',
        name: Routes.login,
        builder: (context, state) => HomeserverScreen(key: ValueKey(state.uri)),
        routes: [
          GoRoute(
            path: ':homeserver',
            name: Routes.loginServer,
            builder: (context, state) {
              final homeserver = state.pathParameters['homeserver']!;
              final capabilities =
                  state.extra as ServerAuthCapabilities? ??
                      const ServerAuthCapabilities(supportsPassword: true);
              return LoginScreen(
                homeserver: homeserver,
                capabilities: capabilities,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/register',
        name: Routes.register,
        builder: (context, state) {
          final homeserver = state.extra as String? ??
              context.read<PreferencesService>().defaultHomeserver ??
              AppConfig.instance.defaultHomeserver;
          return RegistrationScreen(initialHomeserver: homeserver);
        },
      ),

      // ── Add-account login flow (outside shell) ──────────────
      GoRoute(
        path: '/add-account',
        name: Routes.addAccount,
        builder: (context, state) {
          final manager = context.read<ClientManager>();
          return _AddAccountGuard(
            manager: manager,
            child: ChangeNotifierProvider<MatrixService>.value(
              value: manager.pendingService!,
              child: const HomeserverScreen(isAddAccount: true),
            ),
          );
        },
        routes: [
          GoRoute(
            path: ':homeserver',
            name: Routes.addAccountServer,
            builder: (context, state) {
              final homeserver = state.pathParameters['homeserver']!;
              final capabilities =
                  state.extra as ServerAuthCapabilities? ??
                      const ServerAuthCapabilities(supportsPassword: true);
              final manager = context.read<ClientManager>();
              return _AddAccountGuard(
                manager: manager,
                child: ChangeNotifierProvider<MatrixService>.value(
                  value: manager.pendingService!,
                  child: LoginScreen(
                    homeserver: homeserver,
                    capabilities: capabilities,
                    isAddAccount: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),

      // ── E2EE setup (full-page, outside shell) ────────────────
      GoRoute(
        path: '/e2ee-setup',
        name: Routes.e2eeSetup,
        builder: (context, state) => const E2eeSetupScreen(),
      ),

      // ── Main app shell ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(routerChild: child, routerState: state),
        routes: [
          GoRoute(
            path: '/',
            name: Routes.home,
            builder: (context, state) => const RoomList(),
            routes: [
              GoRoute(
                path: 'rooms/:roomId',
                name: Routes.room,
                builder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  final eventId = state.extra as String?;
                  return ChatScreen(
                    roomId: roomId,
                    initialEventId: eventId,
                    key: ValueKey(
                      eventId != null ? '$roomId-$eventId' : roomId,
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'details',
                    name: Routes.roomDetails,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      return RoomDetailsPanel(
                        roomId: roomId,
                        isFullPage: true,
                        key: ValueKey('details-$roomId'),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'call',
                    name: Routes.call,
                    builder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      return _AdaptiveCallScreen(roomId: roomId);
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'spaces',
                name: Routes.spaces,
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: 'spaces/:spaceId/details',
                name: Routes.spaceDetails,
                builder: (context, state) {
                  final spaceId = state.pathParameters['spaceId']!;
                  return SpaceDetailsPanel(
                    spaceId: spaceId,
                    isFullPage: true,
                    key: ValueKey('space-details-$spaceId'),
                  );
                },
              ),
              GoRoute(
                path: 'inbox',
                name: Routes.inbox,
                builder: (context, state) => const InboxScreen(),
              ),
              GoRoute(
                path: 'settings',
                name: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'appearance',
                    name: Routes.settingsAppearance,
                    builder: (context, state) =>
                        const AppearanceScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    name: Routes.settingsNotifications,
                    builder: (context, state) =>
                        const NotificationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'devices',
                    name: Routes.settingsDevices,
                    builder: (context, state) => const DevicesScreen(),
                  ),
                  GoRoute(
                    path: 'voice-video',
                    name: Routes.settingsVoiceVideo,
                    builder: (context, state) =>
                        const VoiceVideoSettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _AddAccountGuard extends StatefulWidget {
  const _AddAccountGuard({required this.manager, required this.child});

  final ClientManager manager;
  final Widget child;

  @override
  State<_AddAccountGuard> createState() => _AddAccountGuardState();
}

class _AddAccountGuardState extends State<_AddAccountGuard> {
  @override
  void dispose() {
    widget.manager.cancelPendingService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AdaptiveCallScreen extends StatelessWidget {
  const _AdaptiveCallScreen({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= HomeShell.wideBreakpoint;
    if (isWide) return const CallPane();
    final room =
        context.read<MatrixService>().client.getRoomById(roomId);
    return CallScreen(
      roomId: roomId,
      displayName: room?.getLocalizedDisplayname() ?? 'Call',
    );
  }
}
