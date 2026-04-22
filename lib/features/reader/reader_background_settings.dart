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
  });

  final String key;
  final String label;
  final Color color;
}

const readerBackgroundPalettes = <ReaderBackgroundPalette>[
  ReaderBackgroundPalette(
    key: 'warmPaper',
    label: '暖白',
    color: Color(0xFFF6F0E5),
  ),
  ReaderBackgroundPalette(key: 'rice', label: '米杏', color: Color(0xFFF1E6D0)),
  ReaderBackgroundPalette(key: 'mist', label: '雾蓝', color: Color(0xFFE5EEF5)),
  ReaderBackgroundPalette(key: 'sage', label: '浅绿', color: Color(0xFFE3EBDD)),
  ReaderBackgroundPalette(key: 'slate', label: '青灰', color: Color(0xFFDCE2E6)),
  ReaderBackgroundPalette(key: 'ink', label: '夜墨', color: Color(0xFF1E232B)),
];

@immutable
class ReaderBackgroundSettings {
  const ReaderBackgroundSettings({
    this.source = ReaderBackgroundSource.color,
    this.paletteKey = 'warmPaper',
    this.texture = ReaderTexturePreset.none,
    this.imagePath,
  });

  final ReaderBackgroundSource source;
  final String paletteKey;
  final ReaderTexturePreset texture;
  final String? imagePath;

  ReaderBackgroundPalette get palette => readerBackgroundPalettes.firstWhere(
    (item) => item.key == paletteKey,
    orElse: () => readerBackgroundPalettes.first,
  );

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
      paletteKey: paletteKey is String ? paletteKey : 'warmPaper',
      texture: ReaderTexturePreset.values.firstWhere(
        (item) => item.name == textureName,
        orElse: () => ReaderTexturePreset.none,
      ),
      imagePath: imagePath is String && imagePath.isNotEmpty ? imagePath : null,
    );
  }
}
