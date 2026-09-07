import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'app_settings.dart';
import 'features/bookshelf/launch_page.dart';
import 'features/migration/migration_page.dart';
import 'features/reader/reader_background_settings.dart';
import 'features/reader/widgets/reader_background_surface.dart';
import 'migration/app_bootstrap_coordinator.dart';
import 'migration/migration_runner.dart';
import 'repositories/library_data_access.dart';
import 'services/app_logger.dart';
import 'services/update_check_service.dart';
import 'storage/storage_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/reading_skeleton.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeLogging();
  // Draw page content behind the system bars; combined with the transparent
  // systemUiOverlayStyleForTheme this keeps the three-button navigation bar
  // seamless in both light and dark mode.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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

/// Starts the file-backed logger and global error hooks. Logging is best
/// effort: a failure here must never block startup.
Future<void> _initializeLogging() async {
  final logger = AppLogger.instance;
  try {
    await logger.initialize();
  } catch (_) {
    // The logger still mirrors to developer.log without a file.
  }
  logger.installGlobalErrorHooks();
}

/// Loads settings and the previous session, then runs the normal app tree.
///
/// The app shell runs immediately and shows a card skeleton while settings
/// and the session load in the background, so cold start never blocks on a
/// blank screen.
Future<void> startNormalApplication() async {
  runApp(MyApp(initialization: _initializeNormalSession()));
}

Future<LaunchState> _initializeNormalSession() async {
  final settingsFuture = initializeAppSettings();
  final launchStateFuture = loadLaunchState();
  await settingsFuture;
  unawaited(UpdateCheckService.instance.checkForUpdate());
  return launchStateFuture;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.initialization});

  final Future<LaunchState> initialization;

  @override
  State<MyApp> createState() => _MyAppState();
}

const _windowChromeChannel = MethodChannel('fluidtext/window_chrome');
bool? _lastTitleBarDark;

/// 让 Windows 标题栏/边框跟随应用主题日夜间（DWM 沉浸式深色标题栏）。
void _syncWindowsTitleBar(Brightness brightness) {
  if (kIsWeb || !Platform.isWindows) return;
  final dark = brightness == Brightness.dark;
  if (_lastTitleBarDark == dark) return;
  _lastTitleBarDark = dark;
  unawaited(
    _windowChromeChannel
        .invokeMethod('setTitleBarDarkMode', dark)
        .catchError((_) {}),
  );
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
        // No key on purpose: a keyed FutureBuilder would recreate the whole
        // MaterialApp subtree whenever the seed color changes (background
        // switch), discarding Navigator and page state mid-session. Without
        // the key the builder keeps the previous seed while the new future
        // resolves, and the subtree state survives.
        return FutureBuilder<Color>(
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
                        _syncWindowsTitleBar(theme.brightness);
                        return AnnotatedRegion<SystemUiOverlayStyle>(
                          value: systemUiOverlayStyleForTheme(theme),
                          child: child ?? const SizedBox.shrink(),
                        );
                      },
                      home: FutureBuilder<LaunchState>(
                        future: widget.initialization,
                        builder: (context, snapshot) {
                          final state =
                              snapshot.data ??
                              (snapshot.hasError
                                  ? const LaunchState(
                                      statusMessage: '启动时出现问题，请稍后重试。',
                                    )
                                  : null);
                          if (state == null) {
                            return const _LaunchSkeletonScreen();
                          }
                          return LaunchPage(
                            resumeLastSession: false,
                            initialState: state,
                          );
                        },
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

/// 初始化期间的骨架屏：默认阅读背景上叠几张卡片占位。
class _LaunchSkeletonScreen extends StatelessWidget {
  const _LaunchSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: settings.backgroundColor(
            Theme.of(context).brightness,
          ),
          body: ReaderBackgroundSurface(
            settings: settings,
            child: const ReadingCardSkeleton(),
          ),
        );
      },
    );
  }
}
