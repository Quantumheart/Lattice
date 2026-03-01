import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/chat_screen.dart';
import '../screens/homeserver_screen.dart';
import '../screens/home_shell.dart';
import '../screens/login_screen.dart';
import '../screens/registration_screen.dart';
import '../screens/devices_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/settings_screen.dart';
import '../services/matrix_service.dart';
import '../widgets/room_details_panel.dart';
import 'route_names.dart';

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
          final homeserver = state.extra as String? ?? 'matrix.org';
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
                ],
              ),
              GoRoute(
                path: 'spaces',
                name: Routes.spaces,
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: 'settings',
                name: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
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
