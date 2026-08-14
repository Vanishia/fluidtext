# SQLite 迁移代码审查报告

> 审查日期：2026-08-15  
> 审查范围：分支 `codex/sqlite-migration` 阶段三至六的重构改动（提交 `89e36ea`..`774e732`）  
> 审查重点：错误处理、内存峰值（尤其是导入备份时图片极多的场景）、Isar 迁移失败时 ZIP 恢复的兜底能力  
> 测试基线：`flutter test` 全量通过（223 通过、3 跳过——跳过项为需环境变量的基准测试）；`flutter analyze` 无问题；`flutter build apk --debug` 通过

## 1. 总体结论

**迁移与备份恢复链路的核心安全设计是可靠的。**「旧数据只读 + staging 隔离 + 原子切换 + 完成标记 + 状态机恢复」的纵深防御在各环节落实到位；图片极多场景的内存控制（恢复端）良好；Isar 迁移失败时的 ZIP 兜底路径完整可达。

发现 2 个值得记录的次级问题（P2/P3，不阻塞发布）、2 个已在文档中如实记录的已知取舍（导出内存峰值、无磁盘预检），本次均已写入本报告。另按需求为迁移过程增加了 Android 前台服务通知防杀（见 §5）。

## 2. 错误处理审查

### 2.1 做得好的部分

| 环节 | 实现 | 评价 |
| --- | --- | --- |
| 迁移失败状态 | `MigrationRunner.run` 在任意异常路径都写 `state.json`（markFailed），重试前 `prepareMigrationRetry` 清 staging 与未完成提升物 | ✅ 状态机输入完备 |
| 旧数据保护 | 旧 Isar 只在复制到 staging 后才被打开（`LegacyIsarReader` 只碰副本；`LegacyBackupExporter` 同样从副本构建），原件零写入 | ✅ 符合计划 §5.2 |
| 数据异常分级 | 卡片指向缺失书籍/重复序号 → 硬失败停止；orphan 资源/备注 → warning 跳过；资源文件缺失 → 保留记录 | ✅ 与计划 §5.3 矩阵一致 |
| 诊断脱敏 | `sanitizeDiagnosticText` 统一剥离 SQL 语句/绑定参数（含卡片正文）与绝对路径，迁移/提升/恢复三处共用 | ✅ 无旁路 |
| 恢复回滚 | `_swapAtomically` 失败时从 `previous/` 回滚，回滚动作本身 best-effort 但方向正确；调用方（bookshelf_sheet.dart:518-530）失败后重建已关闭的数据库单例 | ✅ 失败后应用可用 |
| WAL 密封 | `SqliteSealer`/`MigrationPromotion.seal`：checkpoint(TRUNCATE)→close→删边车文件，且处理了后台 isolate 连接重建边车文件的竞态（重试+非空即失败） | ✅ 密封后提升物自包含 |

### 2.2 发现的问题

**P2｜恢复尝试目录失败后不清理，累积消耗磁盘**  
`BackupRestoreService.restore`（backup_restore_service.dart:103-124）：失败时 `recovery/attempts/<id>/`（含解压出的全部资源）保留用于诊断，但**没有任何后续清理或数量上限**。用户反复导入损坏/超限的备份（每次解压最多 4GB）会让 attempts 目录无限增长，最终把应用私有目录写满，恰好破坏「ZIP bomb 防护写满磁盘」想保护的东西。

建议（后续提交）：每次 restore 开始时清理旧的失败 attempts（保留最近 1 个），或启动时清理。计划 §7.4 只规定了成功路径的清理。

**P3｜`_swapAtomically` 回滚的极端缺口**  
回滚循环中「删除已放入 root 的条目」失败被吞掉（方向正确——previous 里的原件优先），但若此时「移回 previous 条目」也失败，root 会处于部分缺失状态。由于交换发生在 `closeLiveDatabase()` 之后且完成标记尚未刷新，下次启动 `decide()` 会走 `recoveryRequired`（数据库存在但 marker 计数失配，app_bootstrap_coordinator.dart:140-143），仍可由用户重试恢复兜底，故降为 P3。恢复/重试状态由迁移页面渲染（复用同一页面，无独立「恢复页面」）；建议在报告文案中保留「重启应用后按迁移页面指引操作」的提示即可，不需要代码改动。

## 3. 内存峰值审查（图片极多场景）

### 3.1 恢复（导入备份）——达标

这是用户点名的场景，结论：**恢复端对大量图片是流式安全的**。

- `ZipSecurity.extractToDisk`（zip_security.dart:108-198）：先自解析中央目录做结构校验（拒绝加密/符号链接/路径逃逸/重复条目/超限），解压经 `decodeStream` 逐条目进行，**同一时刻内存只持有一个条目的 bytes**，写盘前再做词法+canonical 双重 ZIP Slip 校验。单文件 ≤512MB、总数 ≤4GB、条目 ≤10 万的限额在解压中强制执行。
- 图片落盘后，`_stageFiles` → `_copyDirectoryRecursively` 用 `File.copy`（平台流式复制）搬进 payload，不经过堆内存。
- 数据库写入单事务内按 2000 行 chunk batch。
- 实测基准（计划阶段五/六实施记录）：50,000 cards（47MB 备份）峰值 RSS 增量约 40–50MB，量级为备份 JSON 大小的 1–2 倍；图片部分因流式落盘不叠加进该峰值。
- 一个已知边界：v2/v3 的 `data/library.json` 是整文件一次解码（50,000 cards ≈ 47MB JSON → 峰值 ~50MB）。可接受，已在计划中标记「更大书库的流式 JSON 解析留作候选优化」。

### 3.2 导出——已知取舍，已记录，维持现状

`BackupExportService.exportV3` 是内存归档：全部资源 bytes + manifest + 最终 ZIP 同持。基准显示峰值约为未压缩 payload 的 2–3 倍（50,000 cards 约 226MB）。**这是当前唯一可能在大图库上触顶的点**，但：

- 阶段六实施记录已明确「维持内存归档，大图库真机 OOM 验收列入检查清单 §2.4，超标再改流式归档」；
- 恢复前的保险备份（`PreRestoreBackup`）也走同一导出路径，理论峰值相同。

建议：不改代码，但把「导出前校验可用内存/在低端机提示」作为检查清单 §2.4 真机验收的必测项（已存在该条目）。若真机超限，改法是把 `addBytesEntry` 换成 archive 包的 `OutputFileStream` 流式写盘编码，manifest 的 sha256 已在逐文件读取时可流式计算，改动局部。

### 3.3 迁移引擎——达标

- Isar 读取按 batchSize=500 游标分批（`legacy_isar_reader.dart` idGreaterThan+limit）；
- SQLite 写入在同一事务内 batch；
- 资源复制边读边写边 hash（`_copyResources`，chunked sha256），不整文件入内存；
- 唯一的成规模常驻结构是 `copiedResourceHashes`（每文件一个 64 字符 hash）与 ID 集合，10 万文件也就几十 MB 字符串量级，安全。

## 4. Isar 迁移失败的 ZIP 兜底审查

结论：**兜底路径完整、可达、被测过**。三条失败出路都能落到 ZIP 恢复：

1. **迁移页导出 v2 ZIP**（迁移前/失败后均可用）：`LegacyBackupExporter` 从 staging 副本构建，不碰原件；失败文案（migration_page.dart `_buildFailed`）明确提示「可先导出 ZIP 备份；稍后可用导入备份恢复」。
2. **放弃迁移进空书架 → 书架「导入备份」**：`MigrationBootstrapPage` 提供「重新检测旧数据并迁移」入口；`BookshelfSheet` 的「导入备份」接受 v2 `.json`/`.zip` 与 v3 `.zip`（魔数+manifest 判定），恢复到 SQLite。
3. **`migrationUnavailable`（不可信的 default.isar）**：页面直接引导「旧版本导出 ZIP → 新书架导入备份」，不猜测迁移。✅ 符合计划 §11.5。

闭环验证：`backup_restore_service_test.dart` 覆盖 v2 JSON/v2 ZIP/v3 round-trip、恢复替换、中途失败原库完好、reader session 无效引用清空。测试通过。

一个注意点（非缺陷）：兜底依赖**旧版本能导出备份**或**迁移页能从副本导出**。若 Isar 副本损坏到连 v2 导出都失败（`LegacyBackupException('无法读取旧数据库副本…')`），则无数据可救——这是数据源本身损坏的物理极限，任何方案都无解，且旧原件始终未被触碰，用户可回退旧版本尝试。此边界已由文案覆盖（提示回旧版本导出 ZIP）。

## 5. 本次改动：迁移前台通知防杀

按需求实现，与 EPUB 导入的普通常驻通知（`ImportNotificationService`）刻意区分：

| | EPUB 导入 | 数据迁移（本次） |
| --- | --- | --- |
| 机制 | 普通通知 | **dataSync 前台服务**（`MigrationForegroundService`） |
| 理由 | 导入快、失败可下次启动清理半本书 | 一次性搬全库，被杀只能整体重试 |
| 防护边界 | 提示为主 | 提升进程优先级防系统后台回收；**不防用户主动划掉**（Flutter engine 随 Activity 销毁），该场景仍由 staging+state.json 恢复兜底 |

- Android：`fluidtext/migration_service` 通道；`start/update/stop`；迁移页「导出 ZIP 备份」和「开始迁移」期间挂起，进度文本与页面节流（150ms）同步更新，finally 中 stop；通知权限被拒时迁移照常（仅通知不可见）。
- 其他平台 no-op；所有调用 best-effort，失败仅写 `AppLogger`，绝不影响迁移本身。
- Manifest 增加 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC` 权限与 service 声明；`flutter build apk --debug` 验证通过。
- 真机验收项已加入 `sqlite_release_checklist.md` §2.2。

## 6. 已知取舍备忘（无需行动）

1. **导出内存归档**：见 §3.2，触发条件与改法已记录。
2. **磁盘空间无预检**：计划 §5.3 要求「写入前估算、过程中捕获」，实现只有过程中捕获（写盘抛错→失败保留旧数据）。迁移/恢复前不估算可用空间。失败路径安全（staging 被清、原件未动），代价是用户在大库+磁盘将满时要经历一次失败才知道。建议：发布说明或迁移页文案不承诺预检；后续版本可在 `MigrationStaging.create` 前加 `getTotalSpace/freeSpace` 估算（P3）。
3. **v3 恢复统计口径**：`_stageFiles` 的 totalFiles 对 v3 按解压目录文件数计、v2 按资源记录数计，进度百分比口径不同但均单调，无功能影响。

## 7. 审查覆盖文件

`migration/`（runner、migrator、promotion、state、staging、coordinator、legacy_backup_exporter）、`services/backup/`（restore、export、zip_security、pre_restore）、`services/import_notification_service.dart`、`features/migration/migration_page.dart`、`features/bookshelf/bookshelf_sheet.dart`（恢复编排）、`android/`（MainActivity、Manifest）。全量测试/analyze/APK 构建结果见抬头。
