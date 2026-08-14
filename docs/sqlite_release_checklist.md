# FluidText SQLite 版本发布检查清单与用户说明

> 编写日期：2026-08-14
> 适用范围：首个 SQLite 正式版本（Isar → SQLite 迁移版）的发布与回滚操作。
> 配套文档：`docs/sqlite_storage_migration_plan.md`（设计与分阶段计划）。

本文是发布前的操作性清单。自动化已覆盖的项目标注「（自动）」，其余为发布前必须人工执行或确认的项。

## 1. 发布前自动化验证

- [ ] `flutter test` 全量通过（含 Repository 契约、迁移、ZIP 安全、路径隔离）。
- [ ] 性能基准刷新并与 Isar 基线对比（见第 4 节），偏差均有结论。
- [ ] Windows Release 构建通过：`flutter build windows --release`。
- [ ] Android Release 构建通过：`flutter build apk --release`（需要 `android/key.properties` 与签名配置）。
- [ ] 确认 Android APK 内含三个 ABI 的 `libsqlite3.so`；Windows 产物随带 `sqlite3.dll`（打包回归见迁移计划 11.1 实施记录）。

## 2. 发布前真机 / 手动验收矩阵

以下项目无法在本机自动化覆盖，发布前必须在真机或真实环境执行：

### 2.1 真实升级路径（最高优先级）

- [ ] 用 1.0.0 Release 包制造真实数据（导入含图片的 EPUB、标记已读/收藏、写备注、设置自定义背景与字体、保留阅读会话）。
- [ ] 覆盖安装迁移版，确认：启动进入迁移页 → 导出 ZIP 备份成功 → 迁移进度为真实进度 → 校验通过 → 进入书架，书籍/卡片/备注/已读/收藏/背景/字体/会话全部保留。
- [ ] 确认旧 Documents（Windows）或旧私有目录（Android）中的 Isar、JSON、资源**未被修改或删除**。
- [ ] Windows：确认新数据只落在 `%LOCALAPPDATA%\Vanishia\FluidText`，Documents 根目录不再出现新写入。
- [ ] Android：确认 Release 数据目录为应用私有目录，与 Debug/Profile 互不读写。

### 2.2 迁移异常与强杀

- [ ] 迁移各阶段（复制、读卡、写库、复制资源、校验、切换）强杀进程，重启后只能看到：旧数据原样 / 完整新数据 / 明确恢复页，三者之一。
- [ ] 迁移失败后：重试可用；「导出 ZIP 备份」可用；失败文案说明旧数据保留。
- [ ] 旧应用或同步软件（OneDrive）占用旧文件时，hash 不稳定检测能拦截并提示。

### 2.3 备份与恢复

- [ ] 书架「导出备份」（v3 ZIP）→ 清空数据 → 「导入备份」恢复，内容完整。
- [ ] 导入 1.0.0 导出的 v2 备份（有图片的 `.zip` 与无图片的 `.json` 各一份），恢复后提示外观设置未包含。
- [ ] 非空库恢复：出现二次确认；恢复前自动备份写入 `recovery/`；取消恢复不影响现有书库。
- [ ] 恢复中途强杀，原库仍可正常打开。

### 2.4 环境与体感

- [ ] 中端 Android 真机：书架加载、阅读翻卡、已读/收藏列表、统计页无可感知回退。
- [ ] 大书库（≥10,000 cards）导入不 OOM、不留半本书；导入进度可见。
- [ ] 数据目录在 OneDrive 接管的 Documents 下时，旧数据只被只读复制，新库不再其中运行。
- [ ] `%LOCALAPPDATA%` 被重定向到非 NTFS/网络盘时，启动有明确 warning 而非静默失败。

## 3. 回滚操作手册

- 首个 SQLite 版本**不删除**旧 Isar 与旧 JSON/资源，回滚不依赖自动反向迁移。
- 应用级回滚步骤：
  1. 在新版本书架「导出备份」得到 v3 ZIP（或迁移前已导出的 ZIP）。
  2. 卸载新版本，装回 1.0.0。
  3. 1.0.0 仍读取旧目录中未改动的 Isar 数据；若旧数据不可用，通过 ZIP 恢复策略人工处理。
- 禁止让旧版本直接打开新目录中的 SQLite（它不识别，会表现为空书库）；务必先告知用户数据位置变化。
- 发布后若发现致命迁移 bug：撤回发布 → 修复 → 新版本依据 `migration/state.json` 与完成标记继续/重试，不影响已迁移成功用户。

## 4. 性能验收记录

基准报告输出到 `build/reports/`（不入库）：

| 报告 | 驱动命令 |
| --- | --- |
| Isar 基线 | `dart run tool/isar_baseline.dart --cards 100,1000,10000,50000 --output build/reports/isar_baseline.json` |
| SQLite 导入 | 设 `FLUIDTEXT_SQLITE_BENCHMARK=1` 后 `flutter test test/sqlite_import_benchmark_test.dart` |
| 恢复内存 | 设 `FLUIDTEXT_RESTORE_BENCHMARK=1` 后 `flutter test test/backup_restore_benchmark_test.dart` |
| 导出内存 | 设 `FLUIDTEXT_EXPORT_BENCHMARK=1` 后 `flutter test test/backup_export_benchmark_test.dart` |

验收门槛（迁移计划 8.4）：关键查询 P95 与 EPUB 导入总耗时原则上不超过 Isar 基线约 20%；50,000 cards 导入与大图片备份不 OOM；`integrity_check`、外键检查通过。每次发布前将最新数字与结论追加到迁移计划的阶段六实施记录。

当前固定策略（2026-08-14）：

- `synchronous = FULL`（保守默认；仅在真实用户流程性能不可接受且强杀恢复测试通过时才允许降 NORMAL）。
- 迁移写入 batch 500、恢复写入 chunk 2000、导入按书单事务 batch；数据库连接经 `NativeDatabase.createInBackground` 在后台 isolate。
- v3 导出为内存归档：导出基准显示峰值 RSS 增量在可接受范围（见实施记录），大图库真机 OOM 风险在第 2.4 节人工验收；超标再改流式归档。

## 5. 用户说明（发布说明要点）

- 数据已从系统「文档」目录迁移到应用私有目录（Windows：`%LOCALAPPDATA%\Vanishia\FluidText`）；旧文件暂时保留，确认新版本正常前**不要手动删除**。
- 升级首次启动会进入迁移页，建议先导出 ZIP 备份再开始迁移；迁移失败旧数据仍在，可重试或用「导入备份」恢复。
- 书架新增「导入备份」，可恢复本版本导出的 v3 ZIP 与旧版本导出的 v2 备份（v2 不含外观设置）。
- 本轮数据库未做应用层静态加密，依赖系统账户隔离与设备加密；请保持系统盘加密（BitLocker 等）开启。
- Debug/Profile/Release 数据目录互相隔离，互不影响。

## 6. 版本与打包

- [ ] 发布前在 `pubspec.yaml` 提升版本号（当前与 1.0.0 相同，覆盖安装演练后即 bump）。
- [ ] Windows 打包 zip 与 Android APK 命名遵循 `release/` 现有约定，更新 `SHA256SUMS.txt`。
- [ ] 保留上一正式版本安装包与迁移前 ZIP 至少一个稳定版本周期。
