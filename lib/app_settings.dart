import 'package:flutter/material.dart';

import 'features/context/context_settings.dart';
import 'features/reader/reading_analysis_module.dart';
import 'features/reader/reader_background_settings.dart';
import 'features/reader/reading_order.dart';
import 'features/settings/app_font_settings.dart';
import 'viewmodels/app_settings_viewmodel.dart';

final _vm = AppSettingsViewModel.instance;

final themeModeSetting = _vm.themeModeSetting;
final readingOrderSetting = _vm.readingOrderSetting;
final showUnreadOnlySetting = _vm.showUnreadOnlySetting;
final contextSettingsSetting = _vm.contextSettingsSetting;
final readerBackgroundSetting = _vm.readerBackgroundSetting;
final appFontSetting = _vm.appFontSetting;
final analysisModuleOrderSetting = _vm.analysisModuleOrderSetting;
final showPageTurnButtonsSetting = _vm.showPageTurnButtonsSetting;
final readerFontScaleSetting = _vm.readerFontScaleSetting;
final readerLineHeightSetting = _vm.readerLineHeightSetting;

Future<void> initializeAppSettings() => _vm.init();

void saveThemeModeSetting(ThemeMode mode) => _vm.setThemeMode(mode);

void saveReadingOrderSetting(ReadingOrder order) => _vm.setReadingOrder(order);

void saveShowUnreadOnlySetting(bool value) => _vm.setShowUnreadOnly(value);

void saveContextSettingsSetting(ContextSettings settings) =>
    _vm.setContextSettings(settings);

void saveAnalysisModuleOrderSetting(List<ReadingAnalysisModuleType> order) =>
    _vm.setAnalysisModuleOrder(order);

void saveShowPageTurnButtonsSetting(bool value) =>
    _vm.setShowPageTurnButtons(value);

void saveReaderFontScaleSetting(double value) => _vm.setReaderFontScale(value);

void saveReaderLineHeightSetting(double value) =>
    _vm.setReaderLineHeight(value);

Future<void> saveReaderBackgroundSettings(ReaderBackgroundSettings settings) =>
    _vm.saveReaderBackground(settings);

Future<ReaderBackgroundSettings?> importReaderBackgroundImage(
  ReaderBackgroundSettings current,
) => _vm.importReaderBackgroundImage(current);

Future<ReaderBackgroundSettings> clearReaderBackgroundImage(
  ReaderBackgroundSettings current,
) => _vm.clearReaderBackgroundImage(current);

Future<AppFontSettings?> importAppFont() => _vm.importAppFont();

Future<AppFontSettings> useSystemFont() => _vm.useSystemFont();
