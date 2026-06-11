# FluidText

<p align="center">
  一个切分书籍、实现「卡片式阅读」和「乱序阅读」的 EPUB 电子书客户端。
</p>


<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Android%20(primary)-lightgrey.svg" alt="Platform">
</p>

---

## 目录

- [简介](#简介)
- [核心功能](#核心功能)
- [使用流程](#使用流程)
- [技术栈](#技术栈)
- [项目架构](#项目架构)
- [数据模型](#数据模型)
- [导入引擎详解](#导入引擎详解)
- [构建与运行](#构建与运行)
- [平台支持说明](#平台支持说明)
- [路线图](#路线图)
- [文档索引](#文档索引)
- [许可证](#许可证)

---

## 简介

**FluidText** 是一款将长文本 EPUB 书籍切碎为短小阅读卡片、并且支持乱序阅读的 Flutter 应用。

它可以：

**不用顺着看完前面的部分、就能知道后面的事**——不被书籍的线性结构绑架。

**降低阅读的心理门槛**——阅读不需要预期读完、正襟危坐、挑选出整块时间，随手可读。

**多本书混合、乱序阅读**——就像刷流媒体软件一样刷书。

适合：
- 碎片时间随时卡片式阅读
- 通过「乱序阅读」打破线性叙事的惯性，获得新的理解角度
- 通过「混合阅读」丰富阅读时的视角、心境

数据存放于您的设备，您掌控您的数据。在书架管理页面可以导出全部卡片内容，包括图片（暂时未支持存档文件导入）。

支持自定义背景、深浅色模式切换，自定义您的个人图书馆

---

## 核心功能

### 📖 书架管理
- **EPUB 导入**：从本地文件系统选取 `.epub` 文件，支持图文混排 EPUB。
- **多书管理**：在书架中浏览所有已导入书籍，支持单选或多选进入阅读。
- **自动续读**：自动恢复上次打开的书单，无需手动寻找。（暂不支持恢复到上次阅读的具体卡片）
- **删除书籍**：可单本删除，自动清理该书的所有卡片数据与图片资源。
- **书籍备注**：为每本书设置自定义显示备注，不更改文件名。

### ✂️ 文本切分（导入引擎）
- **传送带切分算法**：线性 O(N) 遍历章节文本，在句子边界（中文/英文句号、感叹号、问号、换行等）处切分，将长文切分为目标字数（可选300字符、750字符）的卡片。
- **内容流解析**：不再简单丢弃 HTML 结构，而是将章节解析为文本块、图片块、换行块的序列，保留原文排版意图。
- **图片单独成卡**：EPUB 中的图片会被提取并保存到本地沙盒，在原文位置附近生成独立的图片卡片，第一版暂不做图文混排，以保证渲染稳定性。
- **容错导入**：单个章节解析失败不会导致整本书导入失败；图片缺失或损坏会记录日志并跳过，不影响文本导入。

### 📱 阅读体验
- **顺序阅读**：按 `cardIndex` 递增顺序浏览卡片，即书籍原有顺序。
- **乱序阅读**：随机抽取卡片，按照乱序呈现在主页上。
- **混合阅读**：可以勾选多本书，混合在一起阅读。打破书的界限
- **上下文展开**：点击卡片可展开「上文/下文」设定范围内的邻近卡片（默认可展开上下各 2 张，可设置展开张树）；
- **收藏与已读**：
  - 手动标记卡片为「已读」或「收藏」。点击卡片空白区域已读
  - 支持过滤已读卡片
  - 独立的收藏列表与已读列表页面。
- **阅读背景**：支持纯色背景、自定义图片背景。
- **复制文本**：长按卡片，卡片文本内容自动复制到剪贴板，方便分享和查询。
- **增量加载**：卡片流采用分页/增量加载策略，避免一次性加载大量数据导致卡顿。

### ⚙️ 阅读设置
- **主题模式**：跟随系统 / 浅色 / 深色。
- **阅读顺序**：顺序 / 乱序，随时切换。
- **上下文范围**：自定义展开上下文时的「前文张数」与「后文张数」。
- **未读过滤**：一键隐藏已读卡片，聚焦剩余内容。

### 🔄 数据一致性
- **重复导入检测**：通过 `fileHash`（文件 SHA-256）和 `contentFingerprint`（内容指纹）双重识别同一本书，避免产生重复数据。
- **原子写入**：解析和切卡全部在内存中完成后，再在单个数据库事务中写入 `Book` + `BookCard` + `BookAsset`，杜绝出现空书或半本书
- 旧书兼容（只和使用了早期版本的用户有关）：对早期没有身份字段的纯文本书籍，支持惰性回填 `contentFingerprint`，使其也能参与重复检测。

---

## 使用流程

```
[书架页] ──选书──> [卡片阅读页] ──点击卡片──> [上下文底栏]
   │                      │
   │<── 侧边栏 ── 导入新书   │<── 侧边栏 ── 切换顺序/筛选/背景/设置
   │                      │
   └────── 收藏列表 / 已读列表
```

---

## 技术栈

| 类别 | 技术选型 | 说明 |
|------|---------|------|
| 框架 | [Flutter](https://flutter.dev/) | 跨平台 UI 框架，单套 Dart 代码覆盖多端 |
| 数据库 | [Isar](https://isar.dev/) | 高性能本地 NoSQL 数据库，支持复合索引、全文搜索（预留） |
| EPUB 解析 | [epub_plus](https://pub.dev/packages/epub_plus) | EPUB 结构读取、章节导航、图片资源提取 |
| HTML 解析 | [html](https://pub.dev/packages/html) | 将章节 HTML 解析为内容流，处理 DOM 遍历 |
| 文件选择 | [file_picker](https://pub.dev/packages/file_picker) | 跨平台文件选取，读取 EPUB bytes |
| 路径管理 | [path_provider](https://pub.dev/packages/path_provider) | 获取应用沙盒目录，存储图片资源 |
| 加密/哈希 | [crypto](https://pub.dev/packages/crypto) | SHA-256 计算文件哈希与内容指纹 |
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
│   │   ├── bookshelf_page.dart         # 主页 / 自动续读入口
│   │   └── bookshelf_sheet.dart        # 书架管理 BottomSheet
│   ├── reader/                         # 阅读核心
│   │   ├── reader_page.dart            # 卡片流页面
│   │   ├── reader_controller.dart      # 阅读状态控制（加载、切换顺序、筛选）
│   │   ├── read_cards_page.dart        # 全局已读列表
│   │   ├── favorite_cards_page.dart    # 全局收藏列表
│   │   ├── reading_order.dart          # 顺序 / 乱序枚举
│   │   ├── reader_background_settings.dart
│   │   └── widgets/                    # 卡片瓦片、背景层、内容渲染
│   ├── context/                        # 上下文展开
│   │   ├── context_sheet.dart
│   │   ├── context_controller.dart
│   │   └── context_settings.dart
│   └── settings/                       # 设置与侧边栏
│       ├── app_drawer.dart
│       └── reader_background_sheet.dart
│
├── models/                             # 数据实体（Isar Collection）
│   ├── book.dart                       # 书籍元数据
│   ├── book_card.dart                  # 阅读卡片
│   ├── book_asset.dart                 # 图片资源元数据
│   └── book_remark.dart                # 书籍备注
│
├── repositories/                       # 数据访问层
│   └── book_card_repository.dart       # 对 Book / BookCard / BookAsset 的查询封装
│
├── services/                           # 业务逻辑层（纯 Dart，无 UI 依赖）
│   ├── book_import_service.dart        # EPUB 导入引擎（核心）
│   ├── text_splitter.dart              # 纯文本切分器（legacy 路径）
│   ├── book_asset_store.dart           # 图片文件落盘与清理
│   ├── book_remark_service.dart        # 书籍备注读写
│   ├── reader_session_service.dart     # 阅读会话持久化
│   ├── reader_background_service.dart  # 阅读背景持久化
│   ├── data_backup_service.dart        # 数据备份（JSON 导出）
│   └── app_behavior_settings_service.dart
│
├── viewmodels/                         # 全局共享的 ViewModel
│   └── app_settings_viewmodel.dart     # 设置状态归拢（ChangeNotifier 单例）
│
├── db/
│   └── isar_db.dart                    # Isar 单例管理与数据库打开
│
├── widgets/                            # 通用 UI 组件
│   ├── glass.dart                      # 玻璃态效果容器
│   ├── blocking_loader.dart            # 全屏阻塞加载层
│   └── shelf_glyph.dart                # 书架空态图标
│
└── app_settings.dart                   # 设置项的 ValueListenable 对外暴露（兼容层）
```

### 架构原则
1. **View 不直接持有 Repository**：`reader_page.dart` 通过 `ReaderController` 操作数据，而非直接调 Repository。
2. **Service 无 Flutter 依赖**：导入、切分、文件存储等纯逻辑放在 `services/`，可在单元测试中独立运行。
3. **原子事务**：所有写操作（导入、删书、批量更新卡片状态）都封装在 `isar.writeTxn()` 内。
4. **最小依赖**：不引入 GetIt、Riverpod、Bloc 等状态管理库，降低概念负担。

---

## 数据模型

### Book（书籍）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `int` | Isar 自增主键 |
| `title` | `String` | 书名（来自 EPUB 元数据） |
| `createdAt` | `DateTime` | 记录创建时间 |
| `fileHash` | `String?` | EPUB 文件 SHA-256，用于重复检测 |
| `contentFingerprint` | `String?` | 归一化卡片内容流的 SHA-256，用于内容级重复检测 |
| `sourceFileName` | `String?` | 用户导入时的原始文件名 |
| `importedAt` | `DateTime?` | 导入完成时间 |
| `cardCount` | `int?` | 导入时生成的卡片总数 |
| `textCharCount` | `int?` | 导入时抽取的正文字符数 |
| `assetRootKey` | `String?` | 图片资源存储目录的标识键 |

### BookCard（阅读卡片）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `int` | 自增主键 |
| `bookId` | `int` | 所属书籍 ID（索引） |
| `bookTitle` | `String` | 冗余书名（方便调试与展示） |
| `cardIndex` | `int` | 全书顺序编号（索引） |
| `chapterIndex` | `int` | 所属章节索引 |
| `chapterCardIndex` | `int` | 章内卡片序号 |
| `chapterTitle` | `String?` | 章节标题 |
| `content` | `String` | 卡片纯文本内容 |
| `blocksJson` | `String?` | 结构化渲染块 JSON（图文版卡片使用） |
| `isRead` | `bool` | 是否已读 |
| `readAt` | `DateTime?` | 标记已读时间 |
| `isFavorite` | `bool` | 是否收藏 |
| `favoritedAt` | `DateTime?` | 收藏时间 |

### BookAsset（图片资源，可选）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `int` | 自增主键 |
| `bookId` | `int` | 所属书籍 |
| `assetKey` | `String` | 图片内容 SHA-256（去重标识） |
| `originalHref` | `String` | EPUB 内原始 href |
| `normalizedHref` | `String` | 规范化路径 |
| `mimeType` | `String?` | MIME 类型 |
| `relativePath` | `String` | 本地沙盒相对路径 |
| `byteLength` | `int` | 文件字节数 |
| `createdAt` | `DateTime` | 创建时间 |

---

## 导入引擎详解

导入是 FluidText 最核心的链路，流程如下：

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
原子写入（单事务）
    ├── 写入 Book
    ├── 写入全部 BookCard
    └── 若存在图片：落盘文件 + 写入 BookAsset
    │
    ▼
返回导入结果（bookId, 插入卡片数, 是否重复）
```

### 关键设计决策

- **不在切分过程中写库**：先全量生成内存对象，再一次性 `putAll`，避免部分失败留下脏数据。
- **双重重复检测**：`fileHash` 识别同一文件；`contentFingerprint` 识别「不同文件、同一内容」的场景（如重新下载的 EPUB）。
- **旧书惰性回填**：早期没有身份字段的书籍，在重复检测时会自动计算并回填 `contentFingerprint`，使其后续也能被识别。
- **失败上限控制**：若章节跳过率超过 35% 且总章节数 ≥ 4，则中断导入并提示用户，避免吞掉严重损坏的 EPUB。

---

## 构建与运行

### 环境要求

- Flutter SDK `3.38.3` or newer is recommended.
- Dart SDK `>= 3.10.1 < 4.0.0` (matches `pubspec.yaml`).
- 目标平台的构建工具链（Android Studio；其他平台需自行验证对应工具链）

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/Vanishia/fluidtext.git
cd fluidtext

# 2. 安装依赖
flutter pub get

# 3. 生成 Isar 代码（仅在修改 models/ 后需要）
flutter pub run build_runner build --delete-conflicting-outputs

# 4. 运行
flutter run

# 5. 构建发布版（以 Android 为例）
flutter build apk --release
flutter build appbundle --release
```

### 构建图标

```bash
flutter pub run flutter_launcher_icons:main
```

---

## 平台支持说明

| 平台 | 状态 | 备注 |
|------|------|------|
| Android | ✅ 主要验证平台 | 包名 `com.bird.fluidtext`；当前开发与功能验证以 Android 为主 |
| Windows | ✅ 可用 | 已可作为桌面端使用，部分交互仍偏移动端风格 |
| iOS | ⚠️ 工程存在，未验证 | 需要 macOS + Xcode自行验证构建与运行 |
| macOS | ⚠️ 工程存在，未验证 | 尚未做 macOS 专门适配 |
| Linux | ⚠️ 工程存在，未验证 | 尚未做 Linux 专门适配 |
| Web | ⚠️ 实验性 / 未验证 | Isar 的 Web 支持有限，部分功能可能不可用 |

---

## 路线图

可参考 [`roadmap.md`](roadmap.md)。主要阶段规划：

1. ✅ **书架与多书管理** — 已完成
2. ✅ **导入进度与容错** — 已完成（阻塞加载层、 tolerant parsing、重复检测）
3. ✅ **章节信息入库** — 已完成（`chapterIndex`、`chapterCardIndex`、`chapterTitle`）
4. ⬜ **Android 前台服务** — 导入常驻通知，防止切书被系统杀掉
5. ✅ **乱序阅读** — 已实现
6. ✅ **收藏 / 已读 / 筛选** — 已实现
7. ✅ **图片导入与卡片渲染** — 第一阶段已实现（图片单独成卡）
8. ⬜ **全文搜索** — 预留 Isar 全文索引能力

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [`README.md`](README.md) | 本文件，项目总览与使用指南 |
| [`roadmap.md`](roadmap.md) | 技术架构路线图与实现优先级建议 |
| [`fluidtext_roadmap.md`](fluidtext_roadmap.md) | 产品功能路线图（用户视角） |
| [`db_design.md`](db_design.md) | 数据模型设计笔记、导入一致性策略、图片策略草案 |
| [`mvvm_refactor_plan.md`](mvvm_refactor_plan.md) | MVVM 架构整理规划与实施记录（已完成） |
| [`26-03-10.md`](26-03-10.md) | 开发日志：书架功能、包名调整、Isar 调试 |

---

## 许可证

本项目采用 **GNU Affero General Public License v3.0 (AGPL-3.0)** 开源。

详见 [`LICENSE`](LICENSE) 文件。

---

<p align="center">
  Made with 💙 for readers who love fragments.
</p>
特别鸣谢：gpt-5.4，gpt-5.5
