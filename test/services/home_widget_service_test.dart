import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fluidtext/home_widget_test');
  final messenger = binding.defaultBinaryMessenger;
  late HomeWidgetService service;
  Map<String, Object>? pending;
  late List<MethodCall> calls;

  Map<String, Object> request(int id, {String content = '三行以外还有上下文'}) => {
    'cardId': id,
    'bookId': 7,
    'contentHash': sha256.convert(utf8.encode(content)).toString(),
  };

  Future<void> notifyCard() async {
    final done = Completer<void>();
    binding.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('cardAvailable'),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    pending = null;
    calls = [];
    service = HomeWidgetService(channel: channel, supported: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'takePendingCard') {
        final value = pending;
        pending = null;
        return value;
      }
      if (call.method == 'requestPin') return true;
      return null;
    });
  });

  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('冷启动保留点击目标，消费一次后不会再次打开', () async {
    pending = request(42);
    await service.initialize('/private/library.sqlite');
    expect(service.hasPendingCard, isTrue);
    expect(service.takePendingCard()!.cardId, 42);
    expect(service.takePendingCard(), isNull);
    expect(calls.first.arguments, {'databasePath': '/private/library.sqlite'});
  });

  test('应用已打开时接收新点击，连续点击保留最后一张', () async {
    await service.initialize('/private/library.sqlite');
    pending = request(11);
    await notifyCard();
    pending = request(22);
    await notifyCard();
    expect(service.takePendingCard()!.cardId, 22);
  });

  test('备份恢复复用 ID 时必须同时验证书籍和内容', () {
    final target = HomeWidgetCardRequest.fromMap(request(42))!;
    final card = BookCard()
      ..id = 42
      ..bookId = 7
      ..content = '三行以外还有上下文';
    expect(target.matches(card), isTrue);
    card.content = '恢复后相同 ID 的另一段文字';
    expect(target.matches(card), isFalse);
    card.content = '三行以外还有上下文';
    card.bookId = 8;
    expect(target.matches(card), isFalse);
  });

  test('忽略无效入口参数，避免打开不确定的目标', () async {
    await service.initialize('/private/library.sqlite');
    pending = {'cardId': -1, 'bookId': 7, 'contentHash': 'invalid'};
    await notifyCard();
    expect(service.hasPendingCard, isFalse);
  });

  test('桌面端不调用 Android 平台通道', () async {
    final desktop = HomeWidgetService(channel: channel, supported: false);
    await desktop.initialize('/desktop/library.sqlite');
    await desktop.refresh();
    expect(await desktop.requestPin(), isFalse);
    expect(calls, isEmpty);
    desktop.dispose();
  });
}
