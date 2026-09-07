import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/context/context_settings.dart';
import '../features/reader/reading_analysis_module.dart';
import '../features/reader/reading_order.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';

class AppBehaviorSettings {
  static const minReaderFontScale = 0.8;
  static const maxReaderFontScale = 1.6;
  static const defaultReaderFontScale = 1.0;
  static const minReaderLineHeight = 1.2;
  static const maxReaderLineHeight = 1.8;
  static const defaultReaderLineHeight = 1.5;

  const AppBehaviorSettings({
    this.themeMode = ThemeMode.system,
    this.readingOrder = ReadingOrder.random,
    this.showUnreadOnly = false,
    this.contextSettings = const ContextSettings(),
    this.analysisModuleOrder = defaultReadingAnalysisModuleOrder,
    this.showPageTurnButtons = true,
    this.readerFontScale = defaultReaderFontScale,
    this.readerLineHeight = defaultReaderLineHeight,
    this.showUpdateNotification = true,
  });

  final ThemeMode themeMode;
  final ReadingOrder readingOrder;
  final bool showUnreadOnly;
  final ContextSettings contextSettings;
  final List<ReadingAnalysisModuleType> analysisModuleOrder;
  final bool showPageTurnButtons;

  /// 阅读卡片字号缩放（1.0 = 100%）。
  final double readerFontScale;

  /// 阅读卡片行距倍数。
  final double readerLineHeight;

  /// 发现新版本时是否在侧边栏显示更新通知。
  final bool showUpdateNotification;

  AppBehaviorSettings copyWith({
    ThemeMode? themeMode,
    ReadingOrder? readingOrder,
    bool? showUnreadOnly,
    ContextSettings? contextSettings,
    List<ReadingAnalysisModuleType>? analysisModuleOrder,
    bool? showPageTurnButtons,
    double? readerFontScale,
    double? readerLineHeight,
    bool? showUpdateNotification,
  }) {
    return AppBehaviorSettings(
      themeMode: themeMode ?? this.themeMode,
      readingOrder: readingOrder ?? this.readingOrder,
      showUnreadOnly: showUnreadOnly ?? this.showUnreadOnly,
      contextSettings: contextSettings ?? this.contextSettings,
      analysisModuleOrder: analysisModuleOrder ?? this.analysisModuleOrder,
      showPageTurnButtons: showPageTurnButtons ?? this.showPageTurnButtons,
      readerFontScale: readerFontScale ?? this.readerFontScale,
      readerLineHeight: readerLineHeight ?? this.readerLineHeight,
      showUpdateNotification:
          showUpdateNotification ?? this.showUpdateNotification,
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
        readerFontScale: _readerFontScaleFromJson(json['readerFontScale']),
        readerLineHeight: _readerLineHeightFromJson(json['readerLineHeight']),
        showUpdateNotification: json['showUpdateNotification'] != false,
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
      'readerFontScale': settings.readerFontScale,
      'readerLineHeight': settings.readerLineHeight,
      'showUpdateNotification': settings.showUpdateNotification,
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

  double _readerFontScaleFromJson(Object? value) {
    if (value is! num) return AppBehaviorSettings.defaultReaderFontScale;
    return value.toDouble().clamp(
      AppBehaviorSettings.minReaderFontScale,
      AppBehaviorSettings.maxReaderFontScale,
    );
  }

  double _readerLineHeightFromJson(Object? value) {
    if (value is! num) return AppBehaviorSettings.defaultReaderLineHeight;
    return value.toDouble().clamp(
      AppBehaviorSettings.minReaderLineHeight,
      AppBehaviorSettings.maxReaderLineHeight,
    );
  }
}
