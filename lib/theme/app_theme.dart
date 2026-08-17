import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/reader/reader_background_settings.dart';

class AppThemeSeedResolver {
  const AppThemeSeedResolver._();

  static Future<Color> resolve(ReaderBackgroundSettings settings) async {
    final fallback = normalize(settings.palette.color);
    if (!settings.hasCustomImage) return fallback;

    final imagePath = settings.imagePath;
    if (imagePath == null || imagePath.isEmpty) return fallback;

    final derived = await _extractFromImage(imagePath);
    return derived == null ? fallback : normalize(derived);
  }

  static Color normalize(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.70))
        .withLightness(hsl.lightness.clamp(0.28, 0.64))
        .toColor();
  }

  static Future<Color?> _extractFromImage(String imagePath) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      return _dominantColorFromRgba(byteData);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Color? _dominantColorFromRgba(ByteData rgba) {
    final buckets = <int, _ColorBucket>{};
    for (var offset = 0; offset < rgba.lengthInBytes; offset += 4) {
      final red = rgba.getUint8(offset);
      final green = rgba.getUint8(offset + 1);
      final blue = rgba.getUint8(offset + 2);
      final alpha = rgba.getUint8(offset + 3);
      if (alpha < 180) continue;

      final hsl = HSLColor.fromColor(Color.fromARGB(255, red, green, blue));
      if (hsl.lightness <= 0.06 || hsl.lightness >= 0.95) continue;

      final key = ((red ~/ 32) << 10) | ((green ~/ 32) << 5) | (blue ~/ 32);
      final weight =
          (0.35 + hsl.saturation) *
          (1 - (hsl.lightness - 0.52).abs()).clamp(0.15, 1.0);
      buckets
          .putIfAbsent(key, _ColorBucket.new)
          .add(red: red, green: green, blue: blue, weight: weight);
    }

    if (buckets.isEmpty) return null;
    return buckets.values
        .reduce(
          (best, current) => current.weight > best.weight ? current : best,
        )
        .color;
  }
}

/// System bar style shared by the normal and migration app trees: transparent
/// status and navigation bars so the page background shows through.
SystemUiOverlayStyle systemUiOverlayStyleForTheme(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
}

ThemeData buildAppTheme({
  required Brightness brightness,
  required Color seedColor,
  String? fontFamily,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: scheme.surface,
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
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.56),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class _ColorBucket {
  double _red = 0;
  double _green = 0;
  double _blue = 0;
  double weight = 0;

  void add({
    required int red,
    required int green,
    required int blue,
    required double weight,
  }) {
    _red += red * weight;
    _green += green * weight;
    _blue += blue * weight;
    this.weight += weight;
  }

  Color get color => Color.fromARGB(
    255,
    (_red / weight).round().clamp(0, 255),
    (_green / weight).round().clamp(0, 255),
    (_blue / weight).round().clamp(0, 255),
  );
}
