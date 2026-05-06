import 'dart:async';

import 'package:flutter/material.dart';

import '../features/context/context_settings.dart';
import '../features/reader/reader_background_settings.dart';
import '../features/reader/reading_order.dart';
import '../services/app_behavior_settings_service.dart';
import '../services/reader_background_service.dart';

class AppSettingsViewModel {
  AppSettingsViewModel._();

  static final instance = AppSettingsViewModel._();

  final themeModeSetting = ValueNotifier(ThemeMode.system);
  final readingOrderSetting = ValueNotifier(ReadingOrder.random);
  final showUnreadOnlySetting = ValueNotifier(false);
  final contextSettingsSetting = ValueNotifier(const ContextSettings());
  final readerBackgroundSetting = ValueNotifier(const ReaderBackgroundSettings());

  Future<void> _saveQueue = Future.value();

  ThemeMode get themeMode => themeModeSetting.value;
  ReadingOrder get readingOrder => readingOrderSetting.value;
  bool get showUnreadOnly => showUnreadOnlySetting.value;
  ContextSettings get contextSettings => contextSettingsSetting.value;
  ReaderBackgroundSettings get readerBackground => readerBackgroundSetting.value;

  Future<void> init() async {
    final behaviorSettings = await AppBehaviorSettingsService.instance.load();
    themeModeSetting.value = behaviorSettings.themeMode;
    readingOrderSetting.value = behaviorSettings.readingOrder;
    showUnreadOnlySetting.value = behaviorSettings.showUnreadOnly;
    contextSettingsSetting.value = behaviorSettings.contextSettings;
    readerBackgroundSetting.value = await ReaderBackgroundService.instance.load();
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
    final next =
        await ReaderBackgroundService.instance.clearImportedImage(current);
    readerBackgroundSetting.value = next;
    await ReaderBackgroundService.instance.save(next);
    return next;
  }

  Future<void> saveReaderBackground(ReaderBackgroundSettings settings) async {
    readerBackgroundSetting.value = settings;
    await ReaderBackgroundService.instance.save(settings);
  }

  void _scheduleBehaviorSave() {
    final settings = AppBehaviorSettings(
      themeMode: themeModeSetting.value,
      readingOrder: readingOrderSetting.value,
      showUnreadOnly: showUnreadOnlySetting.value,
      contextSettings: contextSettingsSetting.value,
    );

    _saveQueue = _saveQueue
        .catchError((_) {})
        .then((_) => AppBehaviorSettingsService.instance.save(settings))
        .catchError((_) {});
    unawaited(_saveQueue);
  }
}
