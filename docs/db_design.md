# FluidText 数据库设计（SQLite 现状）

> 本文档描述当前生效的 SQLite（Drift）存储设计，替代 2026-06-06 的 Isar 时代草案
> （已归档至 `docs/archive/db_design_2026-06-06.md`）。
> 权威来源：`lib/storage/sqlite/library_database.dart`（schema 定义）、
> `lib/storage/sqlite/sqlite_library_repository.dart`（查询实现）。

## 总览

- ORM：Drift（`drift: ^2.15.0`），底层 `sqlite3`，`NativeDatabase.createInBackground`
  在后台 isolate 中跑数据库。
- schema 版本：`LibraryDatabase.currentSchemaVersion = 1`。
- 数据库文件位置由 `StorageLayoutProvider` 决定（`layout.sqliteDatabaseFile`），
  打开前确保根目录存在（`openLibraryDatabaseForLayout`）。
- Repository 接口：`lib/repositories/library_repository.dart` 的 `LibraryRepository`，
  默认实现 `SqliteLibraryRepository`；Isar 实现 `BookCardRepository` 仅作为
  `FLUIDTEXT_FORCE_ISAR_LIBRARY` 回滚路径保留。

### 连接 PRAGMA

`configureSqlite`（打开时）与 `beforeOpen`（每次连接）设置：

- `journal_mode = WAL`
- `foreign_keys = ON`
- `busy_timeout = 5000`
- `synchronous = FULL` —— 保守默认；只有在真实用户性能不可接受 **且** 崩溃恢复测试
  通过时才允许降级为 NORMAL（迁移计划 §4.3 的决策）

## 表结构

### books —— 书籍

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER PK | `CHECK(id > 0)` |
| `title` | TEXT NOT NULL | 书名（导入时确定） |
| `created_at_ms` | INTEGER NOT NULL | 创建时间（epoch ms） |
| `file_hash` | TEXT NULL | 源文件 hash，用于重复导入检测 |
| `content_fingerprint` | TEXT NULL | 内容指纹，重复导入检测的第二依据 |
| `source_file_name` | TEXT NULL | 来源文件名 |
| `imported_at_ms` | INTEGER NULL | 导入时间 |
| `card_count` | INTEGER NULL | 卡片总数，`>= 0`；用于不完整导入检测 |
| `text_char_count` | INTEGER NULL | 正文字符数，`>= 0` |
| `asset_root_key` | TEXT NULL | 图片等资源在磁盘上的根目录 key |

### book_cards —— 阅读卡片（最小内容单元）

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER PK | `CHECK(id > 0)` |
| `book_id` | INTEGER NOT NULL | FK → `books(id) ON DELETE CASCADE`，`CHECK(book_id > 0)` |
| `book_title` | TEXT NOT NULL | 冗余书名（导入时快照，避免列表页 join） |
| `card_index` | INTEGER | 全书顺序，**阅读主轴**，`>= 0` |
| `chapter_index` | INTEGER | 章节序号（辅助元数据），`>= 0` |
| `chapter_card_index` | INTEGER | 章内序号（辅助元数据），`>= 0` |
| `chapter_title` | TEXT NULL | 章节名（部分书没有，不参与核心体验） |
| `content` | TEXT NOT NULL | 卡片正文 |
| `blocks_json` | TEXT NULL | 富文本块结构（图片占位等） |
| `is_read` | INTEGER NOT NULL | 0/1，`CHECK(is_read IN (0,1))` |
| `read_at_ms` | INTEGER NULL | 已读时间 |
| `is_favorite` | INTEGER NOT NULL | 0/1，`CHECK(is_favorite IN (0,1))` |
| `favorited_at_ms` | INTEGER NULL | 收藏时间 |

约束：

- `UNIQUE(book_id, card_index)` —— 全书顺序在一本书内唯一
- `CHECK(is_read = 1 OR read_at_ms IS NULL)` —— 状态与时间戳一致
- `CHECK(is_favorite = 1 OR favorited_at_ms IS NULL)` —— 同上

### book_assets —— 书籍资源元数据

资源**字节本体存在文件系统**（`BookAssetStore`，按 `asset_root_key` 组织目录），
表里只存元数据：

| 列 | 类型 | 说明 |
|---|---|---|
| `id` | INTEGER PK | |
| `book_id` | INTEGER NOT NULL | FK → `books(id) ON DELETE CASCADE` |
| `asset_key` | TEXT NOT NULL | 资源 key |
| `original_href` / `normalized_href` | TEXT NULL | EPUB 原始 / 归一化链接 |
| `mime_type` | TEXT NULL | |
| `relative_path` | TEXT NOT NULL | 磁盘相对路径 |
| `byte_length` | INTEGER NULL | `>= 0` |
| `created_at_ms` | INTEGER NOT NULL | |

### book_remarks —— 书籍备注名

| 列 | 类型 | 说明 |
|---|---|---|
| `book_id` | INTEGER PK | FK → `books(id) ON DELETE CASCADE` |
| `title` | TEXT NOT NULL | 用户改的显示名（覆盖 `books.title` 展示） |
| `updated_at_ms` | INTEGER NOT NULL | |

Isar 时代 remarks 存在独立数据库，SQLite 后并入主库并挂外键。

### storage_metadata —— 存储元信息

KV 表（`key` PK、`value`、`updated_at_ms`），每次打开连接时 upsert：

- `schema_version` = 当前 schema 版本
- `storage_format_version` = `'sqlite-v1'`

用于迁移完成标记与回滚判定。

## 索引（schema v1）

`sqliteSchemaV1Indexes`（建库时创建）：

| 索引 | 列 | 服务的查询 |
|---|---|---|
| `idx_books_file_hash` | `books(file_hash)` | 重复导入检测 |
| `idx_books_content_fingerprint` | `books(content_fingerprint)` | 重复导入检测 |
| `idx_books_created_at_desc` | `books(created_at_ms DESC)` | 书架排序 |
| `idx_book_cards_book_order` | `book_cards(book_id, card_index)` | 顺序阅读 / 上下文展开 |
| `idx_book_cards_unread_order` | `book_cards(book_id, is_read, card_index)` | 未读卡片流 |
| `idx_book_cards_read_activity` | `book_cards(is_read, read_at_ms DESC, id DESC)` | 已读列表 / 已读事件 |
| `idx_book_cards_favorite_activity` | `book_cards(is_favorite, favorited_at_ms DESC, id DESC)` | 收藏列表 / 收藏事件 |
| `idx_book_assets_book_asset_key` | `book_assets(book_id, asset_key)` | 资源查找 |
| `idx_book_assets_normalized_href` | `book_assets(normalized_href)` | 资源查找 |

注意：两个 activity 索引以 `is_read` / `is_favorite` 打头，不带 `book_id`，
因此**全库已读/收藏列表**走索引很高效；按书架（bookIds 子集）过滤时是
`IN (...)` + 排序，量大后可再评估复合索引。

## 查询设计要点

`SqliteLibraryRepository` 的关键查询均为手写 `customSelect` + 变量绑定：

- **已读/收藏列表**：`SELECT * ... WHERE is_x = 1 [AND book_id IN (...)]
  ORDER BY x_at DESC, id DESC`（`_loadCardsWithState`）。当前无分页——
  全量含 `content` 进内存，已列入优化清单 P0-1
  （`docs/reading_pages_optimization_review_2026-08-19.md`）。
- **阅读分析事件**：只取 `id, book_id, card_index, x_at_ms` 四列的轻量投影
  （`_loadActivityEvents`），不反序列化 `content`，单次查询完成
  （Isar 时代的 4 次投影 + zip 已随 SQLite 迁移废弃）。
- **书籍统计**：一条 `GROUP BY book_id` 聚合出 total/read/favorite
  （`loadBookStats`），替代 Isar 时代的每书 3 次 count。

## 完整性与维护

- 外键 `ON DELETE CASCADE`：删书自动清卡片、资源元数据、备注；磁盘资源由
  `BookAssetStore.deleteAssetRoot` 单独清理（失败仅记日志，不回滚）。
- `PRAGMA integrity_check` / `PRAGMA foreign_key_check` 有封装
  （`integrityCheck()` / `foreignKeyCheck()`）。
- `checkpoint({truncate})` 封装了 `wal_checkpoint`，供备份导出前收敛 WAL。

## 变更标记

所有写操作（toggleRead / toggleFavorite / 导入 / 删除 / 备注等）后调用
`LibraryChangeTracker.instance.markChanged()` 递增 revision，阅读分析缓存以此
判定失效（见 `reading_analysis_controller.dart`）。

## 明确不放在数据库里的东西

- 图片/资源字节本体 → 文件系统（`BookAssetStore`）
- 阅读进度会话、UI 设置等 → `SharedPreferences`（`app_settings.dart` 一带）
- 阅读分析结果 → 内存 SWR 缓存，不落库
