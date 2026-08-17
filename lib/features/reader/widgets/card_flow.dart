import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../models/book_card.dart';

/// 阅读区可用宽度达到该值时，卡片流切换为双列瀑布流。
/// 阈值基于宽度而不是字数，因此不受字号、行距设置影响。
const double kCardWaterfallMinWidth = 1100;

/// 阅读卡片流：窄屏单列列表，超宽屏双列瀑布流（参考小红书）。
/// 单双列切换时交叉淡入淡出，避免界面闪烁；共享同一个
/// [ScrollController]，切换列数不丢滚动位置。
class BookCardFlow extends StatelessWidget {
  const BookCardFlow({
    super.key,
    required this.scrollController,
    required this.cards,
    required this.hasMore,
    required this.cardBuilder,
  });

  final ScrollController scrollController;
  final List<BookCard> cards;
  final bool hasMore;
  final Widget Function(BookCard card) cardBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= kCardWaterfallMinWidth;
        final padding = EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 2,
          bottom: MediaQuery.paddingOf(context).bottom + 20,
        );
        final itemCount = cards.length + (hasMore ? 1 : 0);

        Widget itemBuilder(BuildContext context, int index) {
          if (index >= cards.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return cardBuilder(cards[index]);
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: twoColumns
              ? MasonryGridView.count(
                  key: const ValueKey('card-flow-two-columns'),
                  controller: scrollController,
                  padding: padding,
                  crossAxisCount: 2,
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                )
              : ListView.builder(
                  key: const ValueKey('card-flow-single-column'),
                  controller: scrollController,
                  padding: padding,
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
        );
      },
    );
  }
}
