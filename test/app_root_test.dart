import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/app_settings.dart';
import 'package:fluidtext/features/bookshelf/launch_page.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/main.dart';

void main() {
  testWidgets('更换阅读背景不重建根子树，页面状态保留', (tester) async {
    readerBackgroundSetting.value = const ReaderBackgroundSettings();
    await tester.pumpWidget(const MyApp(initialLaunchState: LaunchState()));
    await tester.pump();
    await tester.pump();

    final stateBefore =
        tester.state<State<LaunchPage>>(find.byType(LaunchPage));

    // 模拟用户在外观设置中切换背景配色：种子色缓存 key 随之变化，
    // 但根子树（含 LaunchPage 的选书状态）不允许被重建。
    readerBackgroundSetting.value = const ReaderBackgroundSettings().copyWith(
      paletteKey: 'sage',
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(LaunchPage), findsOneWidget);
    expect(
      tester.state<State<LaunchPage>>(find.byType(LaunchPage)),
      same(stateBefore),
    );
  });
}
