import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../repositories/library_repository.dart';
import '../context/context_controller.dart';
import '../context/context_settings.dart';
import '../context/context_sheet.dart';
import '../reader/reader_background_settings.dart';
import '../reader/widgets/book_card_tile.dart';
import '../reader/widgets/reader_background_surface.dart';

/// 全文搜索页：结果默认折叠为 3 行摘要（命中关键词高亮），点击展开为
/// 与主界面一致的整张阅读卡片；滚动到底部自动加载下一页。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _results = <CardSearchResult>[];
  final _expandedCardIds = <int>{};

  Timer? _debounce;
  Timer? _indexPollTimer;
  ContextSettings _contextSettings = contextSettingsSetting.value;

  var _query = '';
  var _isSearching = false;
  var _isLoadingMore = false;
  var _hasMore = false;
  var _indexReady = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 懒触发回填：只有进入搜索功能才为升级前的存量卡片建索引。
    unawaited(widget.repository.ensureSearchIndexBuilt());
    _watchIndexReadiness();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _indexPollTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 升级后的首次回填在后台进行；就绪前轮询并在就绪后刷新当前结果。
  Future<void> _watchIndexReadiness() async {
    if (await widget.repository.isSearchIndexReady()) return;
    if (!mounted) return;
    setState(() => _indexReady = false);
    _indexPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final ready = await widget.repository.isSearchIndexReady();
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (ready) {
        timer.cancel();
        setState(() => _indexReady = true);
        _runSearch();
      }
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  void _onScroll() {
    if (_scrollController.positions.length != 1) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results.clear();
        _expandedCardIds.clear();
        _hasMore = false;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _query = query;
      _isSearching = true;
    });
    final page = await widget.repository.searchCards(query, limit: _pageSize);
    if (!mounted || query != _searchController.text.trim()) return;
    setState(() {
      _results
        ..clear()
        ..addAll(page);
      _expandedCardIds.clear();
      _hasMore = page.length == _pageSize;
      _isSearching = false;
    });
  }

  Future<void> _loadMore() async {
    if (_query.isEmpty || _isSearching || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final page = await widget.repository.searchCards(
      _query,
      limit: _pageSize,
      offset: _results.length,
    );
    if (!mounted) return;
    setState(() {
      _results.addAll(page);
      _hasMore = page.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _refreshCard(int cardId) async {
    final cards = await widget.repository.loadCardsByIds([cardId]);
    if (!mounted || cards.isEmpty) return;
    setState(() {
      final index = _results.indexWhere((hit) => hit.card.id == cardId);
      if (index >= 0) {
        _results[index] = CardSearchResult(
          card: cards.single,
          snippet: _results[index].snippet,
        );
      }
    });
  }

  Future<void> _toggleRead(CardSearchResult hit) async {
    await widget.repository.toggleRead(hit.card);
    await _refreshCard(hit.card.id);
  }

  Future<void> _toggleFavorite(CardSearchResult hit) async {
    await widget.repository.toggleFavorite(hit.card);
    await _refreshCard(hit.card.id);
  }

  Future<void> _showContext(CardSearchResult hit) async {
    final card = hit.card;
    final contextController = ContextController(
      repository: widget.repository,
      bookId: card.bookId,
      initialCard: card,
      initialSettings: _contextSettings,
    );
    await contextController.load();

    if (!mounted) {
      contextController.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContextSheet(
        controller: contextController,
        bookTitle: card.bookTitle,
      ),
    );

    if (mounted) {
      saveContextSettingsSetting(contextController.settings);
      setState(() => _contextSettings = contextController.settings);
      for (final cardId in contextController.changedCardIds) {
        await _refreshCard(cardId);
      }
    }
    contextController.dispose();
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const Center(child: Text('输入关键词搜索全部书籍正文'));
    }
    if (_isSearching) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(child: Text('没有找到包含“$_query”的卡片'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _results.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final hit = _results[index];
        final expanded = _expandedCardIds.contains(hit.card.id);
        return _SearchResultItem(
          hit: hit,
          expanded: expanded,
          repository: widget.repository,
          onToggleExpand: () {
            setState(() {
              expanded
                  ? _expandedCardIds.remove(hit.card.id)
                  : _expandedCardIds.add(hit.card.id);
            });
          },
          onToggleRead: () => _toggleRead(hit),
          onToggleFavorite: () => _toggleFavorite(hit),
          onShowContext: () => _showContext(hit),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        return Scaffold(
          backgroundColor: backgroundSettings.backgroundColor(
            Theme.of(context).brightness,
          ),
          body: ReaderBackgroundSurface(
            settings: backgroundSettings,
            child: ColoredBox(
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white)
                      .withValues(alpha: 0.10),
              child: SafeArea(
                // 宽屏（桌面/平板横屏）下内容居中限宽：比展开上下文弹窗
                // （Material 3 默认 640）略宽，窄屏不受影响。
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 54,
                          child: Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.arrow_back),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).backButtonTooltip,
                                onPressed: () => Navigator.maybePop(context),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: TextField(
                                    controller: _searchController,
                                    autofocus: true,
                                    onChanged: _onQueryChanged,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      hintText: '搜索正文…',
                                      isDense: true,
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                        size: 20,
                                      ),
                                      suffixIcon: _query.isEmpty
                                          ? null
                                          : IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: const Icon(
                                                Icons.clear_rounded,
                                                size: 18,
                                              ),
                                              onPressed: () {
                                                _searchController.clear();
                                                _onQueryChanged('');
                                              },
                                            ),
                                      filled: true,
                                      fillColor: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.7),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_indexReady)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            child: ValueListenableBuilder<double?>(
                              valueListenable:
                                  widget.repository.searchIndexProgress,
                              builder: (context, progress, _) {
                                final percent = progress == null
                                    ? null
                                    : (progress * 100).round();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 3,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      percent == null
                                          ? '正在创建搜索索引，结果可能不完整'
                                          : '正在创建搜索索引 $percent%，结果可能不完整',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        Expanded(child: _buildBody()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
    required this.hit,
    required this.expanded,
    required this.repository,
    required this.onToggleExpand,
    required this.onToggleRead,
    required this.onToggleFavorite,
    required this.onShowContext,
  });

  final CardSearchResult hit;
  final bool expanded;
  final LibraryRepository repository;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleRead;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowContext;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.expand_less, size: 18),
              label: const Text('收起'),
              onPressed: onToggleExpand,
            ),
          ),
          BookCardTile(
            card: hit.card,
            repository: repository,
            onToggleRead: onToggleRead,
            onToggleFavorite: onToggleFavorite,
            onShowContext: onShowContext,
            showBookTitle: true,
            // 搜索页不用毛玻璃，与折叠态搜索条目保持一致的扁平样式。
            flat: true,
          ),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    final card = hit.card;
    final chapter = card.chapterTitle;
    final subtitle = chapter == null || chapter.isEmpty
        ? '#${card.cardIndex}'
        : '$chapter · #${card.cardIndex}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggleExpand,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.bookTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(children: _snippetSpans(context, hit.snippet)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 把 `snippet()` / LIKE 兜底输出里的 `<mark>` 标记渲染为高亮片段。
  static List<TextSpan> _snippetSpans(BuildContext context, String snippet) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5);
    final highlight = base?.copyWith(
      color: cs.onTertiaryContainer,
      backgroundColor: cs.tertiaryContainer,
      fontWeight: FontWeight.w600,
    );

    final spans = <TextSpan>[];
    var rest = snippet;
    while (true) {
      final start = rest.indexOf('<mark>');
      if (start < 0) {
        if (rest.isNotEmpty) spans.add(TextSpan(text: rest, style: base));
        break;
      }
      final end = rest.indexOf('</mark>', start);
      if (end < 0) {
        spans.add(TextSpan(text: rest, style: base));
        break;
      }
      if (start > 0) {
        spans.add(TextSpan(text: rest.substring(0, start), style: base));
      }
      spans.add(
        TextSpan(text: rest.substring(start + 6, end), style: highlight),
      );
      rest = rest.substring(end + 7);
    }
    return spans;
  }
}
