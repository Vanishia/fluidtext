import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/app_settings.dart';
import 'package:fluidtext/features/bookshelf/launch_page.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/features/settings/app_font_settings.dart';
import 'package:fluidtext/main.dart';
import 'package:fluidtext/theme/app_theme.dart';

void main() {
  test('Windows system font uses Flutter Windows typography', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final theme = buildAppTheme(
      brightness: Brightness.light,
      seedColor: Colors.blue,
    );

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Segoe UI');
  });

  test(
    'missing wallpaper image falls back to the selected background color',
    () async {
      const settings = ReaderBackgroundSettings(
        source: ReaderBackgroundSource.image,
        paletteKey: 'sage',
        imagePath: 'missing-wallpaper.png',
      );

      expect(
        await AppThemeSeedResolver.resolve(settings),
        AppThemeSeedResolver.normalize(settings.palette.color),
      );
    },
  );

  testWidgets('root color scheme follows reader background changes', (
    tester,
  ) async {
    final originalBackground = readerBackgroundSetting.value;
    final originalThemeMode = themeModeSetting.value;
    addTearDown(() {
      readerBackgroundSetting.value = originalBackground;
      themeModeSetting.value = originalThemeMode;
    });

    themeModeSetting.value = ThemeMode.light;
    readerBackgroundSetting.value = const ReaderBackgroundSettings(
      paletteKey: 'mist',
    );
    await tester.pumpWidget(MyApp(initialization: Future.value(const LaunchState())));
    await tester.pumpAndSettle();
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final mistPrimary = materialApp.theme!.colorScheme.primary;

    readerBackgroundSetting.value = const ReaderBackgroundSettings(
      paletteKey: 'sage',
    );
    await tester.pumpAndSettle();
    final updatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final sageSeed = AppThemeSeedResolver.normalize(
      readerBackgroundSetting.value.palette.color,
    );

    expect(updatedApp.theme!.colorScheme.primary, isNot(mistPrimary));
    expect(
      updatedApp.theme!.colorScheme.primary,
      buildAppTheme(
        brightness: Brightness.light,
        seedColor: sageSeed,
      ).colorScheme.primary,
    );
  });

  testWidgets('custom font selection updates both app themes', (tester) async {
    final originalFont = appFontSetting.value;
    addTearDown(() => appFontSetting.value = originalFont);
    appFontSetting.value = const AppFontSettings(
      source: AppFontSource.custom,
      fontFamily: 'FluidTextUserFont_test',
      displayName: '测试字体',
      fontPath: 'test.ttf',
    );

    await tester.pumpWidget(MyApp(initialization: Future.value(const LaunchState())));
    await tester.pumpAndSettle();
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(
      materialApp.theme!.textTheme.bodyMedium!.fontFamily,
      'FluidTextUserFont_test',
    );
    expect(
      materialApp.darkTheme!.textTheme.bodyMedium!.fontFamily,
      'FluidTextUserFont_test',
    );
  });
}
