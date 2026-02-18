import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'services/matrix_service.dart';
import 'theme/lattice_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LatticeApp());
}

class LatticeApp extends StatelessWidget {
  const LatticeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MatrixService(),
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          return Consumer<MatrixService>(
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
          );
        },
      ),
    );
  }
}
