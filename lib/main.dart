import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'services/matrix_service.dart';
import 'theme/helix_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HelixMatrixApp());
}

class HelixMatrixApp extends StatelessWidget {
  const HelixMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MatrixService(),
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          return Consumer<MatrixService>(
            builder: (context, matrix, _) {
              final theme = HelixTheme.light(lightDynamic);
              final darkTheme = HelixTheme.dark(darkDynamic);

              return MaterialApp(
                title: 'Helix',
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
