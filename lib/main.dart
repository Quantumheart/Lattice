import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'services/client_manager.dart';
import 'services/matrix_service.dart';
import 'services/preferences_service.dart' show PreferencesService, ThemeVariant;
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
              return ChangeNotifierProvider<MatrixService>.value(
                value: manager.activeService,
                child: Consumer<MatrixService>(
                  builder: (context, matrix, _) {
                    final isClassic =
                        prefs.themeVariant == ThemeVariant.classic;
                    final theme = isClassic
                        ? LatticeTheme.classicLight()
                        : LatticeTheme.light(lightDynamic);
                    final darkTheme = isClassic
                        ? LatticeTheme.classicDark()
                        : LatticeTheme.dark(darkDynamic);

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
              );
            },
          );
        },
      ),
    );
  }
}
