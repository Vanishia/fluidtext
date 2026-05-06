import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'app_settings.dart';
import 'features/bookshelf/bookshelf_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAppSettings();
  runApp(const MyApp());
}

SystemUiOverlayStyle _systemUiStyleForTheme(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: theme.colorScheme.surface,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme({required Brightness brightness}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF60A5FA),
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF5FAFF)
          : null,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(
          alpha: brightness == Brightness.light ? 0.7 : 0.6,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeModeSetting,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'FluidText',
          scrollBehavior: const _FluidScrollBehavior(),
          theme: _buildTheme(brightness: Brightness.light),
          darkTheme: _buildTheme(brightness: Brightness.dark),
          themeMode: themeMode,
          builder: (context, child) {
            final theme = Theme.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemUiStyleForTheme(theme),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const BookshelfPage(),
        );
      },
    );
  }
}

class _FluidScrollBehavior extends MaterialScrollBehavior {
  const _FluidScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}
