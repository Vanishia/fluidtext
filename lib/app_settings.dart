import 'package:flutter/material.dart';

import 'features/reader/reader_background_settings.dart';
import 'features/reader/reading_order.dart';
import 'services/reader_background_service.dart';

final themeModeSetting = ValueNotifier(ThemeMode.system);
final readingOrderSetting = ValueNotifier(ReadingOrder.sequential);
final readerBackgroundSetting = ValueNotifier(const ReaderBackgroundSettings());

Future<void> initializeAppSettings() async {
  readerBackgroundSetting.value = await ReaderBackgroundService.instance.load();
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
