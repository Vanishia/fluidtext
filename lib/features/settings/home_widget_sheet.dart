import 'package:flutter/material.dart';

import '../../services/home_widget_service.dart';

Future<void> showHomeWidgetSheet(
  BuildContext context, {
  int bookCount = 0,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('桌面随机卡片', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('把五行书摘放到桌面，左下角显示书名，点击即可打开这张卡片的上下文。半透明底色自动跟随系统日夜间模式。'),
          const SizedBox(height: 12),
          const Text('添加时可选择书籍、仅收藏或仅未读，以及自动换卡频率。每个小组件单独设置，也可以点击组件上的设置按钮随时修改。'),
          const SizedBox(height: 20),
          if (bookCount == 0)
            const Text('请先添加书籍，再将小组件放到桌面。')
          else
            FilledButton.icon(
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: const Text('添加到桌面'),
              onPressed: () async {
                var requested = false;
                try {
                  requested = await HomeWidgetService.instance.requestPin();
                } catch (_) {
                  // Launchers may not offer pinning; their picker still works.
                }
                if (!context.mounted) return;
                if (!requested) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('请长按桌面空白处，打开“小组件”，选择 FluidText 随机卡片。'),
                    ),
                  );
                }
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  ),
);
