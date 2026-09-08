# 英文多语言支持（i18n）实施计划

日期：2026-09-08
状态：待实施（排在阅读统计板块重构之后）

## 1. 背景与目标

为 FluidText 增加英文界面支持：

- 支持语言：中文（现状）+ 英文，共两种。
- 默认跟随系统语言（`MaterialApp.locale: null`，由系统 locale 匹配），不做应用内手动切换的第一阶段可以后续再加。
- 全平台一致行为，Windows 端零额外适配（见第 5 节）。

**前置条件**：阅读统计板块（`lib/features/reader/analysis/`）重构完成后再启动，避免两边同时大改导致冲突和返工。阅读分析模块有约 60 条硬编码文案，重构后文案结构稳定再提取，性价比最高。

## 2. 现状

- **零 i18n 基础**：`pubspec.yaml` 无 `flutter_localizations` / `intl`；无 `l10n.yaml`、无 `.arb` 文件；`MaterialApp`（`lib/main.dart:163`）未配置 `localizationsDelegates` / `supportedLocales` / `locale`。
- **硬编码中文规模**：lib/ 下约 600–750 条含中文的字符串字面量，分布在 43 个文件（占 lib/ 94 个 dart 文件的 46%）。
- **状态管理**：无第三方框架，自研 `AppSettingsViewModel` + `ValueNotifier` 体系，`MaterialApp` 外层已有三层 `ValueListenableBuilder`（背景 / themeMode / appFont），语言设置可顺此结构挂载。
- **日期格式**：手写实现（如 `analysis_common_widgets.dart:719` 的 `formatDate`，内含 `'周一'…'周日'` switch），需替换为 `intl.DateFormat` 或按 locale 分支。
- **字体**：主题未硬编码中文字体 family，默认系统字体，英文无需特殊字体处理。

### 文案分布

| 模块 | 条数（约） | 说明 |
|---|---|---|
| `lib/features/` | 440 | UI 主战场 |
| `lib/services/` | 160 | 多为错误消息，会通过插值漏进 UI 弹窗 |
| `lib/migration/` | 63 | 迁移页一次性流程，可降优先级 |
| 其余（storage / repositories / widgets / main.dart） | 13 | 少量 |

最集中的文件：

- `features/migration/migration_page.dart`：88
- `features/bookshelf/bookshelf_sheet.dart`：76
- `features/reader/analysis/widgets/analysis_modules.dart`：60（前置重构对象）
- `services/backup/backup_restore_service.dart`：55 / `zip_security.dart`：39 / `backup_format.dart`：34
- `features/settings/reader_background_sheet.dart`：34
- `features/reader/card_list_page.dart`：32

## 3. 方案选型

| 方案 | 结论 |
|---|---|
| 官方 `flutter_localizations` + `intl` + `gen_l10n`（arb 文件） | **采用**。零第三方状态管理依赖的项目用它侵入最小，编译期生成 `AppLocalizations`，类型安全 |
| easy_localization / slang 等第三方框架 | 否决：项目刻意最小依赖（README 架构原则第 4 条），为两种语言引入框架属过度设计 |
| 自研 Map 查表 | 否决：无 plural 支持，无编译期校验，长期维护成本高 |

## 4. 实施步骤

### 4.1 基础设施（约 0.5–1 天）

1. `pubspec.yaml` 添加 `flutter_localizations`（sdk: flutter）与 `intl`，开启 `generate: true`。
2. 新建 `l10n.yaml`，arb 目录定为 `lib/l10n/`，模板 `app_zh.arb` + `app_en.arb`。
3. `MaterialApp` 接入 `AppLocalizations.localizationsDelegates` 与 `supportedLocales`，`locale` 保持 `null`（跟随系统）。
4. 冒烟：抽 2–3 条文案走通全链路，Windows / Android 分别验证系统语言切换生效。

### 4.2 字符串提取与改写（约 4–6 天，工作主体）

按模块推进：features/bookshelf → features/settings → features/reader → features/context → services（错误消息）→ migration（可最后或降级处理）。

改写规则：

- **插值整句作为一个 msgid**：如 `'书籍 X 本 · 卡片 Y 张 · 警告 Z 条'` 整句翻，用 `{bookCount}` 等命名占位符，禁止逐段拼接翻译（中英文语序不同）。
- **量词处理**：中文「张 / 本 / 条」无单复数，英文需 `Intl.plural`（1 card / N cards），约几十处。
- **条件拼接改造**：如 `'${formatDate(day)} · 已读 $readCount' '${favoriteCount > 0 ? ' · 收藏 $favoriteCount' : ''}'` 这类跨行条件拼接，改为两个完整 msgid 或带可选段的占位符方案。
- **枚举→文案 switch**：保留 switch 结构，分支内改为 `AppLocalizations` 取值。
- **产品向文案需决策而非直译**：如「建议中文书籍选择」、中文预览例句（`reader_background_sheet.dart:590-592`）等绑定中文阅读场景的内容，英文版需单独定文案。

### 4.3 英文翻译（约 1–2 天）

填写 `app_en.arb`，统一术语表（bookshelf / card / shuffle reading / context 等）。

### 4.4 日期与星期格式 locale 化（约 0.5 天）

`formatDate` 等手写处替换为 `intl.DateFormat`，`initializeDateFormatting` 按需接入。

### 4.5 测试修复（约 1–2 天）

`test/features/**` 中大量 widget test 按中文文案 `find.text(...)`，需改为按 key 或按 `AppLocalizations` 取值查找；补充 locale 切换的冒烟测试。

### 4.6 回归检查

英文文案比中文长 1.5–2 倍，重点回归密集布局：

- `analysis_modules.dart`（KPI 卡片、单字星期标签 `WeekdayLabel('一')`）
- `side_panel.dart`（桌面端停靠面板）
- 书架列表项、卡片瓦片按钮区

## 5. 各平台跟随系统语言的可行性

- **Windows**：runner 端零改动。Windows embedder 自动通过 `GetUserPreferredUILanguages` 把系统语言列表上报给引擎，`PlatformDispatcher.locales` 开箱即用。已确认 `windows/runner/` 为标准模板，无任何 locale 处理，也无需添加。
- **Android / iOS**：embedder 同样自动上报，零适配。
- **应用内手动切换（可选后续项）**：持久化一个 `Locale?` 设置（仿 `themeModeSetting` 的 ValueNotifier 模式），传入 `MaterialApp.locale` 即可，各平台同样无需 runner 改动。

## 6. 工作量汇总（1 人）

| 阶段 | 估计 |
|---|---|
| 基础设施 | 0.5–1 天 |
| 字符串提取与改写 | 4–6 天 |
| 英文翻译 | 1–2 天 |
| 日期格式 locale 化 | 0.5 天 |
| 测试修复 | 1–2 天 |
| **合计** | **约 7–11 天** |

降本选项：migration 页（88 条）为一次性流程，第一阶段可保留中文；但 services 层错误消息会经 `'xxx 失败：$error'` 插值漏进 UI 弹窗，跳过会导致英中混杂，不建议省。

## 7. 风险与注意点

- **与阅读统计重构的次序**：必须先重构再提取文案，否则 60 条 analysis 文案白做一遍。
- **UI 溢出**：英文长文案在密集布局的截断/溢出，见 4.6。
- **自定义字体**：用户导入的字体若仅含中文字形，英文界面可能缺字形；属用户自选功能的边界情况，记录即可，不阻塞。
- **README / 文档**：完成后需更新 README 核心功能与平台说明，并在设置文档中记录语言行为。
