import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/storage/storage_layout.dart';

void main() {
  group('StorageLayout target layout', () {
    test('uses isolated Windows local app data directories per build mode', () {
      final base = Directory(r'C:\Users\reader\AppData\Local');

      final release = StorageLayout.targetForPlatform(
        baseDirectory: base,
        platform: AppStoragePlatform.windows,
        buildMode: AppBuildMode.release,
      );
      final debug = StorageLayout.targetForPlatform(
        baseDirectory: base,
        platform: AppStoragePlatform.windows,
        buildMode: AppBuildMode.debug,
      );
      final profile = StorageLayout.targetForPlatform(
        baseDirectory: base,
        platform: AppStoragePlatform.windows,
        buildMode: AppBuildMode.profile,
      );

      expect(
        release.rootDirectory.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText',
      );
      expect(
        debug.rootDirectory.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText-Debug',
      );
      expect(
        profile.rootDirectory.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText-Profile',
      );
      expect(
        release.sqliteDatabaseFile.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText\fluidtext_library.sqlite',
      );
      expect(
        release.appBehaviorSettingsFile.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText\settings\app_behavior_settings.json',
      );
      expect(
        release.bookAssetsDirectory.path,
        r'C:\Users\reader\AppData\Local\Vanishia\FluidText\book_assets',
      );
      expect(release.usesLegacyRuntimeLocations, isFalse);
    });

    test(
      'uses the Android app-private base directory supplied by the package',
      () {
        final releaseBase = Directory('/data/user/0/com.bird.fluidtext/files');
        final debugBase = Directory(
          '/data/user/0/com.bird.fluidtext.debug/files',
        );
        final profileBase = Directory(
          '/data/user/0/com.bird.fluidtext.profile/files',
        );

        final release = StorageLayout.targetForPlatform(
          baseDirectory: releaseBase,
          platform: AppStoragePlatform.android,
          buildMode: AppBuildMode.release,
        );
        final debug = StorageLayout.targetForPlatform(
          baseDirectory: debugBase,
          platform: AppStoragePlatform.android,
          buildMode: AppBuildMode.debug,
        );
        final profile = StorageLayout.targetForPlatform(
          baseDirectory: profileBase,
          platform: AppStoragePlatform.android,
          buildMode: AppBuildMode.profile,
        );

        expect(release.rootDirectory.path, releaseBase.path);
        expect(debug.rootDirectory.path, debugBase.path);
        expect(profile.rootDirectory.path, profileBase.path);
        expect(
          release.sqliteDatabaseFile.path,
          '/data/user/0/com.bird.fluidtext/files/fluidtext_library.sqlite',
        );
        expect(
          release.appFontSettingsFile.path,
          '/data/user/0/com.bird.fluidtext/files/settings/app_font_settings.json',
        );
        expect(
          release.readerBackgroundsDirectory.path,
          '/data/user/0/com.bird.fluidtext/files/reader_backgrounds',
        );
      },
    );
  });

  test('legacy layout preserves current Documents and Support locations', () {
    final layout = StorageLayout.legacy(
      documentsDirectory: Directory(r'C:\Users\reader\Documents'),
      supportDirectory: Directory(r'C:\Users\reader\AppData\Roaming\FluidText'),
      pathSeparator: r'\',
    );

    expect(layout.usesLegacyRuntimeLocations, isTrue);
    expect(layout.libraryDatabaseDirectory.path, r'C:\Users\reader\Documents');
    expect(
      layout.bookRemarkDatabaseDirectory.path,
      r'C:\Users\reader\Documents',
    );
    expect(
      layout.appBehaviorSettingsFile.path,
      r'C:\Users\reader\Documents\app_behavior_settings.json',
    );
    expect(
      layout.readerSessionFile.path,
      r'C:\Users\reader\Documents\reader_session.json',
    );
    expect(
      layout.readerBackgroundSettingsFile.path,
      r'C:\Users\reader\Documents\reader_background.json',
    );
    expect(
      layout.bookAssetsDirectory.path,
      r'C:\Users\reader\Documents\book_assets',
    );
    expect(
      layout.appFontSettingsFile.path,
      r'C:\Users\reader\AppData\Roaming\FluidText\app_font_settings.json',
    );
    expect(
      layout.appFontsDirectory.path,
      r'C:\Users\reader\AppData\Roaming\FluidText\app_fonts',
    );
  });

  test('parses build mode names', () {
    expect(AppBuildMode.parse('debug'), AppBuildMode.debug);
    expect(AppBuildMode.parse('PROFILE'), AppBuildMode.profile);
    expect(AppBuildMode.parse(' release '), AppBuildMode.release);
    expect(() => AppBuildMode.parse('beta'), throwsFormatException);
  });

  group('StoragePathSafety', () {
    test('normalizes safe relative paths', () {
      final path = StoragePathSafety.parseRelativePath(
        r'book_assets\root\images\cover.png',
      );

      expect(path.asPosixPath(), 'book_assets/root/images/cover.png');
      expect(
        path.asPlatformPath(separator: r'\'),
        r'book_assets\root\images\cover.png',
      );
    });

    test('rejects absolute, traversal and control-character paths', () {
      for (final value in <String>[
        '',
        '../cover.png',
        'book_assets/../cover.png',
        '/tmp/cover.png',
        r'C:\tmp\cover.png',
        r'\\server\share\cover.png',
        'book_assets/root/\u0001.png',
        'book_assets//cover.png',
        'book_assets/./cover.png',
      ]) {
        expect(
          () => StoragePathSafety.parseRelativePath(value),
          throwsFormatException,
          reason: value,
        );
      }
    });
  });
}
