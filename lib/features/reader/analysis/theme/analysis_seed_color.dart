import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../reader_background_settings.dart';

class AnalysisSeedColorResolver {
  const AnalysisSeedColorResolver._();

  static Future<Color> resolveSeedColor(
    ReaderBackgroundSettings settings,
  ) async {
    if (!settings.hasCustomImage) {
      return normalizeSeedColor(settings.palette.color);
    }

    final imagePath = settings.imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      return normalizeSeedColor(settings.palette.color);
    }

    final derived = await _extractSeedColorFromImage(imagePath);
    return normalizeSeedColor(derived ?? settings.palette.color);
  }

  static ThemeData buildPageTheme(ThemeData baseTheme, Color seedColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: baseTheme.brightness,
    );

    return baseTheme.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(
          alpha: baseTheme.brightness == Brightness.dark ? 0.64 : 0.84,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.45),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: scheme.surface.withValues(alpha: 0.24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static Future<Color?> _extractSeedColorFromImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      codec.dispose();
      if (byteData == null) return null;
      return _dominantColorFromRgba(byteData);
    } catch (_) {
      return null;
    }
  }

  static Color _dominantColorFromRgba(ByteData rgba) {
    final buckets = <int, _ColorBucket>{};
    for (var offset = 0; offset < rgba.lengthInBytes; offset += 4) {
      final red = rgba.getUint8(offset);
      final green = rgba.getUint8(offset + 1);
      final blue = rgba.getUint8(offset + 2);
      final alpha = rgba.getUint8(offset + 3);
      if (alpha < 180) continue;

      final color = Color.fromARGB(255, red, green, blue);
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness <= 0.06 || hsl.lightness >= 0.95) continue;

      final key = ((red ~/ 32) << 10) | ((green ~/ 32) << 5) | (blue ~/ 32);
      final weight =
          (0.35 + hsl.saturation) *
          (1 - (hsl.lightness - 0.52).abs()).clamp(0.15, 1.0);
      buckets
          .putIfAbsent(key, _ColorBucket.new)
          .add(red: red, green: green, blue: blue, weight: weight);
    }

    if (buckets.isEmpty) {
      return const Color(0xFF5F8AA6);
    }

    final bucket = buckets.values.reduce(
      (best, current) => current.weight > best.weight ? current : best,
    );
    return bucket.color;
  }

  static Color normalizeSeedColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.70))
        .withLightness(hsl.lightness.clamp(0.28, 0.64))
        .toColor();
  }
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

  Color get color {
    if (weight == 0) {
      return const Color(0xFF5F8AA6);
    }
    return Color.fromARGB(
      255,
      (_red / weight).round().clamp(0, 255),
      (_green / weight).round().clamp(0, 255),
      (_blue / weight).round().clamp(0, 255),
    );
  }
}
