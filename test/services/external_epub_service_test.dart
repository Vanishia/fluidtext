import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/book_import_service.dart';
import 'package:fluidtext/services/external_epub_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fluidtext/external_epub_test');
  final messenger = binding.defaultBinaryMessenger;
  late ExternalEpubService service;
  late List<Map<String, String>> nativePending;
  late List<MethodCall> calls;

  setUp(() {
    nativePending = [];
    calls = [];
    service = ExternalEpubService(channel: channel, supported: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'takePendingFiles') {
        final files = nativePending.toList();
        nativePending.clear();
        return files;
      }
      return null;
    });
  });

  tearDown(() {
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    service.dispose();
  });

  Future<void> notifyNativeFilesAvailable() async {
    final completed = Completer<void>();
    binding.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('filesAvailable'),
      ),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  test('冷启动读取原生暂存文件，重复 start 不重复接收', () async {
    nativePending.add({'name': '中文书.epub', 'path': '/cache/incoming-1.epub'});
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.start();
    await service.start();

    expect(
      calls.where((call) => call.method == 'takePendingFiles'),
      hasLength(1),
    );
    expect(notifications, 1);
    expect(service.hasPendingFiles, isTrue);
    final file = service.takeNext();
    expect(file.name, '中文书.epub');
    expect(file.path, '/cache/incoming-1.epub');
    expect(service.hasPendingFiles, isFalse);
  });

  test('已启动后继续接收文件，按收到顺序入队', () async {
    await service.start();
    nativePending.addAll([
      {'name': 'first.epub', 'path': '/cache/1.epub'},
      {'name': 'second.EPUB', 'path': '/cache/2.epub'},
    ]);
    await notifyNativeFilesAvailable();
    nativePending.add({'name': 'third.epub', 'path': '/cache/3.epub'});
    await notifyNativeFilesAvailable();

    expect(service.takeNext().name, 'first.epub');
    expect(service.takeNext().name, 'second.EPUB');
    expect(service.takeNext().name, 'third.epub');
    expect(service.hasPendingFiles, isFalse);
  });

  test('读取权限失败保留为可反馈的导入错误', () async {
    nativePending.add({'name': 'lost.epub', 'error': 'Permission denied'});
    await service.start();

    expect(
      () => service.takeNext().readBytes(),
      throwsA(isA<BookImportException>()),
    );
  });

  test('取消或完成后通知原生清理缓存副本', () async {
    const file = ExternalEpubFile(name: 'book.epub', path: '/cache/book.epub');
    await service.release(file);

    expect(calls.single.method, 'releaseFile');
    expect(calls.single.arguments, {'path': '/cache/book.epub'});
  });

  test('桌面端无需初始化平台通道', () async {
    final desktop = ExternalEpubService(channel: channel, supported: false);
    await desktop.start();
    expect(calls, isEmpty);
    desktop.dispose();
  });
}
