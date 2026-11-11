import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/book_card.dart';
import 'app_logger.dart';

/// The identity of the card actually rendered by the Android launcher.
/// Its hash prevents an old widget from opening unrelated restored data
/// when a backup reuses the same numeric IDs.
class HomeWidgetCardRequest {
  const HomeWidgetCardRequest({
    required this.cardId,
    required this.bookId,
    required this.contentHash,
  });

  final int cardId;
  final int bookId;
  final String contentHash;

  bool matches(BookCard card) =>
      card.id == cardId &&
      card.bookId == bookId &&
      sha256.convert(utf8.encode(card.content)).toString() == contentHash;

  static HomeWidgetCardRequest? fromMap(Map<dynamic, dynamic> value) {
    final id = value['cardId'];
    final book = value['bookId'];
    final hash = value['contentHash'];
    if (id is! int ||
        id <= 0 ||
        book is! int ||
        book <= 0 ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      return null;
    }
    return HomeWidgetCardRequest(cardId: id, bookId: book, contentHash: hash);
  }
}

class HomeWidgetService extends ChangeNotifier with WidgetsBindingObserver {
  HomeWidgetService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('fluidtext/home_widget'),
      supported = supported ?? (!kIsWeb && Platform.isAndroid);

  static final instance = HomeWidgetService();
  final MethodChannel _channel;
  final bool supported;
  HomeWidgetCardRequest? _pending;
  bool _started = false;

  bool get hasPendingCard => _pending != null;

  HomeWidgetCardRequest? takePendingCard() {
    final request = _pending;
    _pending = null;
    return request;
  }

  Future<void> initialize(String databasePath) async {
    if (!supported) return;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'cardAvailable') await _collectPending();
      });
    }
    try {
      await _channel.invokeMethod<void>('initialize', {
        'databasePath': databasePath,
      });
      await _collectPending();
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'HomeWidget',
        'Widget initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _collectPending() async {
    final value = await _channel.invokeMapMethod<dynamic, dynamic>(
      'takePendingCard',
    );
    if (value == null) return;
    final request = HomeWidgetCardRequest.fromMap(value);
    if (request == null) return;
    // Repeated taps while the app boots should open the latest requested card.
    _pending = request;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!supported || !_started) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'HomeWidget',
        'Widget refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> requestPin() async =>
      supported && (await _channel.invokeMethod<bool>('requestPin') ?? false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) refresh();
  }

  @override
  void dispose() {
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
