import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

/// Drives the Android persistent notification shown while the FTS search
/// index is being backfilled (only happens once, after upgrading from a
/// pre-search app version). Mirrors [ImportNotificationService]: no-op on
/// non-Android platforms, every call best-effort and never throws.
class SearchIndexNotificationService {
  SearchIndexNotificationService._();

  static final SearchIndexNotificationService instance =
      SearchIndexNotificationService._();

  /// Same MethodChannel as the import notification; the native side picks
  /// the notification by this id.
  static const _channel = MethodChannel('fluidtext/import_notifications');
  static const _notificationId = 4202;

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

  /// Shows (or updates) the ongoing indexing notification. [percent] in
  /// 0..100 shows a determinate bar; null shows an indeterminate one.
  Future<void> showProgress({
    required String title,
    required String text,
    int? percent,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('showProgress', {
        'id': _notificationId,
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
      await _channel.invokeMethod<void>('showCompleted', {
        'id': _notificationId,
        'text': text,
      });
    } catch (error, stackTrace) {
      _logFailure('showCompleted', error, stackTrace);
    }
  }

  Future<void> cancel() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': _notificationId});
    } catch (error, stackTrace) {
      _logFailure('cancel', error, stackTrace);
    }
  }

  void _logFailure(String method, Object error, StackTrace stackTrace) {
    AppLogger.instance.warning(
      'SearchIndexNotificationService',
      '$method failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
