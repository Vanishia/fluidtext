import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/context/context_settings.dart';
import '../features/reader/reading_analysis_module.dart';
import '../features/reader/reading_order.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';

class AppBehaviorSettings {
  const AppBehaviorSettings({
    this.themeMode = ThemeMode.system,
    this.readingOrder = ReadingOrder.random,
    this.showUnreadOnly = false,
    this.contextSettings = const ContextSettings(),
    this.analysisModuleOrder = defaultReadingAnalysisModuleOrder,
    this.showPageTurnButtons = true,
  });

  final ThemeMode themeMode;
  final ReadingOrder readingOrder;
  final bool showUnreadOnly;
  final ContextSettings contextSettings;
  final List<ReadingAnalysisModuleType> analysisModuleOrder;
  final bool showPageTurnButtons;

  AppBehaviorSettings copyWith({
    ThemeMode? themeMode,
    ReadingOrder? readingOrder,
    bool? showUnreadOnly,
    ContextSettings? contextSettings,
    List<ReadingAnalysisModuleType>? analysisModuleOrder,
    bool? showPageTurnButtons,
  }) {
    return AppBehaviorSettings(
      themeMode: themeMode ?? this.themeMode,
      readingOrder: readingOrder ?? this.readingOrder,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      contextSettings: contextSettings ?? this.contextSettings,
      analysisModuleOrder: analysisModuleOrder ?? this.analysisModuleOrder,
      showPageTurnButtons: showPageTurnButtons ?? this.showPageTurnButtons,
    );
  }
}

class AppBehaviorSettingsService {
  AppBehaviorSettingsService({StorageLayoutProvider? storageLayout})
    : _storageLayout = storageLayout ?? AppStorageResolver.activeRuntimeLayout;

  static final instance = AppBehaviorSettingsService();

  final StorageLayoutProvider _storageLayout;

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
        showPageTurnButtons: json['showPageTurnButtons'] != false,
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
      'showPageTurnButtons': settings.showPageTurnButtons,
      'savedAt': DateTime.now().toIso8601String(),
    };
    await JsonFileStore.writeAtomic(file, payload);
  }

  Future<File> _settingsFile() async {
    return (await _storageLayout()).appBehaviorSettingsFile;
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
