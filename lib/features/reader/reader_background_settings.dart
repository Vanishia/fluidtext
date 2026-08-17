import 'package:flutter/material.dart';

enum ReaderBackgroundSource { color, image }

enum ReaderTexturePreset { none, fiber, dots, diagonal }

extension ReaderTexturePresetX on ReaderTexturePreset {
  String get label {
    switch (this) {
      case ReaderTexturePreset.none:
        return '无纹理';
      case ReaderTexturePreset.fiber:
        return '纸纹';
      case ReaderTexturePreset.dots:
        return '点阵';
      case ReaderTexturePreset.diagonal:
        return '斜纹';
    }
  }
}

@immutable
class ReaderBackgroundPalette {
  const ReaderBackgroundPalette({
    required this.key,
    required this.label,
    required this.color,
    this.darkLabel,
    this.darkColor,
  });

  final String key;
  final String label;
  final Color color;

  /// 夜间模式下的对应深色；为空时日夜间同色（如夜墨）。
  final String? darkLabel;
  final Color? darkColor;

  Color colorFor(Brightness brightness) {
    return brightness == Brightness.dark ? (darkColor ?? color) : color;
  }

  String labelFor(Brightness brightness) {
    return brightness == Brightness.dark ? (darkLabel ?? label) : label;
  }
}

const readerBackgroundPalettes = <ReaderBackgroundPalette>[
  ReaderBackgroundPalette(
    key: 'warmPaper',
    label: '暖白',
    color: Color(0xFFF6F0E5),
    darkLabel: '暖灰',
    darkColor: Color(0xFF292420),
  ),
  ReaderBackgroundPalette(
    key: 'rice',
    label: '米杏',
    color: Color(0xFFF1E6D0),
    darkLabel: '深棕',
    darkColor: Color(0xFF2B2419),
  ),
  ReaderBackgroundPalette(
    key: 'mist',
    label: '雾蓝',
    color: Color(0xFFE5EEF5),
    darkLabel: '夜雾',
    darkColor: Color(0xFF202B36),
  ),
  ReaderBackgroundPalette(
    key: 'sage',
    label: '浅绿',
    color: Color(0xFFE3EBDD),
    darkLabel: '苔夜',
    darkColor: Color(0xFF222A20),
  ),
  ReaderBackgroundPalette(
    key: 'slate',
    label: '青灰',
    color: Color(0xFFDCE2E6),
    darkLabel: '深灰',
    darkColor: Color(0xFF25292E),
  ),
  ReaderBackgroundPalette(key: 'ink', label: '夜墨', color: Color(0xFF1E232B)),
];

/// 未选择壁纸时的默认背景色（浅蓝）。
const defaultReaderBackgroundPaletteKey = 'mist';

@immutable
class ReaderBackgroundSettings {
  const ReaderBackgroundSettings({
    this.source = ReaderBackgroundSource.color,
    this.paletteKey = defaultReaderBackgroundPaletteKey,
    this.texture = ReaderTexturePreset.none,
    this.imagePath,
  });

  final ReaderBackgroundSource source;
  final String paletteKey;
  final ReaderTexturePreset texture;
  final String? imagePath;

  ReaderBackgroundPalette get palette => readerBackgroundPalettes.firstWhere(
    (item) => item.key == paletteKey,
    orElse: () => readerBackgroundPalettes.firstWhere(
      (item) => item.key == defaultReaderBackgroundPaletteKey,
    ),
  );

  /// 纯色背景随日夜间模式取对应颜色。
  Color backgroundColor(Brightness brightness) => palette.colorFor(brightness);

  bool get hasCustomImage =>
      source == ReaderBackgroundSource.image &&
      imagePath != null &&
      imagePath!.isNotEmpty;

  ReaderBackgroundSettings copyWith({
    ReaderBackgroundSource? source,
    String? paletteKey,
    ReaderTexturePreset? texture,
    String? imagePath,
    bool clearImagePath = false,
  }) {
    return ReaderBackgroundSettings(
      source: source ?? this.source,
      paletteKey: paletteKey ?? this.paletteKey,
      texture: texture ?? this.texture,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.name,
      'paletteKey': paletteKey,
      'texture': texture.name,
      'imagePath': imagePath,
    };
  }

  factory ReaderBackgroundSettings.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'];
    final paletteKey = json['paletteKey'];
    final textureName = json['texture'];
    final imagePath = json['imagePath'];
    return ReaderBackgroundSettings(
      source: ReaderBackgroundSource.values.firstWhere(
        (item) => item.name == sourceName,
        orElse: () => ReaderBackgroundSource.color,
      ),
      paletteKey: paletteKey is String
          ? paletteKey
          : defaultReaderBackgroundPaletteKey,
      texture: ReaderTexturePreset.values.firstWhere(
        (item) => item.name == textureName,
        orElse: () => ReaderTexturePreset.none,
      ),
      imagePath: imagePath is String && imagePath.isNotEmpty ? imagePath : null,
    );
  }
}
