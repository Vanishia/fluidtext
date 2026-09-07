# 全文搜索（FTS）实现计划

日期：2026-09-01
状态：已实施（分支 feature/full-text-search）

## 1. 背景与目标

为 FluidText 增加全文搜索功能：输入关键词，跨全部书籍正文检索，返回匹配的卡片（含书名、章节、高亮片段），点击可跳转到对应上下文阅读。

## 2. 现状

- 数据层：Drift 2.15 + sqlite3，后台 isolate 打开数据库（`lib/storage/sqlite/library_database.dart:106`），`schemaVersion = 1`，索引为手写 SQL（`sqliteSchemaV1Indexes`），`MigrationStrategy` 仅有 `onCreate` + `beforeOpen`，**无 `onUpgrade`**。
- 正文存储：EPUB 导入后切为"卡片"（`TextSplitter` 目标 300 字、上限 900 字按句切分），存于 `book_cards.content`（TEXT），带 `chapter_index` / `chapter_title` / `card_index` 元数据。
- 现有搜索：**无**。全 lib/ 无任何搜索相关代码。
- 数据规模：压力基准 50,000 卡片 ≈ 47MB 正文（见 `docs/sqlite_storage_migration_plan.md`）。
- UI 入口：侧栏 `AppSidePanel`（`lib/features/settings/app_drawer.dart`）底部一排 `_QuietIconButton`，启动页与阅读页共用。

## 3. 方案选型

| 方案 | 结论 |
|---|---|
| SQLite FTS5 虚表 + `trigram` 分词器 | **采用**。中英文均可子串匹配，毫秒级查询 |
| FTS5 + `unicode61`（默认） | 否决：中文整段算一个 token，中文搜索不可用 |
| FTS5 + ICU 分词器 | 否决：跨平台打包 ICU 成本高 |
| 应用层 LIKE 全表扫描 | 否决：50MB 文本每次全扫，体验与扩展性差 |

约束：`sqlite3_flutter_libs` 原生库默认开启 FTS5（`SQLITE_ENABLE_FTS5`），落地前先加一条冒烟测试验证（直接建虚表或查 `pragma_compile_options`）。

## 4. 数据层设计

### 4.1 FTS 虚表与触发器（手写 SQL，沿用现有惯例）

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS book_cards_fts USING fts5(
  content,
  content='book_cards',
  content_rowid='id',
  tokenize='trigram'
);

CREATE TRIGGER IF NOT EXISTS book_cards_fts_ai AFTER INSERT ON book_cards BEGIN
  INSERT INTO book_cards_fts(rowid, content) VALUES (new.id, new.content);
END;
CREATE TRIGGER IF NOT EXISTS book_cards_fts_ad AFTER DELETE ON book_cards BEGIN
  INSERT INTO book_cards_fts(book_cards_fts, rowid, content) VALUES('delete', old.id, old.content);
END;
CREATE TRIGGER IF NOT EXISTS book_cards_fts_au AFTER UPDATE ON book_cards BEGIN
  INSERT INTO book_cards_fts(book_cards_fts, rowid, content) VALUES('delete', old.id, old.content);
  INSERT INTO book_cards_fts(rowid, content) VALUES (new.id, new.content);
END;
```

### 4.2 迁移（schema v1 → v2）

- `library_database.dart`：`schemaVersion` 升为 2，新增 `onUpgrade`，幂等执行上述 DDL。
- 存量回填：**懒触发**——不在 App 启动时回填，只有进入搜索页才调用
  `ensureSearchIndexBuilt()`（只有 v1→v2 升级的库有未建索引的存量卡片；
  新装/迁移/恢复走的都是带触发器的 onCreate，从第一条插入起索引就是同步的，
  `onCreate` 直接写入完成标记 `fts_index_version`）。
- 回填实现：单事务内分批扫描（500 卡/批），经 `searchIndexProgress`
  （`ValueNotifier<double?>`）上报真实进度；幂等，并发调用共享同一次回填；
  失败不写标记，下次进入搜索页重试。
- trigram 注意点：关键词长度 < 3 个字符时 trigram 无法命中（退化为全表扫），UI 层对 1–2 字查询直接走 `LIKE` 兜底或提示。

### 4.3 Repository 接口

在 Repository 接口与 `lib/storage/sqlite/sqlite_library_repository.dart` 新增：

```dart
Future<List<CardSearchResult>> searchCards(String query, {int limit = 50, int offset = 0});
```

- 查询用 `customSelect` + `snippet(book_cards_fts, 0, '<mark>', '</mark>', '…', 32)` 取高亮片段，`bm25()` 排序，JOIN `book_cards` / `books` 取书名、章节、`card_index`。
- `CardSearchResult`：card id、book id、书名、章节标题、card_index、高亮片段。
- `LIKE` 兜底：query trim 后长度 < 3 时用 `book_cards.content LIKE '%q%'`（同样走索引外扫描，但数据量可控）。

## 5. UI 设计

- 入口：`app_drawer.dart` 的 `AppSidePanel` 新增"搜索"图标（启动页/阅读页共用此面板，改一处）。
  - 不在底部按钮排，放在书架按钮（`_ShelfButton`）右侧，一个小放大镜图标。
- 搜索页（新增 `lib/features/search/search_page.dart`）：
  - 顶部搜索框，输入防抖（~300ms）触发查询；
  - 结果列表懒加载（limit/offset 滚动加载更多）；
  - 结果卡片**默认折叠**：只显示书名 + 章节标题 + 3 行摘要，摘要中命中关键词高亮（解析 `snippet()` 的 `<mark>` 标记渲染为高亮 TextSpan）；
  - 点击卡片后**展开为整张卡片**，展示全量正文，样式与主界面阅读卡片一致（复用阅读卡片组件）；
  - 空态 / 索引构建中提示：真实进度条（`searchIndexProgress`）+ 百分比文案；
    移动端同时挂常驻通知"正在创建搜索索引"（复用导入通知的 MethodChannel，
    独立 notification id 4202 与渠道"搜索索引"），桌面端仅页内进度条。
- 跳转：展开态可再进入上下文阅读，复用阅读页上下文弹层模式（`reader_page.dart:287` 的 `_showContext` / `ContextController`），定位到对应卡片。
- 参考实现：`lib/features/reader/card_list_page.dart`（收藏/已读列表的列表模式可直接套用）。

## 6. 边界与兼容

- **备份/恢复**：`buildBackupSnapshot` 不包含 FTS 表（内容可自动重建）；恢复后由打开时的幂等 rebuild 逻辑重建。
- **Isar 回滚路径**（`FLUIDTEXT_FORCE_ISAR_LIBRARY`）：搜索功能禁用（入口隐藏）——回滚路径仅为过渡残留，不为其实现搜索。
- **跨卡片关键词**：卡片按句边界切分，关键词跨卡片时按行匹配会漏，可接受，不处理。

## 7. 测试计划

- FTS5 可用性冒烟测试：建虚表 + trigram 分词 + 中文/英文查询命中（`test/db/` 或 `test/storage/`）。
- Repository 契约测试：复用 `test/repositories/library_repository_contract.dart` 模式，覆盖：中文词命中、英文命中、大小写、snippet 高亮标记、分页、`content` 更新/删除后索引同步。
- 迁移测试：v1 库（用 `tool/` 下 fixture 思路构造）升级后存量数据可搜、rebuild 幂等（重复执行不报错不重复）。
- 性能 benchmark：50,000 卡片下 rebuild 耗时与查询耗时（参照 `tool/sqlite_import_benchmark.dart` 模式），确认索引体积可接受（预期为正文 2–3 倍）。

## 8. 实施步骤

1. 冒烟验证 FTS5 + trigram 在当前打包的 sqlite3 原生库上可用（含 Android 真机）。
2. `library_database.dart`：schema v2、DDL、`onUpgrade`、懒触发分批 rebuild + 完成标记 + 进度上报；移动端常驻通知。
3. Repository：`searchCards` 接口 + SQLite 实现 + LIKE 兜底；Isar 实现抛 `UnimplementedError`（UI 层隐藏入口）。
4. 契约测试与迁移测试。
5. UI：搜索页 + 侧栏入口 + 结果跳转。
6. 备份/恢复确认 FTS 表被排除；补充恢复后 rebuild 的测试。
7. benchmark 验证性能与体积，更新本计划文档结论。

## 9. 验收标准

- 中文、英文关键词均能返回正确卡片，结果含书名/章节/高亮片段。
- 点击结果正确跳转至对应卡片上下文。
- 卡片增删改后搜索结果同步。
- 从 v1 数据库升级的存量数据可正常搜索。
- 50,000 卡片规模下查询 < 100ms，rebuild 不阻塞启动。

## 10. 风险

| 风险 | 缓解 |
|---|---|
| trigram 索引体积大（50MB 正文 → 索引约 100MB+） | 步骤 7 的 benchmark 实测确认；不可接受时再评估压缩/外部内容表已去重存储 |
| 原生库未开启 FTS5 | 步骤 1 先行冒烟，失败则换 `sqlite3_flutter_libs` 配置或自带编译库 |
| 回填耗时影响首次升级体验 | 后台构建 + 完成标记 + UI 提示 |
| 短查询（<3 字符）trigram 不命中 | LIKE 兜底 |

## 11. 实测结果（2026-09-01，Windows，测试 runner；工具 `tool/fts_benchmark.dart`）

合成数据：约 300 字/卡的中文正文，部分卡片埋入中英文检索词。

| 卡片数 | 导入（含 FTS） | 导入（无 FTS） | 索引回填（分批） | 中文查询 | 英文查询 | 库文件 | FTS 开销 |
|---|---|---|---|---|---|---|---|
| 1,000 | 546ms | 236ms | 376ms | 9ms | 3ms | 3.9MB | 2.7MB |
| 10,000 | 8.5s | 1.0s | 7.9s | 20ms | 12ms | 29MB | 18MB |
| 50,000 | 59.7s | 5.7s | 41.4s | 25ms | 28ms | 131MB | 76MB |

结论：

- **查询延迟优秀**：50,000 卡片下中英文查询均 <30ms，满足验收标准。
- **索引体积**约为库文件的 1.4 倍（≈正文字节的 1.7 倍），好于预估的 2–3 倍，可接受。
- **回填耗时**：50,000 卡片极端规模约 41s（分批比单条 `rebuild` 慢约 19%，
  换来真实进度上报），真实书库（几千卡）约 1–3s；懒触发（进入搜索页才执行），
  搜索页显示进度条，移动端另有常驻通知。
- **导入变慢**：trigram 索引使导入约慢 2–10 倍（约 1.1ms/卡）。真实书籍
  （数百至数千卡）导入从亚秒级变为 1–4s，可接受；50,000 卡为合成压力场景。
- 如未来导入耗时成为问题，可考虑导入时临时禁用触发器、导入后整体 rebuild。
