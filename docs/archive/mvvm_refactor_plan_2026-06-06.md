# MVVM 架构整理规划

## 目标

最小改动，不引入新依赖，不影响现有功能。目的：让调用链路清晰、方便调试时追踪状态变化来源。

---

## 当前不改的事项及原因

| 原建议 | 处理 | 原因 |
|--------|------|------|
| Repository ↔ Service 边界模糊 | 不改 | 改动范围大，当前不影响调试 |
| 引入统一依赖注入容器 | 不改 | 需改大量文件，增加概念负担 |
| BookRemark 独立 Isar 实例合并到主实例 | 不改 | 涉及数据迁移，风险收益不成比例 |
| TextSplitter 硬上限增强 | 不改 | 纯功能增强，非架构整理 |
| 异常处理风格不一致 | 不改 | 不影响调试，只影响线上排障 |
| ReadCardsPage/FavoriteCardsPage 补齐 ViewModel | 不改 | 每个页面仅一个查询+渲染，逻辑太少，单独建文件收益为负 |

---

## 改动步骤

### 第一组：修复 View 绕过 ViewModel 直接调 Repository

**问题**：`reader_page.dart` 的 `_toggleFavorite` / `_toggleRead` 直接持有并调用 `_repository`

**改动**：

| 文件 | 操作 |
|------|------|
| `lib/features/reader/reader_controller.dart` | 新增 `toggleRead(BookCard)` 和 `toggleFavorite(BookCard)` 方法 |
| `lib/features/reader/reader_page.dart` | 删除 `_repository` 字段；`_toggleRead/_toggleFavorite` 改为调 `_controller`；`_showContext` 通过 `_controller.repository` 获取 repository |

### 第二组：收拢全局设置为一个 ViewModel

**问题**：`app_settings.dart` 暴露 5 个裸 ValueNotifier + 5 个独立 save 函数，状态来源难以追踪

**改动**：

| 文件 | 操作 |
|------|------|
| **新建** `lib/viewmodels/app_settings_viewmodel.dart` | 类 `AppSettingsViewModel extends ChangeNotifier`，内部包含 5 个属性（themeMode、readingOrder、showUnreadOnly、contextSettings、readerBackground），setter 触发 notifyListeners 并调度持久化。单例 instance |
| `lib/app_settings.dart` | 保留 5 个 ValueNotifier 和 save 函数签名，内部改为委托给 ViewModel（最小改动，不改各文件的 import） |
| `lib/main.dart` | `initializeAppSettings()` 调用改为委托 ViewModel 初始化 |

### 第三组：给 BookshelfPage 补齐 ViewModel（可选）

| 文件 | 操作 |
|------|------|
| **新建** `lib/viewmodels/bookshelf_viewmodel.dart` | 从 BookshelfPage State 中移出 `_init` 加载逻辑 |
| `lib/features/bookshelf/bookshelf_page.dart` | State 只负责 init 触发加载和 build 渲染 |

---

## 改动总结

| 组 | 新建文件 | 修改文件 | 净删除代码 |
|----|---------|---------|-----------|
| 一 | 0 | 2 | reader_page 删除 _repository 字段 |
| 二 | 1 | 2 | 无 |
| 三 | 1 | 1 | 无 |

总计：最多新建 2 个文件，修改 4~5 个文件。

---

## 实施结果（已完成）

### 已实施

| 组 | 状态 | 文件 | 说明 |
|----|------|------|------|
| 一 | 已完成 | `reader_controller.dart`（改）、`reader_page.dart`（改） | View 不再持有 `_repository`，切换操作通过 Controller |
| 二 | 已完成 | `viewmodels/app_settings_viewmodel.dart`（新建）、`app_settings.dart`（重写） | 5 个 ValueNotifier 归一到 ViewModel 单例，app_settings 变纯转发层 |
| 三 | 跳过 | — | BookshelfPage 逻辑太薄，收益不够 |

### 未实施

不改事项与上文"当前不改的事项及原因"表格一致。

### 附带改动

- `reader_page.dart`：桌面端左上角新增汉堡菜单按钮（`Stack` + `Positioned` IconButton，仅非移动端显示）
- `.claude/settings.local.json`：新增 `dart analyze` 权限
