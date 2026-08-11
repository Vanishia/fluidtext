import 'package:flutter/foundation.dart';

enum AppFontSource { system, custom }

@immutable
class AppFontSettings {
  const AppFontSettings({
    this.source = AppFontSource.system,
    this.fontFamily,
    this.displayName,
    this.fontPath,
  });

  const AppFontSettings.system()
    : source = AppFontSource.system,
      fontFamily = null,
      displayName = null,
      fontPath = null;

  final AppFontSource source;
  final String? fontFamily;
  final String? displayName;
  final String? fontPath;

  bool get usesCustomFont =>
      source == AppFontSource.custom &&
      fontFamily != null &&
      fontFamily!.isNotEmpty &&
      fontPath != null &&
      fontPath!.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.name,
      'fontFamily': fontFamily,
      'displayName': displayName,
      'fontPath': fontPath,
    };
  }

  factory AppFontSettings.fromJson(Map<String, dynamic> json) {
    final source = AppFontSource.values.firstWhere(
      (item) => item.name == json['source'],
      orElse: () => AppFontSource.system,
    );
    final fontFamily = json['fontFamily'];
    final displayName = json['displayName'];
    final fontPath = json['fontPath'];
    final settings = AppFontSettings(
      source: source,
      fontFamily: fontFamily is String ? fontFamily : null,
      displayName: displayName is String ? displayName : null,
      fontPath: fontPath is String ? fontPath : null,
    );
    return settings.usesCustomFont ? settings : const AppFontSettings.system();
  }
}
