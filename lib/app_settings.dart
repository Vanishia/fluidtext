import 'dart:async';

import 'package:flutter/material.dart';

import 'features/context/context_settings.dart';
import 'features/reader/reader_background_settings.dart';
import 'features/reader/reading_order.dart';
import 'services/app_behavior_settings_service.dart';
import 'services/reader_background_service.dart';

final themeModeSetting = ValueNotifier(ThemeMode.system);
final readingOrderSetting = ValueNotifier(ReadingOrder.random);
final showUnreadOnlySetting = ValueNotifier(false);
final contextSettingsSetting = ValueNotifier(const ContextSettings());
final readerBackgroundSetting = ValueNotifier(const ReaderBackgroundSettings());
Future<void> _behaviorSettingsSaveQueue = Future.value();

Future<void> initializeAppSettings() async {
  final behaviorSettings = await AppBehaviorSettingsService.instance.load();
  themeModeSetting.value = behaviorSettings.themeMode;
  readingOrderSetting.value = behaviorSettings.readingOrder;
  showUnreadOnlySetting.value = behaviorSettings.showUnreadOnly;
  contextSettingsSetting.value = behaviorSettings.contextSettings;
  readerBackgroundSetting.value = await ReaderBackgroundService.instance.load();
}

void saveThemeModeSetting(ThemeMode mode) {
  themeModeSetting.value = mode;
  _scheduleBehaviorSettingsSave();
}

void saveReadingOrderSetting(ReadingOrder order) {
  readingOrderSetting.value = order;
  _scheduleBehaviorSettingsSave();
}

void saveShowUnreadOnlySetting(bool value) {
  showUnreadOnlySetting.value = value;
  _scheduleBehaviorSettingsSave();
}

void saveContextSettingsSetting(ContextSettings settings) {
  contextSettingsSetting.value = settings;
  _scheduleBehaviorSettingsSave();
}

void _scheduleBehaviorSettingsSave() {
  final settings = AppBehaviorSettings(
    themeMode: themeModeSetting.value,
    readingOrder: readingOrderSetting.value,
    showUnreadOnly: showUnreadOnlySetting.value,
    contextSettings: contextSettingsSetting.value,
  );

  _behaviorSettingsSaveQueue = _behaviorSettingsSaveQueue
      .catchError((_) {})
      .then((_) => AppBehaviorSettingsService.instance.save(settings))
      .catchError((_) {});
  unawaited(_behaviorSettingsSaveQueue);
}

Future<void> saveReaderBackgroundSettings(
  ReaderBackgroundSettings settings,
) async {
  readerBackgroundSetting.value = settings;
  await ReaderBackgroundService.instance.save(settings);
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
