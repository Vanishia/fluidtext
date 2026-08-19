# 收藏 / 已读 / 数据统计页面优化清单（2026-08-19）

评审范围：

- 收藏页 `lib/features/reader/favorite_cards_page.dart`
- 已读页 `lib/features/reader/read_cards_page.dart`
- 数据统计页 `lib/features/reader/analysis/`（page / controller / models / widgets）
- 相关查询层 `lib/repositories/book_card_repository.dart`（Isar 回滚路径）、
  `lib/storage/sqlite/sqlite_library_repository.dart`（当前默认路径）

存储现状：默认走 SQLite（Drift）实现 `SqliteLibraryRepository`，查询层已是单次投影查询 +
`GROUP BY` 聚合 + 覆盖索引（`sqliteSchemaV1Indexes`），比较干净；Isar 实现
（`BookCardRepository`）仅作为 `FLUIDTEXT_FORCE_ISAR_LIBRARY` 回滚路径保留。
文中标注「遗留」的条目只影响 Isar 回滚路径。

安全方面：本次评审未发现明显安全问题（无注入面——SQLite 查询均走变量绑定；无敏感数据外泄面）。

---

## P0 —— 严重性能问题

### P0-1 收藏/已读页全量加载，无分页

`SqliteLibraryRepository._loadCardsWithState`（`sqlite_library_repository.dart:126-149`）
一条 `SELECT *` 把所有已读/收藏卡片一次性拉回，包括每张卡片的 `content` 全文和
`blocksJson`。重度用户已读卡片可达上万张，即十几 MB 以上的 Dart 对象常驻内存，且首屏要等
全部行反序列化完成。`ListView.separated` 只是 widget 懒构建，数据层没有懒加载。

建议：查询加 `LIMIT/OFFSET` 分页（现有索引 `idx_book_cards_read_activity` /
`idx_book_cards_favorite_activity` 已覆盖排序，分页成本低），滚动到底再加载下一页。

### P0-2 统计页缓存形同虚设：`load()` 忽略 `forceFullScan`

`ReadingAnalysisController.load`（`reading_analysis_controller.dart:40-42`）无论缓存是否
有效都无条件 `_loadFull(cacheKey)`。页面 `_load()` 设计了「先展示缓存再后台刷新」
（`reading_analysis_page.dart:47-56`），但后台这次刷新在数据未变时纯属浪费：每次打开统计页
都全量重扫（4 组查询 + 全量聚合）。

建议：`load()` 内先查 `getCachedAnalytics()`，命中且非 `forceFullScan` 直接返回缓存。

### P0-3 统计聚合跑在 UI isolate

`ReadingAnalytics.fromEvents`（`reading_analytics.dart:130-308`）对每个事件做 `toLocal()`、
`copyWith`、多次 map 更新，事件量大时会掉帧。输入数据不可变，适合 `compute()` 下沉。

---

## 极其影响用户体验的问题（单独区块）

### UX-1 列表页打开期间数据不更新，也无刷新入口

收藏/已读页只在 `initState` 加载一次。在阅读器里新收藏/标记已读后回到列表看不到变化，
也没有下拉刷新。建议监听 `LibraryChangeTracker.revision` 变化自动刷新，或至少加下拉刷新。

### UX-2 统计页刷新失败会用错误页覆盖已展示的缓存

`_load()` 失败时直接设置 `_error`（`reading_analysis_page.dart:68-74`），而
`_buildStateBody` 先判 `_error`——即使缓存内容正在展示，后台刷新失败也会把整块内容换成
错误页。建议：已有缓存时刷新失败只提示 SnackBar/横幅，保留原内容。

### UX-3 加载态只有一个转圈

三个页面加载中都只有 `CircularProgressIndicator`。应使用骨架屏，项目已有
`lib/widgets/reading_skeleton.dart` 可参考/复用。（此方向已确认要做）

---

## P1 —— 中等问题

### P1-1 收藏/已读页 `_load()` 串行 await，且拉了全量书籍

两页 `_load()`（各 43-56 行）先等卡片查询，再等 `_loadBookTitlesById()`（内部又串行
`loadBooks()` + `loadRemarks()`）。三者互不依赖，应 `Future.wait` 并行；且 `loadBooks()`
拉全部书籍，实际只需要 `widget.bookIds` 范围内的，应走已有的 `loadBooksByIds`。

### P1-2 统计页排序 getter 在 build / 拖拽中重复计算

`booksSortedByRead/Progress/Favorite` 每次都是 copy + 全量 sort
（`reading_analytics.dart:316-350`）。`RankingsModule.build` 一次调 3 个，
`DepthModule.build` 再调一次；拖动模块排序时 `ReorderableListView` 每帧重建，这些排序
每帧都在跑。应在 `fromEvents` 里算好存为 final 字段。

### P1-3 热力图一次性铺约 371 个 `Tooltip + GestureDetector`

`analysis_modules.dart:168-223`，53 周 × 7 天，每格一个 Tooltip（带 overlay 管理，较重）。
热力图是统计页重做后要保留的模块，值得优化：改为整层一个 GestureDetector 按命中位置换算
日期，Tooltip 只在长按/悬停时动态创建。

### P1-4 收藏/已读两页是 340 行 ×2 的逐行复制

`favorite_cards_page.dart` 与 `read_cards_page.dart` 仅文案和过滤条件不同。后续任何优化
都要做两遍，应合并为一个参数化的列表页。

### P1-5 收藏/已读列表无搜索、筛选、排序切换

收藏量上来后只能无限滚动，基本不可用。建议至少支持：按内容关键字搜索、按书籍筛选、
时间正/倒序切换。

### P1-6 列表内无法直接取消收藏 / 取消已读

目前只能进上下文弹层操作，路径长。建议列表项加滑动操作或长按菜单。（注意：主界面卡片
的长按复制要保持隐式、不加显眼入口，见「已确认不做」。）

### P1-7 统计页展示层问题（统计展示将大重做，以下供重做时参考）

- 榜单（已读最多/完成度最高/收藏最多）和「快读完的书」行均不可点击；
- 无时间范围切换（近 30 天 / 近 90 天 / 今年 / 全部）；
- 无整体空状态，新用户看到七个模块全是 0 和「暂无数据」；
- 单日弹层时间线事件同样只展示、不可操作。

---

## P2 —— 小问题 / 遗留

### P2-1 列表 itemBuilder 每次 build 重复格式化时间字符串

两页 itemBuilder 里 `_formatReadAt/_formatFavoriteAt` 每个 item 每次 build 都重新
padLeft 拼接；且每个 item 各自挂一个合并两个全局 setting 的 `AnimatedBuilder`，改一次
字号全列表 N 个 builder 各自重建。可预计算时间字符串、字号监听提升到页面级。

### P2-2  已解决

### P2-3 「遗留」Isar 回滚路径的重复投影查询与缺失索引

`BookCardRepository._loadReadActivityEventsByProjection`
（`book_card_repository.dart:162-257`）对同一 filter+sort 重复执行 4 次属性投影，
收藏事件再来 4 次；且 `isRead/readAt/isFavorite/favoritedAt` 在 Isar schema 上无索引，
`sortByReadAtDesc` 为全集合内存排序。SQLite 路径已全部解决，此项仅在维护回滚路径时
顺手处理，或直接随 Isar 路径退役而消失。

### P2-4 热力图空格子的重复对象分配

`analysis_modules.dart:182` 在 lookup miss 时每次 build 都 `DayAnalysis.empty(day)` 新建
对象；miss 时只需要 count=0，用常量空实例即可。

### P2-5 统计页无数据时效提示

修复 P0-2 的缓存后，页面可能展示稍旧的数据，宜加「更新于 HH:mm」或下拉刷新入口让用户
感知时效。

---

## 已确认不做 / 维持现状（避免重复提出）

- **卡片点击不跳回阅读器**：想看前后文、点击上下文按钮即可，这是应用阅读体验的独特设计。
- **不显示章节名**：部分书没有章节名，章节名不参与体验，`#序号` 更清楚，维持现状。
- **日期格式维持现状**（`yyyy-MM-dd HH:mm` 逐行显示）。
- **主界面卡片长按复制保持隐式**，不加显式按钮/菜单；仅在未选书时的启动页为移动端
  （Android/iOS）增加一句提示「长按卡片复制段落内容」。（提示已随本次评审落地）
- **统计页展示内容（统计哪些数据）暂不调整**，后续整体大重做；热力图模块保留
  其性能优化（P1-3、P2-4）不受重做影响。
