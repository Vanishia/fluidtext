import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../features/context/context_settings.dart';
import '../features/reader/reading_analysis_module.dart';
import '../features/reader/reading_order.dart';

class AppBehaviorSettings {
  const AppBehaviorSettings({
    this.themeMode = ThemeMode.system,
    this.readingOrder = ReadingOrder.random,
    this.showUnreadOnly = false,
    this.contextSettings = const ContextSettings(),
    this.analysisModuleOrder = defaultReadingAnalysisModuleOrder,
  });

  final ThemeMode themeMode;
  final ReadingOrder readingOrder;
  final bool showUnreadOnly;
  final ContextSettings contextSettings;
  final List<ReadingAnalysisModuleType> analysisModuleOrder;

  AppBehaviorSettings copyWith({
    ThemeMode? themeMode,
    ReadingOrder? readingOrder,
    bool? showUnreadOnly,
    ContextSettings? contextSettings,
    List<ReadingAnalysisModuleType>? analysisModuleOrder,
  }) {
    return AppBehaviorSettings(
      themeMode: themeMode ?? this.themeMode,
      readingOrder: readingOrder ?? this.readingOrder,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      contextSettings: contextSettings ?? this.contextSettings,
      analysisModuleOrder: analysisModuleOrder ?? this.analysisModuleOrder,
    );
  }
}

class AppBehaviorSettingsService {
  AppBehaviorSettingsService._();

  static final instance = AppBehaviorSettingsService._();
  static const _fileName = 'app_behavior_settings.json';

  Future<AppBehaviorSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return const AppBehaviorSettings();

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppBehaviorSettings(
        themeMode: _themeModeFromJson(json['themeMode']),
        readingOrder: _readingOrderFromJson(json['readingOrder']),
        showUnreadOnly: json['showUnreadOnly'] == true,
        contextSettings: ContextSettings(
          before: _contextCountFromJson(json['contextBefore']),
          after: _contextCountFromJson(json['contextAfter']),
        ),
        analysisModuleOrder: normalizeReadingAnalysisModuleOrder(
          json['analysisModuleOrder'] as List<dynamic>?,
        ),
      );
    } catch (_) {
      return const AppBehaviorSettings();
    }
  }

  Future<void> save(AppBehaviorSettings settings) async {
    final file = await _settingsFile();
    final payload = <String, Object?>{
      'themeMode': settings.themeMode.name,
      'readingOrder': settings.readingOrder.name,
      'showUnreadOnly': settings.showUnreadOnly,
      'contextBefore': settings.contextSettings.before,
      'contextAfter': settings.contextSettings.after,
      'analysisModuleOrder': settings.analysisModuleOrder
          .map((item) => item.name)
          .toList(growable: false),
      'savedAt': DateTime.now().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  ThemeMode _themeModeFromJson(Object? value) {
    if (value is! String) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  ReadingOrder _readingOrderFromJson(Object? value) {
    if (value is! String) return ReadingOrder.random;
    return ReadingOrder.values.firstWhere(
      (order) => order.name == value,
      orElse: () => ReadingOrder.random,
    );
  }

  int _contextCountFromJson(Object? value) {
    if (value is! num) return ContextSettings.defaultCount;
    return value.toInt().clamp(
      ContextSettings.minCount,
      ContextSettings.maxCount,
    );
  }
}
