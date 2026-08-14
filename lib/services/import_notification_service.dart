import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

/// Drives the Android persistent notification shown while an EPUB import is
/// running. No-op on non-Android platforms; every call is best-effort and
/// never throws, because the notification is a nicety, not a requirement.
class ImportNotificationService {
  ImportNotificationService._();

  static final ImportNotificationService instance =
      ImportNotificationService._();

  static const _channel = MethodChannel('fluidtext/import_notifications');

  static bool get _isSupported => !kIsWeb && Platform.isAndroid;

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns whether
  /// notifications can be shown.
  Future<bool> ensurePermission() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } catch (error, stackTrace) {
      _logFailure('ensurePermission', error, stackTrace);
      return false;
    }
  }

  /// Shows (or updates) the ongoing import notification. [percent] in
  /// 0..100 shows a determinate bar; null shows an indeterminate one.
  Future<void> showProgress({
    required String title,
    required String text,
    int? percent,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('showProgress', {
        'title': title,
        'text': text,
        'percent': ?percent,
      });
    } catch (error, stackTrace) {
      _logFailure('showProgress', error, stackTrace);
    }
  }

  /// Turns the notification into a dismissible "done" one.
  Future<void> showCompleted({required String text}) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('showCompleted', {'text': text});
    } catch (error, stackTrace) {
      _logFailure('showCompleted', error, stackTrace);
    }
  }

  Future<void> cancel() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (error, stackTrace) {
      _logFailure('cancel', error, stackTrace);
    }
  }

  void _logFailure(String method, Object error, StackTrace stackTrace) {
    AppLogger.instance.warning(
      'ImportNotificationService',
      '$method failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
