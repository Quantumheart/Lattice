import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/models/server_auth_capabilities.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/app_config.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/auth/screens/homeserver_screen.dart';
import 'package:lattice/features/auth/screens/login_screen.dart';
import 'package:lattice/features/auth/screens/registration_screen.dart';
import 'package:lattice/features/calling/screens/call_pane.dart';
import 'package:lattice/features/chat/screens/chat_screen.dart';
import 'package:lattice/features/home/screens/home_shell.dart';
import 'package:lattice/features/home/widgets/inbox_screen.dart';
import 'package:lattice/features/rooms/widgets/room_details_panel.dart';
import 'package:lattice/features/settings/screens/appearance_screen.dart';
import 'package:lattice/features/settings/screens/devices_screen.dart';
import 'package:lattice/features/settings/screens/notification_settings_screen.dart';
import 'package:lattice/features/settings/screens/settings_screen.dart';
import 'package:lattice/features/spaces/widgets/space_details_panel.dart';
import 'package:provider/provider.dart';

/// Creates the app router with auth-aware redirects.
///
/// [matrixService] is used as a [Listenable] for `refreshListenable` so that
/// login/logout automatically triggers a redirect evaluation.
GoRouter buildRouter(MatrixService matrixService) {
  return GoRouter(
    refreshListenable: matrixService,
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = matrixService.isLoggedIn;
      final onAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register');

      if (!loggedIn && !onAuthRoute) return '/login';
      if (loggedIn && onAuthRoute) return '/';
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

      // ── Main app shell ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(routerChild: child, routerState: state),
        routes: [
          GoRoute(
            path: '/',
            name: Routes.home,
            builder: (context, state) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'rooms/:roomId',
                name: Routes.room,
                builder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  return ChatScreen(
                    roomId: roomId,
                    key: ValueKey(roomId),
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
                    builder: (context, state) => const CallPane(),
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
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
