import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'services/client_manager.dart';
import 'services/matrix_service.dart';
import 'theme/lattice_theme.dart';
import 'screens/login_screen.dart';
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
    return ChangeNotifierProvider<ClientManager>.value(
      value: clientManager,
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          return Consumer<ClientManager>(
            builder: (context, manager, _) {
              return ChangeNotifierProvider<MatrixService>.value(
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
                      themeMode: ThemeMode.system,
                      home: matrix.isLoggedIn
                          ? const HomeShell()
                          : const LoginScreen(),
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
