import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'app_settings.dart';
import 'features/bookshelf/launch_page.dart';
import 'features/migration/migration_page.dart';
import 'features/reader/reader_background_settings.dart';
import 'migration/app_bootstrap_coordinator.dart';
import 'migration/migration_runner.dart';
import 'repositories/library_data_access.dart';
import 'storage/storage_layout.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Rollback switch: keep the pre-migration startup path entirely.
  if (LibraryDataAccess.forceIsarLibrary) {
    await startNormalApplication();
    return;
  }

  final decision = await const AppBootstrapCoordinator().decide();
  switch (decision.action) {
    case AppBootstrapAction.normalStart:
      AppStorageResolver.useActiveRuntimeLayout(
        AppStorageResolver.targetRuntimeLayout,
      );
      await startNormalApplication();
    case AppBootstrapAction.freshInstall:
      AppStorageResolver.useActiveRuntimeLayout(
        AppStorageResolver.targetRuntimeLayout,
      );
      await initializeFreshStorage(decision.targetLayout);
      await startNormalApplication();
    case AppBootstrapAction.migrationRequired:
    case AppBootstrapAction.recoveryRequired:
    case AppBootstrapAction.migrationUnavailable:
      // Do not initialize settings or repositories here: they could write
      // defaults over legacy data or open the old database.
      runApp(
        MigrationRootApp(
          decision: decision,
          onEnterApp: () async {
            AppStorageResolver.useActiveRuntimeLayout(
              AppStorageResolver.targetRuntimeLayout,
            );
            await startNormalApplication();
          },
        ),
      );
  }
}

/// Loads settings and the previous session, then runs the normal app tree.
Future<void> startNormalApplication() async {
  final settingsFuture = initializeAppSettings();
  final launchStateFuture = loadLaunchState();
  await settingsFuture;
  final launchState = await launchStateFuture;
  runApp(MyApp(initialLaunchState: launchState));
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

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.initialLaunchState});

  final LaunchState initialLaunchState;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Future<Color>? _seedColorFuture;
  String? _seedColorCacheKey;

  void _ensureSeedColorFuture(ReaderBackgroundSettings settings) {
    final key = [
      settings.source.name,
      settings.paletteKey,
      settings.imagePath ?? '',
    ].join('|');
    if (_seedColorCacheKey == key && _seedColorFuture != null) return;
    _seedColorCacheKey = key;
    _seedColorFuture = AppThemeSeedResolver.resolve(settings);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        _ensureSeedColorFuture(backgroundSettings);
        final fallbackSeed = AppThemeSeedResolver.normalize(
          backgroundSettings.palette.color,
        );
        return FutureBuilder<Color>(
          key: ValueKey(_seedColorCacheKey),
          future: _seedColorFuture,
          initialData: fallbackSeed,
          builder: (context, seedSnapshot) {
            final seedColor = seedSnapshot.data ?? fallbackSeed;
            return ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeSetting,
              builder: (context, themeMode, _) {
                return ValueListenableBuilder(
                  valueListenable: appFontSetting,
                  builder: (context, fontSettings, _) {
                    return MaterialApp(
                      title: 'FluidText',
                      scrollBehavior: const _FluidScrollBehavior(),
                      theme: buildAppTheme(
                        brightness: Brightness.light,
                        seedColor: seedColor,
                        fontFamily: fontSettings.fontFamily,
                      ),
                      darkTheme: buildAppTheme(
                        brightness: Brightness.dark,
                        seedColor: seedColor,
                        fontFamily: fontSettings.fontFamily,
                      ),
                      themeMode: themeMode,
                      builder: (context, child) {
                        final theme = Theme.of(context);
                        return AnnotatedRegion<SystemUiOverlayStyle>(
                          value: _systemUiStyleForTheme(theme),
                          child: child ?? const SizedBox.shrink(),
                        );
                      },
                      home: LaunchPage(
                        resumeLastSession: false,
                        initialState: widget.initialLaunchState,
                      ),
                    );
                  },
                );
              },
            );
          },
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
