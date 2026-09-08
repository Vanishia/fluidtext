# FluidText

<p align="center">
  一个切分书籍、实现「卡片式阅读」和「乱序阅读」的 EPUB 电子书客户端。
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-lightgrey.svg" alt="Platform">
</p>
<p align="center">
  <b>中文</b> | <a href="README_EN.md">English</a>
</p>
## 简介

**FluidText** 是一款将长文本 EPUB 书籍切碎为短小阅读卡片、并且支持乱序阅读的 Flutter 应用。

它可以：

**不用顺着看完前面的部分、就能知道后面的事**——不因为书籍的线性结构错失后面的精彩。

**降低阅读的心理门槛**——阅读不需要预期读完、正襟危坐、挑选出整块时间，随手可读。

**多本书混合、乱序阅读**——就像刷流媒体软件一样刷书。

数据存放于设备本地。书架管理页面支持导出完整备份（含图片与外观设置），也可以随时导入恢复；支持自定义背景、自定义字体、深浅色模式切换；

*readme文档更新于2026-09-08*

---

## 核心功能

### 📖 书架管理
- **EPUB 导入**：从本地文件系统选取 `.epub` 文件，支持图文混排 EPUB。
- **多书管理**：在书架中浏览所有已导入书籍，支持单选或多选进入阅读。
- **自动续读**：自动恢复上次打开的书单，无需手动寻找。（暂不支持恢复到上次阅读的具体卡片）
- **删除书籍**：可单本删除，自动清理该书的所有卡片数据与图片资源。
- **书籍备注**：为每本书设置自定义显示备注，不更改文件名。
- **备份与恢复**：一键导出 v3 ZIP 备份（书库数据 + 图片 + 背景 + 字体 + 阅读会话）；支持导入恢复 v3 与旧版 v2 备份（v2 不含外观设置）。非空库恢复前自动写入 `recovery/` 备份并二次确认。

### ✂️ 文本切分（导入引擎）
- **传送带切分算法**：线性 O(N) 遍历章节文本，在句子边界（中文/英文句号、感叹号、问号、换行等）处切分，将长文切分为目标字数（可选300字符、750字符）的卡片。
- **内容流解析**：将章节解析为文本块、图片块、换行块的序列
- **图片浏览**：支持导入含有图片的书籍
- **容错导入**：单个章节解析失败不会导致整本书导入失败；图片缺失或损坏会记录日志并跳过，不影响文本导入。
- **导入前台通知（Android）**：导入期间显示常驻前台通知（dataSync 前台服务），防止进程被系统回收。

### 📱 阅读体验
- **顺序阅读**：按 `cardIndex` 递增顺序浏览卡片，即书籍原有顺序。
- **乱序阅读**：随机抽取卡片，按照乱序呈现在主页上。
- **混合阅读**：可以勾选多本书，混合在一起阅读。打破书的界限
- **上下文展开**：点击卡片可展开「上文/下文」设定范围内的邻近卡片（默认可展开上下各 2 张，可设置展开张树）；
- **收藏与已读**：
  - 手动标记卡片为「已读」或「收藏」。点击卡片空白区域已读
  - 支持过滤已读卡片
  - 独立的收藏列表与已读列表页面，支持按时间范围、按书籍筛选与多种排序，筛选条随列表滚动。
- **全文搜索**：基于 SQLite FTS5 的书库全文检索，中英文均可命中；结果折叠为命中摘要并高亮关键词，点击展开为完整卡片，滚动到底自动加载下一页；存量卡片在首次进入搜索时后台懒建索引。
- **阅读分析**：独立的阅读统计页，包含总览、热力图、连续阅读、动态、排行、深度、收藏等模块，模块顺序可自定义。
- **阅读背景**：支持纯色背景、自定义图片背景。
- **自定义字体**：导入本地字体文件（`.ttf` / `.otf` 等），作为应用阅读字体。
- **复制文本**：桌面端提供复制按钮，移动端长按卡片即可复制文本内容到剪贴板。
- **增量加载**：卡片流采用分页/增量加载策略，避免一次性加载大量数据导致卡顿。
- **桌面端适配（Windows）**：独立的停靠式侧边面板、翻页按钮，启动窗口停靠主显示器工作区右侧；移动端保留原生悬浮毛玻璃 Drawer。

### ⚙️ 阅读设置
- **主题模式**：跟随系统 / 浅色 / 深色。
- **阅读顺序**：顺序 / 乱序，随时切换。
- **上下文范围**：自定义展开上下文时的「前文张数」与「后文张数」。
- **过滤已读**：一键隐藏已读卡片。

### 🔔 应用更新
- **软件内更新检查**：设置中可开关「显示更新通知」；开启后启动时检查 GitHub 最新 release，发现新版本时侧边栏显示通知块，可查看更新说明并下载对应平台安装包。

### 🔄 数据一致性
- **原子写入**：解析和切卡全部在内存中完成后，再在单个 SQLite 事务中写入 `books` + `book_cards` + `book_assets`，杜绝出现空书或半本书。
- **约束兜底**：卡片表带外键（`ON DELETE CASCADE`）、唯一键（`book_id + card_index`）与 CHECK 约束，删书自动级联清理。

---

## 使用流程

```
[书架页] ──选书──> [卡片阅读页] ──点击卡片──> [上下文展开]
   │                      │
   │<── 侧边栏 ── 导入新书   │<── 侧边栏 ── 切换顺序/筛选/背景/字体/设置
   │                      │
   └────── 收藏列表 / 已读列表 / 阅读分析
```

### 第一次使用

1. **导入书籍**：打开侧边栏（移动端右滑或点菜单，桌面端看右侧停靠面板），选择「导入书籍」，从文件管理器中选取 `.epub` 文件；有两种切分字数可选；
2. **打开书架**：导入完成后书籍出现在书架页。点选一本进入阅读；勾选多本则进入「混合阅读」——多本书的卡片会混在一起呈现。
3. **开始阅读**：可在侧边栏切换正序阅读/乱序阅读
4. **同时阅读多本**：可在书架页同时勾选多本书籍加入阅读卡片池

### 日常阅读

- **标记已读**：点击卡片即可标记为已读；已读卡片可以在侧边栏一键过滤，只看剩余内容。
- **收藏卡片**：点击卡片上的收藏按钮；收藏和已读各有独立列表页，从书架页或侧边栏进入。
- **展开上下文**：乱序模式下，刷到想查看上下文的卡片时，点击卡片右下角箭头展开阅读（卡片张数可在设置中调整）
- **复制文本**：桌面端点卡片右上角复制按钮，移动端长按卡片即可复制。

### 个性化

- **外观**：侧边栏切换日夜间模式，设置纯色或图片阅读背景，还可以导入本地 `.ttf` / `.otf` 字体作为阅读字体。

### 数据与统计

- **阅读分析**：从侧边栏进入阅读统计页，查看总览、热力图、连续阅读天数、排行等模块，模块顺序可自定义。
- **备份**：书架管理页可导出完整 ZIP 备份（含书籍、卡片、图片、背景与字体设置）

---

## 技术栈

| 类别 | 技术选型 | 说明 |
|------|---------|------|
| 框架 | [Flutter](https://flutter.dev/) | 跨平台 UI 框架，单套 Dart 代码覆盖多端 |
| 数据库 | [Drift](https://drift.simonbinder.eu/) + [sqlite3](https://pub.dev/packages/sqlite3) / [sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) | 类型安全的 SQLite 访问层，数据库连接在后台 isolate 中运行；内置 FTS5 全文索引 |
| 旧数据迁移 | [Isar](https://isar.dev/) | 仅用于只读打开 1.0.0 的 Isar 库并迁移到 SQLite，不参与新数据读写 |
| EPUB 解析 | [epub_plus](https://pub.dev/packages/epub_plus) | EPUB 结构读取、章节导航、图片资源提取 |
| HTML 解析 | [html](https://pub.dev/packages/html) | 将章节 HTML 解析为内容流，处理 DOM 遍历 |
| 文件选择 | [file_picker](https://pub.dev/packages/file_picker) | 跨平台文件选取，读取 EPUB / 字体 / 备份文件 |
| 路径管理 | [path_provider](https://pub.dev/packages/path_provider) | 获取应用沙盒目录，存储图片资源 |
| 压缩归档 | [archive](https://pub.dev/packages/archive) | v3 备份 ZIP 的导出与导入 |
| 加密/哈希 | [crypto](https://pub.dev/packages/crypto) | SHA-256 计算文件哈希与内容指纹 |
| 更新检查 | [package_info_plus](https://pub.dev/packages/package_info_plus) + [url_launcher](https://pub.dev/packages/url_launcher) | 读取本地版本、查询 GitHub 最新 release 并打开下载链接 |
| 状态管理 | `ChangeNotifier` + `ValueListenable` | 最小化依赖，不引入 Riverpod / Bloc 等重型框架 |

---

## 项目架构

FluidText 采用 **MVVM + 分层架构**，依赖关系严格单向：

```
lib/
├── main.dart                           # 应用入口、主题配置
│
├── features/                           # 按功能域组织（接近 Clean Architecture 的 Presentation 层）
│   ├── bookshelf/                      # 书架
│   │   ├── launch_page.dart            # 启动页：冷启动骨架、半导入书清理、自动续读
│   │   └── bookshelf_sheet.dart        # 书架管理面板（导入、备份、删除）
│   ├── reader/                         # 阅读核心
│   │   ├── reader_page.dart            # 卡片流页面
│   │   ├── reader_controller.dart      # 阅读状态控制（加载、切换顺序、筛选）
│   │   ├── card_list_page.dart         # 已读 / 收藏列表（CardListKind 区分）
│   │   ├── analysis/                   # 阅读分析（统计页）
│   │   ├── reading_order.dart          # 顺序 / 乱序枚举
│   │   ├── reader_background_settings.dart
│   │   └── widgets/                    # 卡片瓦片、卡片流、翻页按钮、背景层
│   ├── context/                        # 上下文展开
│   │   ├── context_sheet.dart
│   │   ├── context_controller.dart
│   │   └── context_settings.dart
│   ├── search/                         # 全文搜索（FTS5 检索、结果高亮、分页）
│   ├── migration/                      # Isar → SQLite 迁移页
│   └── settings/                       # 设置与侧边栏
│       ├── app_drawer.dart             # 移动端 Drawer
│       ├── app_font_settings.dart      # 自定义字体设置
│       └── reader_background_sheet.dart
│
├── models/                             # 数据实体（纯 Dart DTO）
│   ├── book.dart                       # 书籍元数据
│   ├── book_card.dart                  # 阅读卡片
│   ├── book_asset.dart                 # 图片资源元数据
│   └── book_remark.dart                # 书籍备注
│
├── repositories/                       # 数据访问层
│   ├── library_repository.dart         # LibraryRepository 接口（Repository 快照契约）
│   ├── book_card_repository.dart       # 卡片查询封装
│   └── library_snapshot.dart           # 导入/备份共用的数据快照
│
├── services/                           # 业务逻辑层（纯 Dart，无 UI 依赖）
│   ├── book_import_service.dart        # EPUB 导入引擎（核心）
│   ├── text_splitter.dart              # 纯文本切分器（legacy 路径）
│   ├── book_asset_store.dart           # 图片文件落盘与清理
│   ├── reader_session_service.dart     # 阅读会话持久化
│   ├── reader_background_service.dart  # 阅读背景持久化
│   ├── app_font_service.dart           # 自定义字体导入与注册
│   ├── backup/                         # v3 ZIP 备份导出 / 恢复 / 安全校验
│   ├── update_check_service.dart       # GitHub release 更新检查
│   ├── search_index_notification_service.dart # Android 搜索索引构建通知
│   ├── import_notification_service.dart    # Android 导入前台通知
│   └── migration_notification_service.dart # Android 迁移前台通知
│
├── viewmodels/                         # 全局共享的 ViewModel
│   └── app_settings_viewmodel.dart     # 设置状态归拢（ChangeNotifier 单例）
│
├── storage/                            # 存储层
│   ├── storage_layout.dart             # 数据目录布局（按平台与构建模式隔离）
│   ├── json_file_store.dart            # JSON 设置文件读写
│   └── sqlite/                         # Drift 数据库与 SQLite Repository 实现
│
├── migration/                          # Isar → SQLite 一次性迁移
│   ├── library_migrator.dart           # 迁移主流程（staging → 校验 → 切换）
│   ├── legacy_isar_reader.dart         # 只读打开旧 Isar 库
│   └── ...                             # 进度、状态、恢复、提升等
│
├── db/
│   └── isar_db.dart                    # 旧 Isar 单例（仅迁移期使用）
│
├── widgets/                            # 通用 UI 组件
│   ├── glass.dart                      # 玻璃态效果容器
│   ├── side_panel.dart                 # 桌面端停靠侧边面板
│   └── reading_skeleton.dart           # 阅读骨架占位
│
└── app_settings.dart                   # 设置项的 ValueListenable 对外暴露（兼容层）
```

1. **View 不直接持有 Repository**：`reader_page.dart` 通过 `ReaderController` 操作数据，而非直接调 Repository。
2. **Service 无 Flutter 依赖**：导入、切分、文件存储等纯逻辑放在 `services/`，可在单元测试中独立运行。
3. **原子事务**：所有写操作（导入、删书、批量更新卡片状态）都封装在 SQLite 事务内。

---

## 数据模型

1.1.0 起使用 SQLite（Drift 管理 schema），库文件为数据根目录下的 `fluidtext_library.sqlite`，共 5 张表，另有 `book_cards_fts` FTS5 虚拟表（外部内容索引，为全文搜索服务）：

### books（书籍）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `INTEGER` | 主键 |
| `title` | `TEXT` | 书名（来自 EPUB 元数据） |
| `created_at_ms` | `INTEGER` | 记录创建时间（毫秒时间戳） |
| `file_hash` | `TEXT?` | EPUB 文件 SHA-256，用于重复检测 |
| `content_fingerprint` | `TEXT?` | 归一化卡片内容流的 SHA-256，用于内容级重复检测 |
| `source_file_name` | `TEXT?` | 用户导入时的原始文件名 |
| `imported_at_ms` | `INTEGER?` | 导入完成时间 |
| `card_count` | `INTEGER?` | 导入时生成的卡片总数 |
| `text_char_count` | `INTEGER?` | 导入时抽取的正文字符数 |
| `asset_root_key` | `TEXT?` | 图片资源存储目录的标识键 |

### book_cards（阅读卡片）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `INTEGER` | 主键 |
| `book_id` | `INTEGER` | 所属书籍（外键，`ON DELETE CASCADE`） |
| `book_title` | `TEXT` | 冗余书名（方便调试与展示） |
| `card_index` | `INTEGER` | 全书顺序编号（与 `book_id` 组成唯一键） |
| `chapter_index` | `INTEGER` | 所属章节索引 |
| `chapter_card_index` | `INTEGER` | 章内卡片序号 |
| `chapter_title` | `TEXT?` | 章节标题 |
| `content` | `TEXT` | 卡片纯文本内容 |
| `blocks_json` | `TEXT?` | 结构化渲染块 JSON（图文版卡片使用） |
| `is_read` / `read_at_ms` | `INTEGER` / `INTEGER?` | 已读标记与时间 |
| `is_favorite` / `favorited_at_ms` | `INTEGER` / `INTEGER?` | 收藏标记与时间 |

### book_assets（图片资源）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `INTEGER` | 主键 |
| `book_id` | `INTEGER` | 所属书籍（外键，级联删除） |
| `asset_key` | `TEXT` | 图片内容 SHA-256（去重标识） |
| `original_href` / `normalized_href` | `TEXT?` | EPUB 内原始 / 规范化路径 |
| `mime_type` | `TEXT?` | MIME 类型 |
| `relative_path` | `TEXT` | 本地沙盒相对路径 |
| `byte_length` | `INTEGER?` | 文件字节数 |
| `created_at_ms` | `INTEGER` | 创建时间 |

### book_remarks（书籍备注）

| 字段 | 类型 | 说明 |
|------|------|------|
| `book_id` | `INTEGER` | 主键（外键，级联删除） |
| `title` | `TEXT` | 备注显示名 |
| `updated_at_ms` | `INTEGER` | 更新时间 |

### storage_metadata（存储元数据）

键值表，记录 schema 版本、存储格式版本等内部标记。

---

## 导入引擎详解

导入epub书籍的流程如下：

```
用户选择 EPUB 文件
    │
    ▼
读取 bytes 到内存
    │
    ▼
EpubReader.openBook(bytes) ──> 解析 EPUB 包结构
    │
    ├── 提取全部图片资源（bytes -> sha256 -> 候选索引）
    └── 提取章节树（递归读取 HTML 内容）
    │
    ▼
内容流解析（按章节）
    ├── 遍历 HTML DOM
    ├── 文本节点 -> 文本块
    ├── <img> / <image> -> 图片块（通过 href 查图片索引）
    └── <br>, <p>, <div> 等 -> 换行/段落边界
    │
    ▼
卡片打包（_CardBlockPacker）
    ├── 文本按目标字数 + 边界字符落刀
    ├── 图片到达时：若当前文本足够长，先封包文本卡；再新建图片卡
    └── 保证单张卡片最多 2 张图片，避免渲染负担过重
    │
    ▼
重复检测
    ├── 查 fileHash 匹配 -> 命中则返回旧书
    └── 查 contentFingerprint 匹配 -> 命中则返回旧书
    │
    ▼
原子写入（单个 SQLite 事务）
    ├── 写入 books
    ├── 写入全部 book_cards
    └── 若存在图片：落盘文件 + 写入 book_assets
    │
    ▼
返回导入结果（bookId, 插入卡片数, 是否重复）
```

### 设计决策

- **不在切分过程中写库**：先全量生成内存对象，再一次性批量写入，避免部分失败留下脏数据。
- **双重重复检测**：`fileHash` 识别同一文件；`contentFingerprint` 识别「不同文件、同一内容」的场景（如重新下载的 EPUB）。
- **旧书惰性回填**：早期没有身份字段的书籍，在重复检测时会自动计算并回填 `contentFingerprint`，使其后续也能被识别。
- **失败上限控制**：若章节跳过率超过 35% 且总章节数 ≥ 4，则中断导入并提示用户，避免吞掉严重损坏的 EPUB。

---

## 构建与运行

### 环境要求

- Flutter SDK `3.38.3` or newer is recommended.
- Dart SDK `>= 3.10.1 < 4.0.0` (matches `pubspec.yaml`).
- 目标平台的构建工具链（Android Studio / Visual Studio C++ 桌面工作负载）

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/Vanishia/fluidtext.git
cd fluidtext

# 2. 安装依赖
flutter pub get

# 3. 生成 Drift / Isar 代码（仅在修改 storage/ 或 models/ 后需要）
flutter pub run build_runner build --delete-conflicting-outputs

# 4. 运行
flutter run

# 5. 构建发布版
flutter build apk --release      # Android（需要 android/key.properties 签名配置）
flutter build windows --release  # Windows
```

### 测试

```bash
flutter test
```

### 构建图标

```bash
flutter pub run flutter_launcher_icons:main
```

---

## 数据存放位置

1.1.0 起，数据从系统「文档」目录迁移到应用私有目录，且 Debug / Profile / Release 三种构建模式的数据目录互相隔离：

- **Windows Release**：`%LOCALAPPDATA%\Vanishia\FluidText\`（Debug / Profile 分别为 `FluidText-Debug` / `FluidText-Profile`）
- **Android Release**：应用私有目录（各构建模式互不读写）

目录内容：SQLite 库 `fluidtext_library.sqlite`、`book_assets/`（书籍图片）、`reader_backgrounds/`（背景图）、`app_fonts/`（自定义字体）、`settings/`（JSON 设置文件）、`recovery/`（恢复前自动备份）。

数据库未做应用层静态加密，依赖系统账户隔离与设备加密；

---

## 从 1.0.0 升级

1.0.0 使用 Isar 存储，1.1.0 起切换为 SQLite。覆盖安装后首次启动会进入迁移页：

1. 建议先在迁移页**导出 ZIP 备份**，再开始迁移。
2. 迁移失败或中断：旧 Isar 数据**原样保留**，可重试，或卸载后装回 1.0.0 用旧数据。
3. 迁移完成后旧文件不会被删除；确认新版本正常前**不要手动删除**旧目录。
4. 注意：旧版本（1.0.0）无法识别新目录中的 SQLite 数据，请勿降级后直接打开。

---

## 平台支持说明

| 平台 | 状态 | 备注 |
|------|------|------|
| Android | ✅ 主要验证平台 | 包名 `com.bird.fluidtext`；导入/迁移有前台服务通知 |
| Windows | ✅ 已适配桌面端 | 停靠式侧边面板、翻页按钮、启动停靠工作区右侧 |
| iOS | ⚠️ 工程存在，未验证 | 需要 macOS + Xcode 自行验证构建与运行 |
| macOS | ⚠️ 工程存在，未验证 | 尚未做 macOS 专门适配 |
| Linux | ⚠️ 工程存在，未验证 | 尚未做 Linux 专门适配 |
| Web | ⚠️ 实验性 / 未验证 | SQLite 的 Web 支持有限，部分功能可能不可用 |

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [`README.md`](README.md) | 本文件，项目总览与使用指南 |
| [`README_EN.md`](README_EN.md) | English version of this README |
| [`fts_implementation_plan.md`](fts_implementation_plan.md) | 全文搜索（FTS5）实施计划 |
| [`docs/sqlite_storage_migration_plan.md`](docs/sqlite_storage_migration_plan.md) | Isar → SQLite 迁移设计与分阶段实施记录 |
| [`docs/sqlite_release_checklist.md`](docs/sqlite_release_checklist.md) | 1.1.0 发布检查清单、验收矩阵与回滚手册 |
| [`docs/sqlite_migration_code_review_2026-08-15.md`](docs/sqlite_migration_code_review_2026-08-15.md) | SQLite 迁移代码评审记录 |
| [`docs/db_design.md`](docs/db_design.md) | 数据模型设计笔记、导入一致性策略 |
| [`docs/reading_pages_optimization_review.md`](docs/reading_pages_optimization_review.md) | 阅读页优化评审记录 |
| [`docs/i18n_english_support_plan.md`](docs/i18n_english_support_plan.md) | 英文多语言支持实施计划（待实施） |

---

## 许可证

本项目采用 **GNU Affero General Public License v3.0 (AGPL-3.0)** 开源。

详见 [`LICENSE`](LICENSE) 文件。

---

<p align="center">
  Made with 💙 for readers who love fragments.
</p>
