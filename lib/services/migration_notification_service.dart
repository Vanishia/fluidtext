import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

/// Drives the Android foreground service (dataSync) shown while the one-shot
/// data migration or the pre-migration backup export is running. The
/// foreground priority keeps the process alive when the user switches away,
/// so the system does not kill the app mid-migration.
///
/// No-op on non-Android platforms; every call is best-effort and never
/// throws, because the migration itself must never fail because of the
/// notification. A kill stays safe either way (staging + state machine); the
/// service only makes it unlikely.
class MigrationNotificationService {
  MigrationNotificationService._();

  static final MigrationNotificationService instance =
      MigrationNotificationService._();

  static const _channel = MethodChannel('fluidtext/migration_service');

  static bool get _isSupported => !kIsWeb && Platform.isAndroid;

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns whether
  /// notifications can be shown. The foreground service itself runs even
  /// without the permission; the notification is just hidden.
  Future<bool> ensurePermission() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } catch (error, stackTrace) {
      _logFailure('ensurePermission', error, stackTrace);
      return false;
    }
  }

  /// Starts the foreground service with an ongoing notification.
  Future<void> start({required String title, required String text}) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('start', {
        'title': title,
        'text': text,
      });
    } catch (error, stackTrace) {
      _logFailure('start', error, stackTrace);
    }
  }

  /// Updates the ongoing notification. [percent] in 0..100 shows a
  /// determinate bar; null shows an indeterminate one.
  Future<void> updateProgress({
    required String title,
    required String text,
    int? percent,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'text': text,
        'percent': ?percent,
      });
    } catch (error, stackTrace) {
      _logFailure('updateProgress', error, stackTrace);
    }
  }

  /// Stops the foreground service and removes its notification.
  Future<void> stop() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error, stackTrace) {
      _logFailure('stop', error, stackTrace);
    }
  }

  void _logFailure(String method, Object error, StackTrace stackTrace) {
    AppLogger.instance.warning(
      'MigrationNotificationService',
      '$method failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
