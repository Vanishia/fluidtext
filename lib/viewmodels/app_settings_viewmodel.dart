import 'dart:async';

import 'package:flutter/material.dart';

import '../features/context/context_settings.dart';
import '../features/reader/reading_analysis_module.dart';
import '../features/reader/reader_background_settings.dart';
import '../features/reader/reading_order.dart';
import '../features/settings/app_font_settings.dart';
import '../services/app_behavior_settings_service.dart';
import '../services/app_font_service.dart';
import '../services/reader_background_service.dart';

class AppSettingsViewModel {
  AppSettingsViewModel._();

  static final instance = AppSettingsViewModel._();

  final themeModeSetting = ValueNotifier(ThemeMode.system);
  final readingOrderSetting = ValueNotifier(ReadingOrder.random);
  final showUnreadOnlySetting = ValueNotifier(false);
  final contextSettingsSetting = ValueNotifier(const ContextSettings());
  final readerBackgroundSetting = ValueNotifier(
    const ReaderBackgroundSettings(),
  );
  final appFontSetting = ValueNotifier(const AppFontSettings.system());
  final analysisModuleOrderSetting =
      ValueNotifier<List<ReadingAnalysisModuleType>>(
        defaultReadingAnalysisModuleOrder,
      );
  final showPageTurnButtonsSetting = ValueNotifier(true);
  final showUpdateNotificationSetting = ValueNotifier(true);
  final readerFontScaleSetting = ValueNotifier(
    AppBehaviorSettings.defaultReaderFontScale,
  );
  final readerLineHeightSetting = ValueNotifier(
    AppBehaviorSettings.defaultReaderLineHeight,
  );

  Future<void> _saveQueue = Future.value();

  ThemeMode get themeMode => themeModeSetting.value;
  ReadingOrder get readingOrder => readingOrderSetting.value;
  bool get showUnreadOnly => showUnreadOnlySetting.value;
  ContextSettings get contextSettings => contextSettingsSetting.value;
  ReaderBackgroundSettings get readerBackground =>
      readerBackgroundSetting.value;
  AppFontSettings get appFont => appFontSetting.value;
  List<ReadingAnalysisModuleType> get analysisModuleOrder =>
      analysisModuleOrderSetting.value;
  bool get showPageTurnButtons => showPageTurnButtonsSetting.value;
  bool get showUpdateNotification => showUpdateNotificationSetting.value;
  double get readerFontScale => readerFontScaleSetting.value;
  double get readerLineHeight => readerLineHeightSetting.value;

  Future<void> init() async {
    final fontFuture = AppFontService.instance.load();
    final backgroundFuture = ReaderBackgroundService.instance.load();
    final behaviorSettings = await AppBehaviorSettingsService.instance.load();
    themeModeSetting.value = behaviorSettings.themeMode;
    readingOrderSetting.value = behaviorSettings.readingOrder;
    showUnreadOnlySetting.value = behaviorSettings.showUnreadOnly;
    contextSettingsSetting.value = behaviorSettings.contextSettings;
    analysisModuleOrderSetting.value = List<ReadingAnalysisModuleType>.from(
      behaviorSettings.analysisModuleOrder,
    );
    showPageTurnButtonsSetting.value = behaviorSettings.showPageTurnButtons;
    showUpdateNotificationSetting.value =
        behaviorSettings.showUpdateNotification;
    readerFontScaleSetting.value = behaviorSettings.readerFontScale;
    readerLineHeightSetting.value = behaviorSettings.readerLineHeight;
    readerBackgroundSetting.value = await backgroundFuture;
    appFontSetting.value = await fontFuture;
  }

  void setThemeMode(ThemeMode mode) {
    themeModeSetting.value = mode;
    _scheduleBehaviorSave();
  }

  void setReadingOrder(ReadingOrder order) {
    readingOrderSetting.value = order;
    _scheduleBehaviorSave();
  }

  void setShowUnreadOnly(bool value) {
    showUnreadOnlySetting.value = value;
    _scheduleBehaviorSave();
  }

  void setContextSettings(ContextSettings settings) {
    contextSettingsSetting.value = settings;
    _scheduleBehaviorSave();
  }

  void setAnalysisModuleOrder(List<ReadingAnalysisModuleType> order) {
    analysisModuleOrderSetting.value =
        List<ReadingAnalysisModuleType>.unmodifiable(
          normalizeReadingAnalysisModuleOrder(order),
        );
    _scheduleBehaviorSave();
  }

  void setShowPageTurnButtons(bool value) {
    showPageTurnButtonsSetting.value = value;
    _scheduleBehaviorSave();
  }

  void setShowUpdateNotification(bool value) {
    showUpdateNotificationSetting.value = value;
    _scheduleBehaviorSave();
  }

  void setReaderFontScale(double value) {
    readerFontScaleSetting.value = value.clamp(
      AppBehaviorSettings.minReaderFontScale,
      AppBehaviorSettings.maxReaderFontScale,
    );
    _scheduleBehaviorSave();
  }

  void setReaderLineHeight(double value) {
    readerLineHeightSetting.value = value.clamp(
      AppBehaviorSettings.minReaderLineHeight,
      AppBehaviorSettings.maxReaderLineHeight,
    );
    _scheduleBehaviorSave();
  }

  Future<ReaderBackgroundSettings?> importReaderBackgroundImage(
    ReaderBackgroundSettings current,
  ) async {
    final next = await ReaderBackgroundService.instance.importImage(current);
    if (next == null) return null;
    readerBackgroundSetting.value = next;
    await ReaderBackgroundService.instance.save(next);
    return next;
  }

  Future<ReaderBackgroundSettings> clearReaderBackgroundImage(
    ReaderBackgroundSettings current,
  ) async {
    final next = await ReaderBackgroundService.instance.clearImportedImage(
      current,
    );
    readerBackgroundSetting.value = next;
    await ReaderBackgroundService.instance.save(next);
    return next;
  }

  Future<void> saveReaderBackground(ReaderBackgroundSettings settings) async {
    readerBackgroundSetting.value = settings;
    await ReaderBackgroundService.instance.save(settings);
  }

  Future<AppFontSettings?> importAppFont() async {
    final next = await AppFontService.instance.importFont(appFontSetting.value);
    if (next == null) return null;
    appFontSetting.value = next;
    return next;
  }

  Future<AppFontSettings> useSystemFont() async {
    final next = await AppFontService.instance.useSystemFont(
      appFontSetting.value,
    );
    appFontSetting.value = next;
    return next;
  }

  void _scheduleBehaviorSave() {
    final settings = AppBehaviorSettings(
      themeMode: themeModeSetting.value,
      readingOrder: readingOrderSetting.value,
      showUnreadOnly: showUnreadOnlySetting.value,
      contextSettings: contextSettingsSetting.value,
      analysisModuleOrder: analysisModuleOrderSetting.value,
      showPageTurnButtons: showPageTurnButtonsSetting.value,
      showUpdateNotification: showUpdateNotificationSetting.value,
      readerFontScale: readerFontScaleSetting.value,
      readerLineHeight: readerLineHeightSetting.value,
    );

    _saveQueue = _saveQueue
        .catchError((_) {})
        .then((_) => AppBehaviorSettingsService.instance.save(settings))
        .catchError((_) {});
    unawaited(_saveQueue);
  }
}
