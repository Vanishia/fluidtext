import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/app_settings.dart';
import 'package:fluidtext/features/bookshelf/launch_page.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/main.dart';
import 'package:fluidtext/theme/app_theme.dart';

void main() {
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
    await tester.pumpWidget(const MyApp(initialLaunchState: LaunchState()));
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
}
