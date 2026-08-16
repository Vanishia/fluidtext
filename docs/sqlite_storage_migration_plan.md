# FluidText SQLite 与应用数据目录迁移计划

> 文档状态：阶段一至六已实施（分支 codex/sqlite-migration）  
> 编写日期：2026-08-12（实施记录持续追加）  
> 适用平台：Windows、Android  
> 当前正式版本基线：`1.0.0`  
> 正文为设计规划；各阶段的「实施记录」引用块与附录 A 记录实际落地情况，如有出入以实施记录为准。原《SQLite Migration Phase 1 Baseline Notes》已于 2026-08-15 并入附录 A，单独文件不再维护。

## 1. 背景与目标

FluidText 当前以 Isar 作为主数据库，并将一部分数据库、配置和资源放在 `getApplicationDocumentsDirectory()` 返回的目录中。这个选择在 Android 上通常对应应用私有目录，但在 Windows 上会落到用户真实的“文档”目录，造成以下问题：

- `default.isar`、`book_remarks.isar`、JSON 配置和资源目录直接污染 Documents 根目录。
- Documents 可能被 OneDrive 或其他同步软件接管，数据库文件可能在运行时被同步、占用或产生冲突副本。
- `default.isar` 名称过于通用，存在与其他应用文件冲突或迁移时误识别的风险。
- Isar 是私有二进制格式；发生损坏时，可用的通用检查、导出和修复工具有限。
- 主库与备注库分离，导入、备份和备注服务仍直接依赖 Isar，数据库替换边界不完整。
- 当前没有 ZIP 恢复入口；用户即使导出了备份，也不能在应用内完成恢复。

本轮目标是把“数据库更换”和“Windows 数据目录修复”合并为一次用户可见迁移：

```text
旧 Documents 中的 Isar、JSON 和资源
                  ↓ 复制并只读解析
目标目录中的 staging SQLite、JSON 和资源
                  ↓ 完整校验并原子切换
%LOCALAPPDATA%\Vanishia\FluidText\fluidtext_library.sqlite
```

目标包括：

1. 主存储由 Isar 迁移到 SQLite，首选 Drift 作为 Dart 访问层。
2. Windows 正式版运行数据迁移到 `%LOCALAPPDATA%\Vanishia\FluidText`，Android 继续使用应用私有目录。
3. Debug、Profile、Release 的新数据目录互相隔离。
4. 检测到旧数据时，启动后先显示专用迁移页面，不提前打开正式数据库或进入阅读页面。
5. 迁移前允许用户导出 ZIP 备份；迁移过程中显示真实进度；失败时明确说明旧数据未删除，并提示可在书架中导入 ZIP。
6. SQLite 切换完成后补齐 ZIP 导入恢复，入口暂放在书架窗口。
7. 尽量保持当前 EPUB 导入速度、书架加载速度和阅读卡片加载体感。
8. 为 Repository、事务、迁移、备份恢复、真实 EPUB 和双平台路径补齐测试。

## 2. 本轮范围与非目标

### 2.1 本轮必须完成

- 统一应用存储目录解析与环境隔离。
- SQLite schema、索引、事务策略和数据库生命周期管理。
- SQLite 版 `LibraryRepository`。
- 将 EPUB 导入、备注、备份导出从具体 Isar 实例中解耦。
- 旧 Isar 到 SQLite 的一次性迁移引擎。
- 设置、会话、壁纸、字体和书籍图片的同步迁移。
- 迁移页面、真实进度、错误提示、重试和崩溃恢复。
- ZIP v2 导入兼容和新版备份格式的导出/恢复闭环。
- Windows、Android 的单元测试、集成测试、构建验证和性能基准。
- 首个 SQLite 版本保留旧 Isar 文件，不自动删除。

### 2.2 明确不在本轮完成

- Web 端支持。
- 云同步、多设备同步或冲突合并。
- 全文搜索和 FTS 索引。SQLite schema 可预留升级能力，但首轮不创建或同步维护 FTS。
- 统计页面的产品功能重做；只把现有统计查询等价迁移并消除明显的 N×3 count。
- ZIP 恢复时进行复杂的“合并两个书库”。首版只做原子替换恢复。
- 自动删除 Documents 中的旧 Isar、旧 JSON 或旧资源目录。
- 为了迁移而重写 EPUB 解析、切卡规则或阅读 UI。
- 在 SQLite 完整切换前先把 Isar 搬到新目录。只允许复制到临时 staging 进行迁移读取。
- 本轮不实现数据库静态加密。SQLite 明文保存的风险需要在风险章节和发布说明中明确记录；若以后书库内容、备注或设备威胁模型要求更高，再单独评估 SQLCipher、系统密钥链和密钥恢复策略。

## 3. 当前代码盘点与问题定位

### 3.1 当前数据与文件位置

当前仍通过 `getApplicationDocumentsDirectory()` 访问的内容：

| 数据 | 当前实现 | 当前文件或目录 |
| --- | --- | --- |
| 主书库 | `lib/db/isar_db.dart` | `default.isar`、对应锁文件 |
| 书籍备注 | `lib/services/book_remark_service.dart` | `book_remarks.isar`、对应锁文件 |
| 行为设置 | `lib/services/app_behavior_settings_service.dart` | `app_behavior_settings.json` |
| 阅读会话 | `lib/services/reader_session_service.dart` | `reader_session.json` |
| 阅读背景配置 | `lib/services/reader_background_service.dart` | `reader_background.json` |
| 阅读背景图片 | `lib/services/reader_background_service.dart` | `reader_backgrounds/` |
| EPUB 书籍图片 | `lib/services/book_asset_store.dart` | `book_assets/` |

自定义字体目前通过 `getApplicationSupportDirectory()` 保存：

| 数据 | 当前实现 | 当前文件或目录 |
| --- | --- | --- |
| 字体配置 | `lib/services/app_font_service.dart` | `app_font_settings.json` |
| 字体文件 | `lib/services/app_font_service.dart` | `app_fonts/` |

阅读背景配置和字体配置目前保存绝对路径。目录迁移后，如果只复制文件、不重写配置，背景和字体会被判断为不存在并退回默认值。

### 3.2 当前数据库边界并不完整

`LibraryRepository` 已覆盖书籍、卡片、统计、资源元数据、阅读/收藏状态和删除书籍，是本次迁移的重要基础。但以下模块仍知道 Isar 的具体类型：

- `LibraryDataAccess` 保存具体的 `BookCardRepository`，并通过它取得 `Isar`。
- `BookImportService.importEpubBytes()` 直接接收 `Isar`，并直接执行查询和 `writeTxn`。
- `DataBackupService.exportBackup()` 和 `buildBackup()` 直接接收 `Isar`。
- `BookRemarkService` 自行打开第二个 Isar 实例。
- `IsarDb` 负责打开 Documents 中的默认 Isar，并在打开后触发资源清理。

因此不能只实现一个 SQLite 版 `LibraryRepository` 就直接删除 Isar。正式切换前还需要数据库无关的批量导入、备注、快照导出、恢复和生命周期契约。

### 3.3 当前启动顺序会绕过迁移门禁

`main.dart` 当前并行启动：

```text
initializeAppSettings()
loadLaunchState()
```

`loadLaunchState()` 会读取阅读会话，并可能通过 `LibraryDataAccess.instance` 打开主 Isar。如果保持该顺序，迁移页面显示前就可能打开或修改旧库，也可能让资源清理提前运行。

迁移版必须增加统一的 `AppBootstrapCoordinator`：先确定存储环境和迁移状态，再决定显示迁移页面（恢复/重试状态复用同一页面，见阶段四实施记录）或正常应用；迁移未完成前禁止创建正常的 `LibraryDataAccess`。

### 3.4 当前 EPUB 导入性能特点

当前导入链路已经具备以下有利条件：

- EPUB 只计算一次 SHA-256，并在写入前进行重复检测。
- 书籍、资源元数据和卡片在同一个 Isar 事务中提交。
- 卡片使用批量写入，而不是每张卡单独开启事务。
- EPUB 图片已采用逐张处理和落盘，不再同时长期保留全部图片 bytes。
- 资源目录在数据库提交失败时具有清理逻辑。

需要保留的用户体感是：文件选择后 UI 不冻结、解析进度可见、普通书籍导入时间不明显回退、导入失败不会留下可见的半本书。

SQLite 侧应使用单事务、prepared statement 和 batch insert。是否将卡片分成 500–2000 行的 batch 只影响绑定与内存管理，所有 batch 仍必须位于同一个事务中，避免产生部分导入。

### 3.5 当前备份能力的边界

当前 `DataBackupService.backupFormatVersion == 2`，备份包括：

- books
- bookCards
- bookAssets
- bookRemarks
- readerSession
- 实际存在的书籍图片

当前备份不包括：

- 行为设置
- 阅读背景配置和背景图片
- 字体配置和字体文件

此外，当前 ZIP 构建会把 JSON、各图片和最终 ZIP 都放入内存。小书库可用，但大图片书库可能产生较高内存峰值。因此本轮需要兼容现有 v2 恢复，同时定义 backend-neutral 的 v3 格式；恢复端出于安全限额需要流式解压，导出端如基准显示内存不可接受，再改为流式归档。

## 4. 目标架构

### 4.1 统一存储布局

引入 `AppStoragePaths` 或 `StorageLayout`，所有数据库、设置服务和资源服务都通过注入取得路径，不再各自调用 `path_provider`。

Windows 建议：

```text
Release: %LOCALAPPDATA%\Vanishia\FluidText
Debug:   %LOCALAPPDATA%\Vanishia\FluidText-Debug
Profile: %LOCALAPPDATA%\Vanishia\FluidText-Profile
```

这里是由 Windows 按当前登录用户展开的运行数据目录，例如 `C:\Users\<用户名>\AppData\Local\Vanishia\FluidText`，与源码目录及用户将 `FluidText.exe` 解压或安装到哪里无关。`Vanishia` 是 Windows 侧的发行者命名空间，不要求与现有 Android 包名一致，本轮不修改 Android application ID。

Android 建议：

- Release 使用正式包名对应的应用私有 support/files 目录。
- Debug 继续使用 `.debug` 包名和独立私有目录。
- Profile 增加 `.profile` 包名或等价 product flavor，避免与 Release 共用私有目录；当前已处理 Debug 与 Release 的包名/签名隔离，但 Profile 仍必须在本轮发布前单独验证。
- Android 只能迁移当前包名自身可访问的旧私有目录，不尝试跨应用沙箱读取 Release/Debug 数据。

Release 新目录建议布局：

```text
FluidText/
  fluidtext_library.sqlite
  fluidtext_library.sqlite-wal
  fluidtext_library.sqlite-shm
  settings/
    app_behavior_settings.json
    reader_session.json
    reader_background.json
    app_font_settings.json
  book_assets/
  reader_backgrounds/
  app_fonts/
  migration/
    state.json
    attempts/
  recovery/
```

约束：

- 数据库名称改为明确的 `fluidtext_library.sqlite`。
- 配置中只保存受控相对路径，例如 `reader_backgrounds/xxx.jpg`，运行时由 `StorageLayout` 解析。
- 禁止接受 `..`、盘符、UNC 路径、空 segment、控制字符或逃逸根目录的持久化相对路径。
- 所有资源读取、复制、备份、恢复和清理在词法校验后还必须做 canonical path 校验；遇到 symlink、junction 或其他 reparse point 默认跳过并记录 warning，不跟随到受管目录外。
- JSON 写入使用“同目录临时文件 → flush → 原子替换”，读取失败需要记录具体原因，不能只静默吞掉异常。
- `.sqlite-wal`、`.sqlite-shm` 是 SQLite 管理的数据库组成部分，不作为普通资源复制，也不能被用户手动当成可忽略缓存。备份、迁移提升和恢复切换前必须通过数据库生命周期接口 checkpoint、关闭连接并确认 staging 已密封；Isar `.lock` 是运行时文件，不复制。

Windows 上自动扫描真实 Documents 遗留数据只在 Release 启用。Debug/Profile 默认使用自己的空目录；测试迁移时通过注入 fixture 根目录运行，避免开发版本误处理真实用户数据。

### 4.2 数据访问分层

建议把当前单一 `LibraryRepository` 扩展为以下职责，具体可拆成多个接口，避免一个巨型 Repository：

```text
UI / ViewModel
      ↓
LibraryDataAccess（应用用例门面）
      ├─ LibraryReadRepository
      ├─ LibraryWriteRepository
      ├─ LibraryImportRepository
      ├─ RemarkRepository
      ├─ BackupSnapshotRepository
      └─ DatabaseLifecycle
               ↓
       SQLite/Drift 实现

Legacy Isar Reader 仅供：旧数据扫描、迁移、旧版备份导出
```

需要补充的数据库无关能力：

- 根据 `fileHash`、`contentFingerprint` 查询重复书籍。
- 对旧书补齐缺失身份字段。
- 在一个事务内写入 Book、BookCard、BookAsset。
- 备注 CRUD。
- 导出完整规范化快照。
- 从规范化快照在 staging 数据库中原子恢复。
- 开启、关闭、checkpoint、重新打开数据库。
- 执行完整性检查、计数和主外键校验。

当前 `toggleRead(BookCard)`、`toggleFavorite(BookCard)` 会直接修改传入模型。迁移时建议改为以 `cardId` 和目标状态为参数，并返回更新结果，减少 ORM 对象可变性泄漏，也便于事务和并发测试。

备份构建层不得直接持有 Isar 或 SQLite 连接。迁移页的“导出 ZIP 备份”必须先把 legacy Isar 复制到 staging，再由 `LegacyIsarBackupSnapshotRepository` 从副本生成 backend-neutral snapshot；SQLite 正常导出也通过 `SqliteBackupSnapshotRepository` 生成同一类 snapshot。ZIP 编码层只接收 DTO/snapshot，避免备份流程绕过“不碰旧原件”的迁移安全边界。

### 4.3 SQLite 技术选择与运行参数

首选 Drift + native SQLite，原因是：

- Flutter/Dart 类型映射、迁移版本和查询代码更容易测试。
- Windows 和 Android 均可使用成熟的 SQLite native runtime。
- 可以保留原始 SQL，用于复杂聚合、PRAGMA 和性能调优。
- schema migration 可显式版本化，不依赖私有二进制 schema 自动推断。

阶段一必须先做最小技术 spike，验证当前 Flutter/Dart 版本下的 Windows Release、Android Release、后台 isolate、文件路径和打包产物。若 Drift/native runtime 在任一目标平台不稳定，再评估 `sqlite3` 直接封装；不能在实现到一半时同时维护两套方案。

建议初始设置：

- `PRAGMA journal_mode = WAL`
- `PRAGMA foreign_keys = ON`
- 合理的 `busy_timeout`
- 数据库连接在后台 isolate 打开和执行大批量工作
- 普通运行候选 `synchronous = NORMAL`
- 迁移/恢复最终提交阶段使用更强的持久化设置并主动 checkpoint

`synchronous = NORMAL` 与 `FULL` 必须通过 Windows 和 Android 真机基准、强杀恢复测试后再最终确定。目标是数据库始终保持一致；即使最后一笔用户操作未落盘，也不能产生结构损坏或半次迁移。

若基准和强杀测试无法给出明确结论，默认选择 `synchronous = FULL`，只有在真实用户流程性能不可接受且恢复测试仍通过时才降级到 `NORMAL`。迁移、恢复、备份前密封数据库和发布前完整校验一律使用保守设置。

需要在阶段二固定连接模型：普通 UI 查询使用主数据库门面，批量导入、迁移和恢复在后台 isolate 中持有受控连接执行；同一时间只允许一个批量写入任务。若使用 Drift isolate-aware 连接或 `NativeDatabase.createInBackground()`，必须在 contract test 中覆盖主 isolate 读、后台 isolate 写、busy timeout 和关闭重开语义。

### 4.4 SQLite schema 初稿

#### `books`

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY，迁移时保留 Isar ID |
| `title` | TEXT | NOT NULL |
| `created_at_ms` | INTEGER | NOT NULL |
| `file_hash` | TEXT | NULL |
| `content_fingerprint` | TEXT | NULL |
| `source_file_name` | TEXT | NULL |
| `imported_at_ms` | INTEGER | NULL |
| `card_count` | INTEGER | NULL |
| `text_char_count` | INTEGER | NULL |
| `asset_root_key` | TEXT | NULL |

索引：`file_hash`、`content_fingerprint`、`created_at_ms DESC`。是否设置 UNIQUE 要先检查真实旧数据；重复数据不能因为新约束导致整库迁移失败。

#### `book_cards`

字段等价覆盖当前 `BookCard`：`id`、`book_id`、`book_title`、`card_index`、`chapter_index`、`chapter_card_index`、`chapter_title`、`content`、`blocks_json`、`is_read`、`read_at_ms`、`is_favorite`、`favorited_at_ms`。

`book_title` 是当前模型的历史冗余字段，本轮不能在未定义语义时照搬成长期一致性负担。实现前需要明确它是“导入时原书名快照”、还是应迁入 `books.original_title` / `books.display_title` 一类字段；如果只是为了保留原名并支持用户备注，优先在 `books` 与 `book_remarks` 上表达，不让每张卡重复维护标题。无论最终保留或移除，都必须保证旧数据中的原书名和备注迁移后不丢失。

约束与索引：

- `book_id REFERENCES books(id) ON DELETE CASCADE`
- `UNIQUE(book_id, card_index)`
- `(book_id, card_index)`
- `(book_id, is_read, card_index)`
- `(is_read, read_at_ms DESC, id DESC)`
- `(is_favorite, favorited_at_ms DESC, id DESC)`

#### `book_assets`

字段等价覆盖当前 `BookAsset`：`id`、`book_id`、`asset_key`、`original_href`、`normalized_href`、`mime_type`、`relative_path`、`byte_length`、`created_at_ms`。

约束与索引：

- `book_id REFERENCES books(id) ON DELETE CASCADE`
- `UNIQUE(book_id, asset_key)` 只有在真实旧数据扫描确认无冲突后启用；同一本书中不同 href 指向相同 bytes 时可能产生相同 `asset_key`，需要在迁移中去重或改用更合适的唯一约束。
- `(book_id, asset_key)`
- `normalized_href`

#### `book_remarks`

备注当前以 book ID 作为 Isar ID，SQLite 中应明确表达：

- `book_id INTEGER PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE`
- `title TEXT NOT NULL`
- `updated_at_ms INTEGER NOT NULL`

#### `storage_metadata`

至少保存：

- schema version
- storage format version
- 创建/升级时间
- 最近完整校验结果
- 来源迁移 fingerprint
- 迁移完成版本

迁移过程的临时状态仍保存在 staging 外部的 `migration/state.json`，避免“数据库没能打开却读不到失败状态”。

Drift 的 `schemaVersion` 是唯一 schema migration 来源；`storage_metadata` 只记录当前已应用版本、最近校验和迁移来源摘要，不另行发明一套会与 Drift 脱节的 schema 版本。未来 v2/v3 schema 升级必须通过 Drift migrator 和 contract fixture 验证，不再依赖一次性 Isar 大迁移。

通用约束：所有保留 Isar ID 的表都拒绝 `id <= 0`、重复 ID 和超出 SQLite INTEGER 安全范围的 ID；迁移/恢复后校准后续插入的 ID 分配，确保新导入书籍不会与旧 ID 冲突。布尔字段使用 0/1 CHECK，计数和 index 字段使用非负 CHECK，状态时间字段保持语义一致，例如 `is_read = 0` 时 `read_at_ms` 应为 NULL。

### 4.5 查询和用户体感保证

- 卡片顺序只由 `(book_id, card_index)` 确定。
- `loadCardsByIds()` 使用 `IN` 查询后，必须按调用者传入 ID 顺序重排；不能依赖 SQLite 返回顺序。
- 阅读页继续按需要读取卡片和上下文，不在打开一本书时一次反序列化所有 `content`。
- 书架统计改为一次 `GROUP BY book_id` 聚合，替代当前每本书分别执行 total/read/favorite 三次 count。
- 收藏和已读写入保持单行短事务，写完后再通知缓存失效。
- 大批量导入和迁移在后台 isolate 中执行，主 isolate 只接收节流后的进度事件。
- 首轮不维护 FTS，避免每张卡插入时产生额外索引开销。未来 FTS 应单独建表并在导入提交后异步构建。
- 时间字段保存 epoch milliseconds，并在涉及活动排序的查询中使用 `id DESC` 作为稳定 tie breaker；如果实测发现毫秒截断会改变现有排序，则改为 epoch microseconds。迁移测试必须同时验证“绝对时刻不变”和当前统计使用的本地日期语义不变，避免时区转换让阅读记录跨天。

## 5. 一次性迁移设计

### 5.1 启动状态机

`AppBootstrapCoordinator` 在任何正常 Repository 打开前判断：

| 状态 | 处理 |
| --- | --- |
| 无旧数据、无 SQLite | 初始化空 SQLite，正常启动 |
| SQLite 完整且完成标记有效 | 正常启动 |
| 有可信旧数据、无完整 SQLite | 显示迁移页面 |
| 有 staging 或上次失败状态 | 显示恢复/重试状态，不打开 staging 作为正式库 |
| 新旧数据共存且迁移标记有效 | 使用 SQLite，保留旧数据作为回滚备份 |
| SQLite 存在但校验或标记不完整 | 禁止正常启动，进入迁移页面的恢复模式 |

在迁移状态判定完成前，不得初始化会写回默认值的设置服务、阅读会话服务、字体/背景服务或普通 Repository。设置加载如果需要参与迁移页主题，只能以只读 legacy snapshot 方式读取；任何“读取失败后写默认值”的自愈逻辑必须等正常 SQLite 启动后再启用。

Windows 的 `default.isar` 不能仅凭文件名认定为 FluidText 数据。可信检测至少结合：

- FluidText 特有的伴随文件或资源目录。
- 文件时间、大小和来源目录记录。
- 把候选复制到 staging 后，使用 1.0.0/current legacy schema 尝试打开并校验 collection/字段。
- 不在原 Documents 文件上做会触发写入或 schema 变更的检查。

### 5.2 迁移步骤

1. 获取应用级单实例锁和迁移锁，阻止两个进程同时迁移或一个正常实例同时打开库。Windows 优先使用命名 Mutex 或等价文件锁，并保证进程崩溃后锁自动释放。
2. 枚举可信的旧数据库、设置和资源，确认源文件 size/mtime/hash 在短时间内稳定后，计算 source fingerprint。
3. 在目标磁盘的 `migration/attempts/<id>/` 创建 staging。
4. 完整复制旧 `.isar` 到 staging；不复制 `.lock`。
5. 使用 legacy Isar reader 打开副本，读取 books、bookCards、bookAssets 和 bookRemarks；大表按主键或 card index 分批读取，不一次性把全部 cards 放入内存。
6. 创建 staging SQLite，按保留原 ID 的方式写入数据；所有 batch 位于同一个迁移事务内。
7. 复制 `book_assets`、阅读背景和字体；只复制 regular file，不跟随 symlink/junction/reparse point，按文件字节计算 SHA-256。
8. 迁移行为设置和阅读会话，过滤已经不存在的 book ID。
9. 将背景、字体配置中的绝对路径改成受控相对路径；缺失文件回退默认并记录 warning。
10. 校验数据库结构、外键、数量、关键字段、状态、时间、资源 hash 和 SQLite 后续自增 ID 分配。
11. 关闭 legacy reader 和 staging SQLite，执行 `wal_checkpoint(TRUNCATE)` 或使用非 WAL staging journal，确保密封后的 staging 不依赖未复制的 WAL 帧。
12. 在同一目标磁盘内将 staging 原子提升为正式存储。
13. 写入包含 source fingerprint、schema version、计数和校验摘要的完成标记。
14. 重新打开正式 SQLite，执行一次只读 smoke test 后进入正常应用。

旧 Documents 数据全程不删除、不改名。首个 SQLite 大版本继续保留 Isar runtime，仅作为 legacy migration reader；待一个稳定版本周期后再单独决定是否移除依赖。

原子提升的实现必须避免覆盖式 rename。推荐流程是：正式目录不存在时，将已密封的 staging 目录在同卷内 rename 为正式目录；正式目录已存在但未完成时，先进入恢复状态，由恢复逻辑明确隔离旧正式目录和新 staging。Windows 上需要验证 Dart `Directory.rename()` / `File.rename()` 的底层行为；如需替换现有正式库，应使用平台侧可靠替换 API 或两阶段目录命名，而不是依赖覆盖大文件 rename。数据目录所在文件系统必须支持所需 rename/flush 语义；FAT/exFAT 或网络文件系统只允许在验证后支持，否则提示用户或记录发布限制。

### 5.3 数据异常处理策略

| 异常 | 策略 |
| --- | --- |
| Isar 副本无法打开或被截断 | 迁移失败，不碰原文件；显示重试与 ZIP 恢复说明 |
| `book_cards` 指向不存在的 book | 视为核心关系损坏，停止自动迁移并输出诊断摘要 |
| 重复 `(book_id, card_index)` | 停止自动迁移，避免静默改变卡片顺序 |
| orphan `book_assets` | 跳过并记录 warning，不让无主资源阻断全部文本数据 |
| orphan `book_remarks` | 跳过并记录 warning |
| 资源元数据存在但文件缺失 | 保留数据库记录并记录 warning；文本和状态继续迁移 |
| 资源路径指向 symlink/junction/reparse point | 不跟随，不复制；记录 warning，避免读取受管目录外文件 |
| 壁纸或字体绝对路径失效 | 回退默认颜色/系统字体并记录 warning |
| 旧 JSON 损坏 | 不覆盖原文件；使用默认值并在迁移结果中提示 |
| 源 Isar 文件复制前后 hash 不稳定 | 判定可能仍被旧实例或同步软件写入，停止迁移并提示关闭旧应用或稍后重试 |
| 目标磁盘空间不足 | 写入前估算、过程中捕获；删除本次 staging，保留旧数据 |
| 原子切换被杀进程或系统重启 | 下次根据 state 和完成标记识别，正式库不可见则重试 |

### 5.4 进度模型

进度必须来自实际阶段和计数，不使用只会自动走完的假进度条。建议事件：

```text
检测旧数据
复制数据库副本（按字节）
读取书籍
迁移卡片（已完成/总数）
迁移备注与资源元数据
复制书籍图片（已完成字节/总字节）
迁移设置、背景和字体
校验数据库与文件
完成切换
```

阶段权重应根据已知记录数和资源总字节动态计算。UI 更新需要节流，例如每 100–200 ms 一次，不能让每行 insert 都触发 Flutter rebuild。

## 6. 迁移页面与失败体验

检测到旧数据后，应用首页改为不可绕过的迁移页面，普通书架和阅读页尚不初始化。

页面状态：

1. `detected`：说明为什么迁移、旧数据位置和不会自动删除旧文件。
2. `exportingBackup`：复制旧库到 backup staging，通过 legacy snapshot facade 从副本导出 ZIP。
3. `ready`：备份成功后可开始迁移。
4. `migrating`：显示阶段、进度条、已处理数量和简短说明。
5. `validating`：明确显示正在校验，不让用户误以为卡死。
6. `success`：显示迁移结果和 warning 数量，进入应用。
7. `failed`：显示失败、错误编号、旧数据仍保留、重试、重新导出 ZIP 和备份恢复说明。

推荐交互：

- 主按钮一：`导出 ZIP 备份`。
- 主按钮二：`开始迁移`，默认在备份成功后启用。
- 为避免文件选择器或磁盘问题永久阻塞用户，可提供较弱的 `跳过备份并继续`，必须二次确认“旧数据仍会保留，但没有额外 ZIP 备份”。
- 迁移进行中禁止关闭页面内操作，但不能假设操作系统不会杀进程；真正的安全性由 staging 和完成标记保证。
- 迁移失败后仍留在迁移页面（失败/恢复状态均复用该页面），优先提供“重试迁移”和“导出 ZIP 备份”。直接进入空书架不作为主路径，只能作为显式放弃迁移的兜底操作，并需要二次确认。失败/恢复/不可信源状态下另提供灰色小字的“导入备份恢复”逃生入口（详见阶段五实施记录）。
- 失败文案至少包含：

```text
迁移失败
旧数据仍保留，未被删除。
你可以重试，也可以先导出 ZIP 备份；如果稍后重装应用或进入新书架，可使用“导入备份”恢复。
```

- 若用户显式放弃迁移并进入书架，必须创建或打开一份明确的空 SQLite，绝不能把部分 staging 当正式库。
- 进入空书架前再次说明“当前书架为空，旧 Isar 仍在原位置”，并在书架或设置中保留“重新检测旧数据并迁移 / 导入备份”的入口。
- 错误详情默认折叠，提供复制诊断信息按钮，但不能包含书籍正文、文件内容或完整个人路径。

## 7. ZIP 备份与恢复设计

### 7.1 兼容策略

- 必须支持导入当前 backup format v2，保证用户现在导出的 ZIP 可用于 SQLite 恢复。

> 实施记录（2026-08-14）：v2 导出的实际形态取决于是否有图片——书库无图片时导出为单个 `.json`（非 ZIP）；阶段五导入端必须同时接受 `.json` 与 `.zip`，不能只认压缩包。
- 新增 backend-neutral backup format v3，SQLite 和 legacy Isar 都先转换成相同 DTO，再交给归档层。
- v2 缺失行为设置、背景和字体，导入时应明确提示“核心书库已恢复，外观设置未包含在旧版备份中”。
- v3 才定义为完整应用备份。
- 迁移页导出的 legacy ZIP 也必须通过 staging 副本生成：不允许直接打开 Documents 中的原始 Isar，不允许复用需要业务层已打开 Isar 实例的旧备份入口。

### 7.2 v3 建议结构

```text
manifest.json
data/library.json 或规范化分片 JSON
settings/app_behavior_settings.json
settings/reader_session.json
settings/reader_background.json
settings/app_font_settings.json
book_assets/...
reader_backgrounds/...
app_fonts/...
```

`manifest.json` 至少包含：

- `format: fluidtext.backup`
- backup format version
- SQLite schema/storage version
- 导出应用版本和平台
- 导出时间
- books/cards/assets/remarks 数量
- 每个归档文件的相对路径、byte length、SHA-256

### 7.3 书架入口

当前 `BookshelfSheet` 顶部已有“导入 EPUB”和“导出备份”按钮。新增“导入备份”应放在相邻操作区；若顶部图标过密，可把备份导出/导入合并为菜单，但不在本轮顺带重做整个书架 UI。

### 7.4 首版恢复语义：原子替换

第一版不做 merge。恢复流程：

1. 用户选择 `.zip` 或兼容的旧 `.json`。
2. 非空书库弹出二次确认，说明恢复会替换当前书库。
3. 自动尝试导出当前书库作为恢复前保险；失败时要求用户确认是否继续。
4. 在解压前校验扩展名、manifest、版本、文件数量、总展开大小和路径。
5. 拒绝绝对路径、`..`、盘符、UNC 路径、ZIP Slip、symlink 条目、重复路径、大小写折叠后重复路径和 filename spoofing。
6. 在 `recovery/attempts/<id>/` 解压并校验 checksum。
7. 创建 staging SQLite，导入 DTO，校验外键、数量、资源和 session 引用；无效的 `reader_session` book/card 引用必须清空并回到书架首页。
8. 关闭当前数据库，密封 staging SQLite，原子交换正式数据与恢复数据。
9. 清理内存缓存和 Repository 单例，重新 bootstrap。
10. 失败时继续使用原数据库，删除或隔离失败 staging。

需要设置 ZIP bomb 防护：压缩包大小、展开总大小、单文件大小、文件数量、压缩比和嵌套归档均应有限制。限制值应由现有真实 EPUB/备份样本和目标设备空间确定，不在计划阶段拍脑袋固定。恢复端必须在流式读取/解压过程中执行限额，不能先把整个 ZIP decode 到内存后再检查。

ZIP 解析库必须固定到已修复公开安全漏洞的版本。实现恢复前需要确认 `archive` 包当前版本是否修复 filename spoofing 类问题；如无法直接确认，需要在归档层自行校验 Central Directory Entry 与 Local File Header 文件名一致性，并把不一致样本加入安全测试。

## 8. 性能与稳定性验收

### 8.1 基准数据集

对 Isar 当前版本和 SQLite 候选实现使用同一批数据：

- 100 cards：小书/冒烟。
- 1,000 cards：常见单书。
- 10,000 cards：大书或中等书库。
- 50,000 cards：压力书库。
- 无图片、少量图片、大量图片三类 EPUB。
- 当前真实 EPUB 测试样本。
- 从正式 tag `1.0.0` 生成的 Windows 遗留数据库 fixture。

### 8.2 需要测量

- 冷启动到可操作首页。
- 启动到迁移页面。
- 书架首次加载和再次加载。
- 读取 20/100 张指定卡片。
- 加载当前卡片前后文。
- 打开已读列表、收藏列表和统计页。
- toggle read/favorite 的 P50、P95。
- 导入 100/1,000/10,000/50,000 cards 的数据库写入耗时。
- EPUB 总导入耗时、主 isolate 卡顿、峰值 RSS。
- 旧库迁移总耗时、资源复制速度和峰值内存。
- v2/v3 ZIP 导出、校验、导入耗时和峰值内存。
- 强杀后的重启恢复时间。

### 8.3 平台矩阵

- Windows 11 普通 SSD，Release 构建。
- Windows Debug 只用于诊断，不作为性能结论。
- 一台中端 Android 真机，Release/Profile 构建。
- 数据目录位于 OneDrive Documents 的 Windows 场景，用于验证只读复制旧数据后不再在其中运行数据库。
- Windows `%LOCALAPPDATA%` 被企业策略重定向到网络盘或非 NTFS 文件系统的场景至少做检测和 warning；不把罕见环境作为首发阻断项，但不能静默声称已验证。

### 8.4 验收标准

在采集 Isar 基线前不承诺固定提升百分比。初始发布门槛：

- 正常规模书库的书架和阅读卡片加载无可感知回退。
- 关键查询 P95 原则上不超过 Isar 基线约 20%；超过时必须给出查询计划、原因和是否可接受的记录。
- EPUB 导入总耗时原则上不超过基线约 20%，且主 isolate 不出现持续可见卡顿。
- 50,000 cards 批量导入和大图片备份不 OOM，不产生半本书。
- 任意迁移阶段强杀后，下一次启动只能看到旧数据、完整新数据或迁移页面的恢复模式，不能看到部分数据。
- `PRAGMA integrity_check`、外键检查和应用级计数校验通过。

若 SQLite 数据库写入很快但 EPUB 解析占主要耗时，不应为了追求数据库基准数字重写解析器。只处理能改善真实用户总耗时或内存峰值的问题。

## 9. 分阶段实施与提交计划

整体拆为 6 个阶段，预计 16 次主提交；如果最终基准要求额外调优，阶段六再追加 1 次性能修正提交。每个阶段结束都应保持代码可构建、测试可运行，并形成可回滚边界。

### 阶段一：建立可测边界、存储布局和基线

**目标**

- 固化当前 Isar 行为和性能基线。
- 建立统一路径解析和环境隔离规则。
- 让文件服务可注入路径，但暂不把生产数据搬到新目录。

**改动边界**

- 新增 `StorageLayout`、build mode/environment 解析和路径安全工具。
- 调整数据库、设置、会话、资源、背景、字体服务的构造方式，使路径可注入。
- 正常运行默认仍使用当前 legacy 布局，直到阶段四原子切换。
- 从 tag `1.0.0` 的真实 schema 生成遗留 fixture；不能用当前 schema 假装旧版本。
- 建立 Isar 性能基线脚本和记录格式。

**预计影响模块**

- `lib/db/isar_db.dart`
- `lib/services/book_asset_store.dart`
- `lib/services/book_remark_service.dart`
- `lib/services/reader_*_service.dart`
- `lib/services/app_*_service.dart`
- `test/`、`tool/`
- Android build type 配置、Windows 路径解析

**不包含**

- 不创建生产 SQLite。
- 不复制或删除 Documents 中的数据。
- 不显示迁移页面。

**预计 3 次提交**

1. `补充 Isar 性能基线和1.0.0遗留数据夹具`
2. `建立统一应用存储布局和环境隔离`
3. `将文件服务改为可注入的存储路径`

**验证**

- 当前全部测试通过。
- Windows/Android Debug、Profile、Release 路径单测通过。
- 当前应用行为和数据位置不变。
- fixture 能由 legacy reader 打开并得到预期数量和字段。

**回滚点**

此阶段只增加抽象、fixture 和测试；任何回归可整体回滚，不涉及用户数据格式变化。

### 阶段二：建立 SQLite schema 与 Repository 实现

**目标**

- 验证 Drift/native SQLite 双端可用。
- 实现等价的 SQLite 查询和写入能力。
- 先在测试和开发开关下运行，不切换正式用户。

**改动边界**

- 引入 Drift/native SQLite 依赖。
- 定义 schema v1、索引、外键、数据库版本和 PRAGMA。
- 实现 SQLite 版读取、状态更新、删除、统计、资源查询。
- 扩展 Repository contract，固定顺序、事务和错误语义。
- 统计只做等价聚合，不改统计 UI 或业务口径。

**预计影响模块**

- `pubspec.yaml`
- 新增 `lib/storage/sqlite/` 或等价目录
- `lib/repositories/library_repository.dart`
- `lib/repositories/library_data_access.dart`
- Repository contract tests

**不包含**

- 不改 EPUB 解析逻辑。
- 不实现旧数据迁移。
- 不让 Release 默认读取 SQLite。
- 不增加 FTS。

**预计 3 次提交**

1. `验证 Drift 双端运行并定义 SQLite 初始结构`
2. `实现 SQLite 版 LibraryRepository`
3. `补充 SQLite 事务外键和 Repository 契约测试`

**验证**

- Isar 和 SQLite 实现运行同一套 Repository contract。
- 验证事务 rollback、外键、cascade、唯一约束和时间转换。
- Windows/Android Release 构建成功并能打开空 SQLite。
- 对关键查询执行 `EXPLAIN QUERY PLAN`，确认使用预期索引。
- 验证 Drift schemaVersion、`storage_metadata` 记录和未来 schema migration fixture 的关系。
- 验证主 isolate/后台 isolate 连接模型、busy timeout、关闭重开和同一时间单批量写入约束。

**回滚点**

SQLite 尚未成为生产数据源，删除新实现和依赖即可回到 Isar。

### 阶段三：解耦导入、备注、备份和数据库生命周期

**目标**

- 清除正常业务链路对具体 Isar 实例的依赖。
- 让 EPUB 能以同一用例写入 Isar 或 SQLite。
- 为迁移页的 legacy 导出和后续 ZIP 恢复准备统一快照模型。

**改动边界**

- 将 EPUB 解析结果改成 backend-neutral import draft/DTO。
- 数据库层负责重复查询、legacy 字段 backfill 和单事务批量写入。
- 将备注并入统一 Repository 契约，SQLite 中进入主库。
- 将备份导出改成从 `BackupSnapshotRepository` 读取 DTO。
- 增加显式 close/reopen/checkpoint 和缓存清理能力。
- 增加 migration backup facade：迁移前备份从 legacy staging 副本生成，不打开 Documents 原 Isar。
- 保留当前解析、图片 staging、重复判断和卡片切分语义。

**预计影响模块**

- `lib/services/book_import_service.dart`
- `lib/services/data_backup_service.dart`
- `lib/services/book_remark_service.dart`
- `lib/repositories/library_data_access.dart`
- 书架和阅读状态更新调用点

**不包含**

- 不迁移用户数据。
- 不增加 ZIP 导入 UI。
- 不删除 legacy Isar 实现。

**预计 3 次提交**

1. `将 EPUB 导入改为数据库无关的批量事务`
2. `将备注和状态写入收口到 Repository`
3. `将备份导出改为数据库无关的快照流程`

**验证**

- 同一个真实 EPUB 分别导入 Isar/SQLite 后，书籍、卡片、blocks、资源和重复检测结果一致。
- 任一批量写入中途抛错，SQLite 中不存在半本书，staging 资源被清理。
- 导入 100–50,000 cards 的基准与峰值内存记录完成。
- 当前 v2 导出内容保持兼容，已有备份集成测试继续通过。

> 实施记录（2026-08-14）：批量导入回滚测试已补入 `test/repositories/sqlite_library_repository_test.dart`；导入基准由 `tool/sqlite_import_benchmark.dart` 驱动（仓储层依赖 Flutter 无法 `dart run`，改用 `FLUIDTEXT_SQLITE_BENCHMARK=1 flutter test test/sqlite_import_benchmark_test.dart`），报告写入 `build/reports/sqlite_import_benchmark.json`，首轮 Windows 结果：50,000 cards 导入约 1.7s、RSS 增量约 28MB。

**回滚点**

生产仍可配置为 Isar；若 SQLite 导入未达标，可只回滚 SQLite adapter，不回滚已经验证的业务解耦。

### 阶段四：实现 Isar → SQLite 迁移引擎和迁移页面

**目标**

- 合并完成 Windows Documents 修复和数据库迁移。
- Android/Windows 旧用户可安全升级。
- 任意失败或强杀都不损坏旧数据，也不暴露部分新数据。

**改动边界**

- 实现 legacy source detection、Isar 副本读取、staging、资源复制、路径重写、校验和原子提升。
- 实现 bootstrap 状态机，阻止迁移前打开正常数据库。
- 增加迁移页面、备份按钮、真实进度、重试、warning 和失败提示。
- Release 正式切换到 SQLite 新写入；旧 Isar 原件不打开、不修改且保留。
- 完成迁移标记与崩溃恢复。

**预计影响模块**

- `lib/main.dart`
- `lib/features/bookshelf/launch_page.dart` 或新的 bootstrap/migration 页面
- 新增 `lib/migration/`
- `StorageLayout`、legacy Isar reader、SQLite lifecycle
- Windows/Android 平台配置

**不包含**

- 不删除旧数据。
- 不删除 Isar 依赖。
- 不做 ZIP 导入；此阶段单独完成后不能作为正式发布候选，必须等阶段五接通恢复入口。
- 不做 FTS。

**预计 4 次提交**

1. `实现旧 Isar 数据扫描和 staging 副本读取`
2. `实现分批迁移写入和资源路径重写`
3. `增加迁移校验原子切换和崩溃恢复`
4. `增加数据迁移页面和真实进度状态`

**验证**

- 迁移 tag `1.0.0` Windows fixture、当前 Isar fixture、Android legacy fixture。
- 比较 books/cards/assets/remarks 数量、全部 ID、卡片顺序、已读/收藏状态、时间和资源 hash。
- 在每个迁移阶段注入异常或强杀，再次启动结果符合状态机。
- 测试旧 JSON 损坏、资源缺失、路径失效、磁盘不足和同名非 FluidText `default.isar`。
- 测试源 Isar 复制前后 hash 不稳定、旧实例占用、symlink/junction/reparse point 资源和非 NTFS/网络数据目录 warning。
- 实机确认 Documents 中旧文件未被修改，新数据库只在目标私有目录运行。

> 实施记录（2026-08-14）：freshInstall 与放弃迁移会写入 `source=fresh` 的完成标记；`verifyLiveDatabase` 只校验 integrity/外键/schema version，不再比对表计数——否则迁移后用户正常写入会让计数失配，把正常启动误判成 recoveryRequired。真机验收发现早期版本（无章节字段）导入的卡片在 Isar 中读回 int64 最小值哨兵，迁移时已归一化为第 0 章并记 warning；迁移诊断会剥离 SQL 语句与绑定参数，避免泄露卡片正文。

> 实施记录（2026-08-15，迁移前台通知防杀）：迁移页的「导出 ZIP 备份」与「开始迁移」期间，Android 上挂起 dataSync 前台服务通知（`MigrationForegroundService`，通道 `fluidtext/migration_service`，Dart 侧 `MigrationNotificationService`，进度文本与页面节流同步更新）。与 EPUB 导入的普通常驻通知不同，这里是真正的 foreground service——一次性迁移数据量大、被杀后只能整体重试，需要提升进程优先级防后台回收；staging + state.json 的强杀兜底不变。前台服务无法防御用户主动划掉任务（Flutter engine 随 Activity 销毁），该场景仍由下次启动的恢复流程兜底。Windows 上为 no-op。已加入检查清单 2.2 的真机验收项。
>
> 实施记录（2026-08-15，措辞澄清）：不存在独立的「恢复页面」——`recoveryRequired` 状态复用迁移页面渲染（`MigrationPage`，文案换为「迁移需要继续」并提供「重新检测并迁移」「放弃迁移并进入空书架」），设计文档中出现的「恢复页面」均指该复用模式。
>
> 实施记录（2026-08-15，迁移页导入备份逃生入口）：迁移页在失败（failed）、恢复（recoveryRequired）与不可信源（migrationUnavailable）三种卡住状态下，显示灰色小字入口「已有备份文件？导入备份恢复」；首次正常迁移流程（detected/migrationRequired）不显示，避免稀释「先备份再迁移」主路径。点击后二次确认（说明旧数据不受影响），经 FilePicker 选择 v2 `.json`/`.zip` 或 v3 `.zip`，由 `BackupRestoreService` 恢复到 target layout（此状态下无活数据库，`closeLiveDatabase` 为 no-op），恢复期间挂迁移前台服务通知；成功后走 `onEnterApp` 正常进入应用，失败留在原状态仅以 SnackBar 提示。配套修改恢复端：`_refreshCompletionMarker` 在 marker 缺失时写入 `source=restore` 的初始完成标记，并把 `migration/state.json` 归位 idle——否则迁移页恢复成功后下次启动会因「库存在但无标记/残留 failed 状态」再次落入 recoveryRequired 死循环。正常路径（已有 marker）行为不变：保留原 source 与 fingerprint，仅刷新计数。回归测试：`migration_page_test.dart`（入口显隐、确认/取消、成功进入应用、失败留在页面）与 `backup_restore_service_test.dart`（无标记写初始标记+state 归位、有标记保留 source）。

**回滚点**

发布前可关闭 SQLite bootstrap 开关回到 Isar。发布后若需要应用级回滚，只允许通过明确的旧版兼容策略或 ZIP 恢复，不能让旧版本直接打开已迁移的 SQLite。

### 阶段五：实现 ZIP v2/v3 恢复与书架入口

**目标**

- 让迁移前导出的现有 ZIP 能恢复到 SQLite。
- 提供完整的新版备份闭环。
- 给迁移失败用户一条不依赖 Isar 自动迁移的恢复路径。

**改动边界**

- 实现 v2 parser 和字段规范化。
- 定义并导出 v3 manifest、checksum、设置和所有受管资源。
- 实现 ZIP 安全校验、流式限额解压、staging restore、完整校验和原子替换。
- 在 `BookshelfSheet` 增加导入备份入口和状态反馈。
- 非空库恢复前自动备份并二次确认。

> 实施记录（2026-08-14）：阶段四后 `BookRemarkService`/`IsarDb` 已无业务调用点，但在 active=target 布局下被误调会在新目录静默打开空 Isar；本阶段开始时先给这两个类加 assert 兜底或直接移除。

**预计影响模块**

- `lib/services/data_backup_service.dart` 或拆分后的 archive/restore 服务
- `lib/features/bookshelf/bookshelf_sheet.dart`
- `StorageLayout`、SQLite lifecycle、设置服务
- 备份 fixture 与安全测试

**不包含**

- 不实现两个书库 merge。
- 不允许选择性覆盖单本书。
- 不导入未知的新格式后猜测字段。

**预计 2 次提交**

1. `升级备份格式并兼容版本2恢复`
2. `在书架增加 ZIP 备份恢复入口`

**验证**

- v2 ZIP/JSON 导入 SQLite 后与原快照一致。
- v3 执行 Isar/SQLite → ZIP → 空 SQLite round-trip。
- 非空库替换恢复失败时，原库和原资源仍可正常打开。
- ZIP Slip、checksum 错误、截断 ZIP、超限文件、重复路径和 ZIP bomb 防护测试通过。
- 恢复后清空缓存并重新加载书架、阅读会话、背景和字体。

**回滚点**

ZIP 恢复入口可单独关闭，不影响已完成的 SQLite 迁移和正常读写。

> 实施记录（2026-08-13，提交一「升级备份格式并兼容版本2恢复」）：
>
> - v3 归档结构按 7.2 落地：`manifest.json`（format/version=3/sqliteSchemaVersion/appVersion/platform/exportedAt/counts/files，files 收录除 manifest.json 外每条目的 path/bytes/sha256）、`data/library.json`（backend-neutral DTO，键名与 v2 完全一致，仅去掉 format/version/exportedAt 头）、`settings/` 下四个设置 JSON（存在才收录、原样读入）、`book_assets/`（snapshot 引用且实际存在、路径安全的文件）、`reader_backgrounds/` 与 `app_fonts/` 下全部 regular file（跳过 symlink 并记 warning）。书架「导出备份」已切换为 v3 ZIP；v2 导出（`DataBackupService`）保持原样，legacy 迁移页继续使用。
> - 恢复入口同时接受 v2 `.json`（无图书库的直出 JSON）与 `.zip`（按扩展名+魔数判定；ZIP 内有 `manifest.json` 走 v3，否则找 `backup.json` 走 v2）。恢复语义为原子替换：staging SQLite 单事务写入并校验 integrity/外键/counts，密封（checkpoint(TRUNCATE)→close→删 -wal/-shm，逻辑与 `MigrationPromotion.seal` 同语义，抽为 `SqliteSealer`）后关闭正式库，再把正式条目 rename 进 `recovery/attempts/<id>/previous/`、payload rename 进 root，失败从 previous 回滚。
> - ZIP 安全层（`ZipSecurity`）不依赖 archive 包内部行为：用 `RandomAccessFile` 自解析 EOCD 与 Central Directory，并逐一比对 CDE 与 Local File Header 文件名（防 filename spoofing）；拒绝加密条目、symlink 条目（externalAttributes 高 16 位 0xA000）、绝对路径/盘符/UNC、`..`/`.`/空 segment、控制字符、重复路径与大小写折叠重复；拒绝多卷与 ZIP64。限额：压缩包 ≤2GB、解压总大小 ≤4GB、单文件 ≤512MB、条目数 ≤100000、单条压缩比 ≤100（仅解压大小 >1MB 时检查，避免小 JSON 误伤；deflate 对重复内容极限约 1032:1，真实图片几乎不可再压缩，100 足够拦截 ZIP bomb）。解压经 `decodeStream` 逐条目进行，同一时刻内存只持有一个文件的 bytes，写盘前再经 `StoragePathSafety` 与目录包含校验防 ZIP Slip。
> - 阶段五预备：删除已无调用点的 `BookRemarkService`；`IsarDb.isar` 增加运行时兜底——active 布局非 legacy 时直接抛 `StateError`，避免在新数据目录静默创建空 `default.isar`（forceIsar 回滚路径会先重置为 legacy 布局，不受影响）。
> - 书架「导入备份」入口、非空库二次确认与恢复前自动备份在提交二实施。
>
> 实施记录（2026-08-13，提交二「在书架增加 ZIP 备份恢复入口」）：书架顶部操作区新增「导入备份」（`Icons.settings_backup_restore_rounded`），接通 7.3/7.4 交互——FilePicker 选择 `.zip`/`.json`、非空库二次确认（「恢复备份将替换当前书库（X 本书），是否继续？」）、恢复前经 `PreRestoreBackup` 自动导出 v3 保险备份到 `recovery/pre-restore-<时间戳>.zip`（失败时弹窗由用户选择继续或取消、空库跳过）、BlockingLoader 期间禁用全部操作、成功后重建 `LibraryDataAccess` 单例并刷新书籍/备注/统计，失败文案含「当前书库未受影响」。恢复编排通过构造参数注入（picker/保险备份/restore runner/dataAccessLoader），widget 测试以 fake repository 覆盖确认对话框、busy 禁用、成功/失败文案与保险备份失败分支。
>
> 实施记录（2026-08-14，真机回归修复）：1.0.0 导出的 v2 备份中，早期版本（无章节字段）卡片的 chapterIndex/chapterCardIndex 是 Isar 的 int64 最小值哨兵，恢复时触发 SQLite CHECK 失败——恢复端现按迁移引擎同样的规则归一化为第 0 章并聚合记一条 warning；同时 staging 写入失败的用户可见错误会剥离 SQL 语句与绑定参数（含卡片正文），只保留约束名等安全信息。回归测试：`backup_restore_service_test.dart` 的 sentinel 归一化与错误脱敏用例。
>
> 实施记录（2026-08-14，恢复进度与内存基准）：恢复流程新增真实进度（`BackupRestoreProgress`，阶段权重固定：解压按中央目录声明的解压字节、写库按记录数分 2000 条 chunk、资源按文件数，发射端按 0.01 节流），书架恢复期间经 `BlockingLoader(label, progress)` 显示进度条与百分比；staging 写入改为同一事务内分 chunk batch。恢复内存基准（`FLUIDTEXT_RESTORE_BENCHMARK=1 flutter test test/backup_restore_benchmark_test.dart`，报告写入 `build/reports/backup_restore_benchmark.json`）首轮 Windows 结果：v2 JSON 最坏场景（整库单 JSON 一次解码）10,000 cards（9.5MB 备份）峰值 RSS 增量约 12MB、1.1s；50,000 cards（47MB 备份）约 40MB、3.4s，峰值量级约为备份 JSON 大小的 1–2 倍，无 OOM 风险；更大书库的流式 JSON 解析留作阶段六候选优化。
>
> 实施记录（2026-08-15，recovery 目录防累积）：修复审查报告 P2——失败 restore 的 `recovery/attempts/<id>/` 只增不清（v3 单次失败最坏解压+payload 两份资源），反复导入损坏/超限备份会写满私有目录，恰好破坏 ZIP bomb 防护想保护的东西；`recovery/pre-restore-*.zip` 存在完全相同的无界累积。新增 `BackupRestoreService.pruneRecoveryArtifacts`，在每次 `restore()` 开始（staging 本次 attempt 之前）执行：清掉全部旧 attempt（本次 attempt 即将成为最新现场，`keepNewestAttempts: 0`；独立调用默认保留最近 1 个供诊断）与旧 pre-restore zip（固定保留最新 1 个——书架流程先写新 zip 再进 restore，它是恢复后用户反悔的回退点）。安全边界：`previous/` 非空的 attempt 一律跳过不删——swap 回滚也失败时它可能是原库最后一份副本（即报告 P3 场景），常见失败（校验/校验和/写库错误）都发生在 swap 之前、无 previous、不受影响；删除 best-effort（单项失败仅记 `AppLogger`，如 Windows 文件被锁），绝不阻断恢复本身。attempt id 为固定 16 位 UTC 微秒时间戳，字典序即时间序，天然免疫时钟回拨排序歧义。修复后 `recovery/` 占用收敛为常数：≤1 个失败 attempt + 1 个最新 pre-restore zip + 进行中 attempt。测试：`backup_restore_service_test.dart` 新增 prune 单元（保留最新 attempt、跳过 previous 持有者、zip 保留最新且不动无关文件）与 restore 集成（进入 restore 前清旧 attempt 与旧 zip、失败后新 attempt 留存）三个用例，全量 232 通过。
>
> 实施记录（2026-08-17，恢复后外观设置热重载）：书架「导入备份」成功后原先只重建 `LibraryDataAccess` 并刷新书籍列表，背景/字体/行为等外观设置仍停留在启动时读入内存的值——恢复的外观要重启应用才生效，且运行中的旧值可能被回写覆盖刚恢复的设置文件（真机复现：恢复约两分钟后 `reader_background.json` 被内存默认值覆盖回纯色）。现恢复成功后追加调用 `initializeAppSettings()` 重新加载设置：app 树的主题色/背景/字体全走 `ValueNotifier`，自定义字体经 `FontLoader` 运行时注册，恢复的外观立即生效、无需重启，旧值回写也无从发生。`BookshelfSheet` 相应新增 `settingsReloader` 注入参数（与既有 IO 注入同模式），widget 测试补「恢复成功后必须重载设置」断言。书架底部说明文案同步修正：明确 v3 备份包含阅读背景与导入字体、v2 旧备份不含（原文案「包含外观设置与阅读背景」未区分版本，导入 v2 时对用户有误导）。

### 阶段六：双端验收、性能调优和发布保护

**目标**

- 完成迁移发布前的全量验证。
- 只根据基准修正查询、batch、PRAGMA 和归档内存问题。
- 明确发布和回滚操作手册。

**改动边界**

- 补齐 Windows/Android integration test 和 Release build 验证。
- 对慢查询增加或调整索引。
- 选择最终 batch size、isolate 边界和 synchronous 策略。
- 恢复端保持流式限额解压；若 ZIP 导出内存超标，再改为流式归档。
- 增加迁移诊断日志脱敏、发布检查清单和用户说明。

**预计影响模块**

- 查询实现与索引 migration
- benchmark/integration tests
- Windows/Android build 和发布文档
- 可能的 streaming archive adapter

**不包含**

- 不新增产品功能。
- 不在性能阶段顺带做 UI 重构。
- 不删除旧 Isar 和 Documents 备份。

**预计 1 次主提交，必要时追加 1 次性能修正提交**

1. `补齐 Windows 和 Android 迁移验收与发布保护`
2. `完成 SQLite 性能基准和查询调优`（仅在基准要求改动时）

**验证**

- 全部单元、契约、集成、安全和强杀恢复测试通过。
- Windows Release、Android Release 构建安装验证通过。
- 真实升级：1.0.0 → 迁移版，覆盖安装后数据完整。
- Debug/Profile/Release 数据互不读写。
- 性能报告满足第 8 节门槛，偏差均有记录和结论。

**回滚点**

发布产物生成前保留上一正式版本、迁移前 ZIP 和旧 Isar。发布后不自动执行反向 SQLite → Isar 迁移，恢复依赖 ZIP 和保留的旧数据。

> 实施记录（2026-08-14，阶段六提交一「补齐 Windows 和 Android 迁移验收与发布保护」）：
>
> - 迁移诊断脱敏收口为共享工具 `lib/services/diagnostic_sanitizer.dart`：`sanitizeDiagnosticText` 剥离 SqliteException 的 `Causing statement`/`parameters:` 段，并按最长优先把绝对路径替换为 `<staging>`/`<legacy>` 等根标记；`LibraryMigrator`、`MigrationPromotion`、`BackupRestoreService` 三处私有实现已改为调用共享工具，新增 `test/services/diagnostic_sanitizer_test.dart`。
> - synchronous 策略定稿为 FULL（§4.3 保守默认：双端强杀恢复基准给出明确结论前不降级 NORMAL），改动点仅 `configureSqlite` 一处。
> - 新增 `test/storage/library_database_test.dart`：文件库 PRAGMA 断言（WAL、`foreign_keys=1`、`busy_timeout=5000`、`synchronous=FULL`）与关键查询 `EXPLAIN QUERY PLAN`（未读排序、已读/收藏活动列表、上下文区间、重复检测身份索引、统计聚合均命中预期索引，无全表扫描）。
> - 新增 `docs/sqlite_release_checklist.md`：发布检查清单、真机/手动验收矩阵、回滚操作手册与用户说明要点；版本号 bump 列为发布时步骤。
> - batch size 与 isolate 边界定稿维持现状：迁移写入 500、恢复写入 2000、导入按书单事务 batch，连接经 `NativeDatabase.createInBackground` 在后台 isolate；基准数字见提交二实施记录。
>
> 实施记录（2026-08-14，阶段六提交二「完成 SQLite 性能基准和查询调优」）：
>
> - 补齐 Isar 全量基线：100/1,000/10,000/50,000 cards → `build/reports/isar_baseline.json`；新增 v3 导出内存基准 `tool/backup_export_benchmark.dart`（`FLUIDTEXT_EXPORT_BENCHMARK=1 flutter test test/backup_export_benchmark_test.dart`），报告写入 `build/reports/backup_export_benchmark.json`。
> - Windows 首轮数字（`synchronous = FULL`）：导入 50,000 cards 约 1.34s、RSS 增量约 26MB；`loadCardsByIds(100)` 4ms 优于基线 23ms；`loadBookStats` 34ms 对基线 18ms（单书 50,000 行单次 GROUP BY 对每书 3 次 count，口径不同，绝对值可接受）；`toggleRead` 14ms 对基线 6ms（FULL fsync 的单笔提交开销，P95 绝对值远低于可感知阈值，结论：接受，不降级 NORMAL）。
> - 唯一超 20% 门槛项：`loadOrderedCardIds` 50,000 行约 115ms 对 Isar 基线 10ms。原因：后台 isolate 行传输与打开书籍时单次全量 id 读取；`EXPLAIN QUERY PLAN` 确认命中 `idx_book_cards_book_order`，无全表扫描；每本书打开一次、绝对值百毫秒级，书架与阅读体感无可感知回退，结论：接受并记录，不为该指标改写查询。
> - 恢复基准复测（FULL）：10,000 cards 约 1.1s、峰值 RSS 增量约 17MB；50,000 cards 约 3.1s、约 50MB，与阶段五记录同量级。
> - 导出基准：10,000 cards + 20 张 256KB 图片约 0.98s、峰值 RSS 增量约 53MB；50,000 cards 约 3.2s、约 226MB（内存归档峰值约为未压缩 payload 的 2–3 倍），无 OOM。结论：维持内存归档，大图库真机 OOM 验收列入 `docs/sqlite_release_checklist.md` §2.4，超标再改流式归档。
> - 结论：本轮无需索引、batch 或 PRAGMA 调优改动，不追加性能修正提交。

## 10. 测试计划

### 10.1 单元测试

- `StorageLayout` 的 Windows/Android、Debug/Profile/Release 路径。
- 相对路径规范化、路径逃逸拒绝和绝对路径重写。
- Isar model ↔ migration DTO ↔ SQLite row 的字段映射。
- `DateTime` epoch 转换、本地日期语义。
- 迁移状态机的所有输入组合。
- source fingerprint 和完成标记验证。
- SQLite 自增 ID 校准、毫秒时间 tie breaker 和 CHECK 约束。
- 进度权重、节流和错误状态。
- v2/v3 backup parser、manifest、checksum 和版本拒绝。
- 路径 canonical 校验、symlink/junction/reparse point 拒绝和日志脱敏工具。

### 10.2 Repository 契约测试

同一套测试分别运行 Isar 和 SQLite：

- 书籍加载及传入顺序保持。
- 卡片 ID、未读卡、上下文和排序。
- 已读/收藏切换和时间戳。
- 阅读/收藏活动事件。
- 统计聚合。
- 资源 key 查询。
- 删除书籍 cascade。
- 备注 CRUD。
- 批量导入事务成功与 rollback。
- 快照导出与原子恢复。

### 10.3 数据库集成测试

- SQLite schema v1 创建、重开和升级预留。
- WAL、foreign key、busy timeout 和 checkpoint。
- `wal_checkpoint(TRUNCATE)` 后密封数据库不依赖 `.sqlite-wal`，恢复重开后数据完整。
- 数据库被占用时的错误与重试。
- 事务中途抛错不产生部分写入。
- `integrity_check` 与 `foreign_key_check`。
- 大量参数的 `IN` 查询分批及顺序重排。
- 主 isolate/后台 isolate 连接模型、并发读写和单批量写入互斥。

### 10.4 EPUB 集成测试

- 当前真实 EPUB 样本导入 SQLite。
- 无图、单图、多图、超大图和缺图 EPUB。
- 重复文件 hash、相同内容不同文件、legacy identity backfill。
- 数据库提交失败后的资源清理。
- 进程退出前后书籍可见性。

### 10.5 迁移集成测试

- tag `1.0.0` 生成的 Windows Isar fixture。
- 当前版本 Isar fixture。
- Android legacy 私有路径 fixture。
- 空库、单书、多书、大书库。
- 独立备注库存在/缺失/损坏。
- 旧锁文件存在，但不被复制。
- 阅读背景、自定义字体和绝对路径改写。
- 旧配置缺失或 JSON 截断。
- 资源缺失、hash 不符、目标磁盘空间不足。
- 源 Isar 被旧实例或同步软件持续写入导致 hash 不稳定。
- 资源目录内存在 symlink、junction 或 reparse point。
- 在复制、读取、写 cards、复制资源、校验、切换、写标记各阶段模拟强杀并重启。
- Documents 中存在无关 `default.isar`，不得误迁移。
- 大书库迁移分批读取，不因一次性 DTO 堆积造成峰值内存失控。

### 10.6 ZIP 恢复和安全测试

- v2 JSON、v2 ZIP、v3 ZIP round-trip。
- manifest 缺失、版本过新、checksum 不匹配、文件截断。
- ZIP Slip、绝对路径、`..`、盘符、UNC、重复文件名、大小写折叠重复路径、Local Header/Central Directory 文件名不一致、symlink 条目。
- 单文件/总大小/文件数/压缩比限制。
- 非空库替换确认和恢复前自动备份。
- 恢复中途失败或强杀，原库仍可使用。
- 恢复后 reader session 引用不存在的 book/card 时自动清空并回到书架。

### 10.7 UI 与构建验证

- 无旧数据不显示迁移页。
- 有旧数据只显示迁移页，不初始化书架 Repository。
- 导出取消、导出失败、跳过备份确认。
- 进度文字和进度条对应真实事件。
- 失败文案、重试、重新导出 ZIP、显式放弃迁移、重新检测旧数据和导入备份。
- 书架 ZIP 导入入口的 busy 状态和错误状态。
- Windows Release 与 Android Release 构建、覆盖安装和数据验证。

## 11. 主要风险与处理策略

### 11.1 Drift/native SQLite 双端打包问题

**风险：** Windows DLL、Android ABI、后台 isolate 或 Release tree shaking 可能出现只在正式构建暴露的问题。  
**处理：** 阶段二先完成最小双端 Release spike，验证打开、写入、重开和事务，再继续大规模实现。

> 实施记录（2026-08-14）：阶段四构建验收时发现 `sqlite3_flutter_libs 0.6.0+eol` 是不含原生库的空壳版本（包自述要求改用 sqlite3 3.x），已固定到 `0.5.42`；Windows Release 已验证随包 `sqlite3.dll`、Android APK 已验证含三个 ABI 的 `libsqlite3.so`。后续如需更新，可评估 sqlite3 3.x 的 native assets 方案。

### 11.2 SQLite 导入速度不及 Isar

**风险：** 每行独立执行、频繁事务、同步统计或 FTS 会放大差距。  
**处理：** 单事务 + prepared/batch insert；重复检测前置；FTS 延迟；UI 进度节流；基于真实总导入时间调优，而不是只测空表 insert。

### 11.3 迁移被杀或原子切换失败

**风险：** Windows 文件占用、杀后台、系统重启可能留下 staging。  
**处理：** 正式目录外 staging、显式关闭数据库、checkpoint、同卷非覆盖 rename、完成标记、有限重试；下次启动只依据完整标记使用新库。Windows 上发布前验证 rename/replace API 行为，FAT/exFAT 或网络文件系统不静默宣称支持。

### 11.4 旧 Isar 与实际 schema 不一致

**风险：** 1.0.0、当前开发版或异常用户数据字段不同。  
**处理：** 保留 versioned legacy reader；至少测试 1.0.0 和当前 schema；读取副本；未知 schema 不自动修改原文件。

### 11.5 Windows `default.isar` 误识别

**风险：** Documents 中可能有其他应用同名文件。  
**处理：** 伴随文件 + 副本 schema/content 校验 + source fingerprint；只在 Release 自动扫描；识别不充分时要求用户选择 ZIP，不猜测迁移。

### 11.6 绝对路径失效或路径逃逸

**风险：** 背景/字体迁移后丢失，恶意备份写到应用目录外，或 symlink/junction 诱导读取应用目录外文件。  
**处理：** 迁移时复制并改相对路径；运行时只从存储根解析；ZIP 导入严格拒绝绝对路径、`..`、symlink 条目和 canonical path 逃逸。

### 11.7 备份 ZIP 内存峰值

**风险：** 当前 `archive` 方案会同时持有多份 bytes，大图库可能 OOM。  
**处理：** 恢复端首版就使用流式限额解压；导出端先建立峰值基线，超过门槛时改流式归档；恢复永远先落 staging 文件，不把全部资源读入内存。

### 11.8 新旧数据同时存在造成错误选库

**风险：** 迁移成功后仍保留旧文件，如果启动逻辑只按“旧文件存在”判断，会重复迁移或读回旧库。  
**处理：** 完成标记优先，且绑定 source fingerprint、schema version 和校验摘要；正常 Repository 只接受 `StorageLayout` 给出的正式 SQLite 路径。

### 11.9 Debug/Profile 污染正式数据

**风险：** Windows 没有 Android 应用沙箱，开发构建可能误读用户 Release 数据。  
**处理：** build mode 路径隔离；Debug/Profile 禁止自动扫描真实 Documents；迁移测试只使用注入 fixture。

### 11.10 数据异常导致用户被迁移页永久阻塞

**风险：** Isar 损坏、磁盘不足或备份失败可能使用户无法进入应用。  
**处理：** 保留重试、重新导出 ZIP、跳过备份二次确认、显式放弃迁移的空 SQLite 入口和书架 ZIP 恢复；所有分支明确说明旧文件仍保留。迁移失败后不默认把用户弹到空书架。

### 11.11 静态加密缺失

**风险：** SQLite 明文保存，Windows 同用户权限进程、未启用磁盘加密的丢失设备或恶意本地备份工具可读取书籍内容、阅读记录和备注。  
**处理：** 本轮不引入 SQLCipher 或自管密钥，避免把大迁移和密钥恢复问题叠加；发布说明记录明文存储边界，后续如增加更敏感数据或用户要求，再单独设计静态加密。

### 11.12 WAL 与备份一致性

**风险：** WAL 中可能包含已提交但未 checkpoint 的数据；如果只复制 `.sqlite` 或把 `.sqlite-wal` 当成普通缓存，会得到不完整备份或不完整提升。  
**处理：** 所有备份、恢复和迁移提升都通过数据库生命周期接口密封数据库，执行 checkpoint、关闭连接并验证重开；文档和代码注释明确 WAL/SHM 由 SQLite 管理，不由资源复制层处理。

### 11.13 数据库连接与批量写入并发

**风险：** 主 isolate 和后台 isolate 同时写入，可能引发 busy timeout、写入饥饿或恢复期间读到中间状态。  
**处理：** 阶段二固定连接模型，同一时间只允许一个批量写入任务；迁移/恢复期间正常 Repository 不初始化，导入期间 UI 只观察节流进度和已提交状态。

## 12. 发布与回滚策略

- SQLite 迁移、迁移页面和 ZIP v2 恢复必须在同一个正式发布版本中交付，不能把用户停在“失败但无法恢复”的中间版本。
- 首发前使用 1.0.0 Release 包制造真实数据，再覆盖安装迁移版做完整演练。
- 首个 SQLite 大版本继续携带 Isar runtime 和 legacy schema，只用于迁移和旧版备份导出。
- 至少一个稳定大版本内不自动删除 Documents 中旧数据。
- 不实现自动反向 SQLite → Isar。回滚到旧应用前必须通过 ZIP 备份/恢复策略处理，不能让旧版本误以为数据为空。
- 迁移诊断只记录阶段、计数、版本、错误类型和脱敏路径，不记录书籍正文、备注内容、资源 bytes、完整个人路径或原始文件名；路径统一替换为 `$APP_DATA/...`、`$LEGACY_DOCS/...` 一类根标记，必要时只记录文件名 hash。
- 发布说明应明确：数据已迁移到应用私有目录、旧 Documents 文件暂时保留、如何手动导出备份，以及不要在确认新版本正常前删除旧文件。
- 发布说明应明确：本轮 SQLite 数据库未做应用层静态加密，依赖系统账户隔离和用户设备加密。

## 13. 完成定义

只有同时满足以下条件，本轮才算完成：

- Windows Release 不再在 Documents 根目录创建或运行任何数据库、设置和资源文件。
- Android Release/Debug/Profile 仅访问各自应用私有且隔离的数据目录。
- 新安装使用 SQLite；旧安装经过迁移页面安全切换到 SQLite。
- 迁移前 ZIP 导出、迁移真实进度、失败说明、重试、重新导出 ZIP、显式放弃迁移和重新检测旧数据路径可用。
- 当前 v2 ZIP 能导入 SQLite；v3 能完成完整 round-trip。
- 迁移或恢复中途强杀不会暴露部分数据，也不会修改或直接打开旧 Isar 原件。
- 书籍、卡片、备注、状态、时间、资源和会话校验通过。
- Repository 契约、真实 EPUB、迁移 fixture、ZIP 安全、双平台路径和 Release build 测试通过。
- 正常书库的阅读与书架体感无明显回退，大批量导入不 OOM，性能偏差有可复现报告。
- 旧 Isar 和 Documents 数据仍保留，删除策略留给后续独立版本决定。

## 附录 A：基线与基准工具

> 本附录并入原 `docs/sqlite_migration_phase1_baseline.md`（阶段一基线笔记，2026-08-15 合并），描述与实际实施保持一致；发布前的操作性检查清单见 `docs/sqlite_release_checklist.md` 第 4 节。

### A.1 `1.0.0` 遗留 fixture

fixture 必须从真实 tag `1.0.0` 生成，不能用当前工作树的 schema 冒充旧版本：

```powershell
.\tool\generate_1_0_0_legacy_fixture.ps1
```

脚本在 tag `1.0.0` 上创建 detached worktree，把 `tool/create_legacy_isar_fixture.dart` 复制进去执行，产物写入 `test/fixtures/legacy_isar_1_0_0/`。fixture manifest 格式：

```json
{
  "format": "fluidtext.legacy_fixture",
  "sourceVersion": "1.0.0",
  "expected": {
    "books": 2,
    "bookCards": 3,
    "bookAssets": 1,
    "bookRemarks": 2
  }
}
```

### A.2 Isar 基线

```powershell
dart run tool/isar_baseline.dart --output build/reports/isar_baseline.json --cards 100,1000,10000,50000
```

报告格式为 `fluidtext.isar_baseline.v1`，按 cardCounts 记录每个规模下 seedWrite/loadBooks/loadOrderedCardIds/loadCardsByIds100/loadBookStats/toggleRead/toggleFavorite 的耗时（毫秒）。Isar 与 SQLite 基准使用同一批规模与指标口径。

### A.3 SQLite 导入基准

仓储层依赖 Flutter，无法直接 `dart run`，统一走 Flutter 测试运行器（无环境变量时跳过，保持日常测试速度）：

```powershell
$env:FLUIDTEXT_SQLITE_BENCHMARK = '1'
flutter test test/sqlite_import_benchmark_test.dart
```

报告格式 `fluidtext.sqlite_import_benchmark.v1`，写入 `build/reports/sqlite_import_benchmark.json`，覆盖 100/1,000/10,000/50,000 cards 经 `SqliteLibraryRepository.importBookDraft` 的导入、关键读查询与各用例前后的 RSS。恢复/导出内存基准同理（`FLUIDTEXT_RESTORE_BENCHMARK` / `FLUIDTEXT_EXPORT_BENCHMARK`），见检查清单第 4 节。

### A.4 报告入库策略

基线报告只有在代表有明确意图的参考环境时才入库；临时本地运行的结果留在 `build/reports/`（不入库）。发布前刷新基准并把结论追加到阶段六实施记录。
