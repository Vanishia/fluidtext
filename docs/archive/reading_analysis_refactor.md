# 阅读分析模块重构指导文档

> 版本：第二轮优化（数据层 + 内容解耦）
> 适用范围：`lib/features/reader/analysis/` 整个子模块
> 前置状态：第一轮"拆分"已完成（9 个文件已落地）
> 本文档可直接对照代码核验；所有"已确认"项均为实跑/读码验证结果

---

## 0. 本轮目标（一句话）

让**阅读分析路径彻底不依赖 `BookCard.content`**，并用**正确的全量重算 + SWR 缓存**替换掉**基于时间戳的增量缓存**，同时把数据层、计算层、UI 层分清楚。

本轮**不做**：UI 视觉改版、isolate、列表页分页、schema 索引迁移（均列入后续）。

---

## 1. 已确认的事实（开工前提，勿再质疑）

这几条是实跑/读码验证过的，不是猜测：

1. **`normalizeReadingAnalysisModuleOrder` 存在真实 bug。**
   实跑结果：
   - 传 `List<ReadingAnalysisModuleType>` → 被重置成默认顺序
   - 传 `List<String>` → 正常保留顺序
   - 结论：页面/设置里传的是 enum，所以用户拖拽排序会被悄悄重置。
   - 修法：让 normalize **同时接受 `ReadingAnalysisModuleType` 和 `String`**。

2. **ORM 是 Isar（3.1.0+1）。** `content` 是普通 string 属性，`findAll()` 会反序列化它。

3. **Isar 单列投影链可编译可用。** 以下链已验证通过编译：
   ```
   isar.bookCards.filter()
     .isReadEqualTo(true).and().readAtIsNotNull()
     .sortByReadAtDesc().thenByIdDesc()
     .idProperty()        // 或 bookIdProperty / cardIndexProperty / readAtProperty
     .findAll()
   ```
   带 `anyOf(bookIds, ...)` 的书籍过滤版本同样通过。收藏路径 `isFavoriteEqualTo(true) + favoritedAtIsNotNull() + sortByFavoritedAtDesc()` 同样通过。
   - **方案 A（多条单列投影 + zip）在当前项目可落地。**

4. **`readAtProperty()` / `favoritedAtProperty()` 返回类型仍是 `DateTime?`**，即便前面过滤了非空。zip 时**必须做 null guard 或断言**，不能直接当非空用。

5. **当前索引只有 `bookId` 和 `cardIndex`。** `readAt` / `favoritedAt` / `isRead` / `isFavorite` 无索引 → 过滤+排序是内存扫描。本轮接受，列为后续优化。

---

## 2. 必须正视的一点：本轮修什么、不修什么

**精确区分，避免做完后误以为"那个卡顿被解决了"：**

| 痛点 | 本轮是否解决 | 说明 |
|---|---|---|
| 常驻内存膨胀（static map 长期 retain 全部正文） | ✅ 解决 | 不再缓存完整卡片，analytics 只持有轻量事件 |
| 缓存正确性（取消已读/收藏后数据残留） | ✅ 解决 | 删除时间戳增量合并，改全量重算 |
| 单次打开的 DB 反序列化成本 | ✅ 解决 | property 投影查询不反序列化 content |
| 重复打开的感知延迟 | ✅ 缓解 | SWR 先显示旧 analytics 再后台覆盖 |
| 主线程同步重算卡顿 | ❌ 不解决 | isolate 列后续；先看投影后是否还卡 |

**关键认知：** SWR 只改善"先看到东西"的感知延迟，**不改善真实工作量**。真正把单次打开成本砍下来的是**方案 A 的 property 投影查询**（绕开 content 反序列化），不是 SWR。两者解决的是不同问题，缺一不可。

---

## 3. 目标架构与分层

**铁律：投影查询 + zip 只存在于 repository 层。** 它上面的所有层都不知道 Isar、不知道 property query、不接触 `BookCard.content`。

```
ReadingAnalysisPage              (UI 壳：监听设置 / loading / error / 组装模块)
  └─ ReadingAnalysisController   (编排：组合 books + stats + events，缓存，SWR)
       └─ BookCardRepository     (Isar 投影查询 + zip + 一致性兜底)  ← 唯一碰 Isar/content 的地方
       └─ ReadingAnalytics.fromEvents(...)  (纯 Dart 计算，无 Flutter 依赖)
  └─ widgets/                    (只渲染 analytics，不读 content)
```

**分层依赖方向（不可逆）：**
```
widgets → analytics(model) ← controller → repository → Isar
```
- `repository` 不能 import `features/reader/analysis/...`（所以事件模型放 `lib/models/`，不放 feature 里）
- `analytics` 不能 import `flutter/material.dart`
- `widgets` 不能 import `repository`

---

## 4. 数据流

```
进入页面
  │
  ├─ 有缓存 → 立即用缓存 ReadingAnalytics 渲染（SWR 第一帧）
  │
  └─ 后台全量重算：
       Controller 收集 bookIds
         → repo.loadReadActivityEvents(bookIds)      ┐ 投影查询 + zip
         → repo.loadFavoriteActivityEvents(bookIds)   ┘ 不读 content
         → repo.loadBooks / stats / remarks（既有）
       → ReadingAnalytics.fromEvents(books, stats, readEvents, favoriteEvents)
       → 覆盖缓存
       → 覆盖 UI
```

**没有** `_loadIncremental`、**没有** `_mergeCards`、**没有** timestamp `since` 查询。每次都是当前 DB 快照的全量重算。

---

## 5. 文件清单（新增 / 修改 / 删除）

### 新增
| 文件 | 职责 |
|---|---|
| `lib/models/book_card_activity_event.dart` | 轻量事件模型 `BookCardActivityEvent { cardId, bookId, cardIndex, timestamp }`。放 models 层，因为 repository 不能依赖 feature。 |

### 修改
| 文件 | 改动 |
|---|---|
| `lib/repositories/book_card_repository.dart` | 新增 `loadReadActivityEvents` / `loadFavoriteActivityEvents`（投影 + zip + 兜底）。原 `loadReadCards/loadFavoriteCards` 保留给列表页，不动。 |
| `lib/features/reader/analysis/models/reading_analytics.dart` | 改吃 `BookCardActivityEvent`，删除对 `BookCard` 的持有；去掉 `material.dart`，自带 `_dateOnly`。`DayAnalysis` 内的 events 改为轻量事件。 |
| `lib/features/reader/analysis/reading_analysis_controller.dart` | 删增量逻辑，改 SWR 全量重算；缓存只存 `ReadingAnalytics`。 |
| `lib/features/reader/analysis/widgets/analysis_modules.dart` | 删除所有读 content 的分析项（最近收藏/最近已读正文预览）。 |
| `lib/features/reader/analysis/widgets/day_analysis_sheet.dart` | 时间线不再显示正文，只显示 时间 + 书名 + #cardIndex。 |
| `lib/features/reader/analysis/widgets/analysis_common_widgets.dart` | 若 `TimelineEventTile` 仅服务正文预览，改为 metadata-only 或删除。 |
| `lib/features/reader/analysis/reading_analysis_module.dart` | 修 normalize，同时接受 enum 和 String。 |

### 删除
| 文件 | 原因 |
|---|---|
| `lib/features/reader/analysis/models/analysis_cache_entry.dart` | 新缓存只需 `static final Map<String, ReadingAnalytics>`，不需要专门的 entry 类。若该类还承载别的职责需先确认再删。 |

---

## 6. Repository 层详细规范（方案 A 核心）

### 6.1 查询条件（两条路径必须各自内部一致）

**已读事件：**
- filter: `anyOf(bookIds)` + `isReadEqualTo(true)` + `readAtIsNotNull()`
- sort: `sortByReadAtDesc().thenByIdDesc()`
- project: `idProperty` / `bookIdProperty` / `cardIndexProperty` / `readAtProperty`

**收藏事件：**
- filter: `anyOf(bookIds)` + `isFavoriteEqualTo(true)` + `favoritedAtIsNotNull()`
- sort: `sortByFavoritedAtDesc().thenByIdDesc()`
- project: `idProperty` / `bookIdProperty` / `cardIndexProperty` / `favoritedAtProperty`

### 6.2 一致性铁律
- **四条投影查询必须用完全相同的 filter + sort**，只有 `.xxxProperty()` 不同。
- 用 `.thenByIdDesc()` 做**稳定排序**，避免相同 timestamp 时不同 property 查询返回顺序不一致 → 否则 zip 会字段错位。
- **尽量包进同一个 Isar read transaction（`isar.txn`）**，保证四条查询看到同一快照。若并发模型不允许，则顺序执行（中间不 await 改库）+ 长度断言兜底。

### 6.3 zip 与兜底
```
正常：四个列表 length 必须相等 → 逐下标组装 BookCardActivityEvent
长度不等 / readAt 出现 null：
  → log warning
  → fallback 到 loadReadCards/loadFavoriteCards，拿到后立即 map 成 event 并释放完整卡片
  → 不缓存完整 BookCard
```
即：**极端情况牺牲一次性能，绝不牺牲正确性。**

### 6.4 null guard
`readAtProperty()` 返回 `List<DateTime?>`。即使过滤了 `readAtIsNotNull()`，类型上仍是可空，zip 时遇 null 走兜底分支，不要 `!`。

---

## 7. 缓存策略（SWR）

- 结构：`static final Map<String, ReadingAnalytics> _cache`
- key：由参与统计的 bookIds 集合派生（注意顺序无关，需用排序后的稳定 key）
- 流程：
  1. 进页：命中缓存先渲染
  2. 后台全量重算
  3. 完成后覆盖缓存 + UI
- **绝不**做 timestamp 增量合并
- **绝不**在缓存里存原始 `BookCard` / `content`

---

## 8. 容易被忽略的坑（之前漏掉、必须覆盖）

1. **缓存失效入口缺失。**
   SWR 最终会刷新，但**备份导入 / 数据恢复**后，bookIds 可能不变而底层数据全变。
   → 在导入/恢复路径上**主动清一次 `_cache`**，不要只靠下次 SWR。

2. **cacheKey 的稳定性。** bookIds 顺序不同不应产生不同 key，否则缓存命中率为 0。先排序再拼 key。

3. **空状态。** 无任何已读/收藏时，每个模块都要有明确空态，不能渲染成 0 高度或 NaN（比率计算除零）。

4. **比率计算除零。** 收藏率、已读占比等，分母为 0 时返回 0 或显示"—"。

5. **`shelfTitle` 参数。** 当前传入但未使用。本轮要么在 header 展示、要么删参数，别留假 API。（建议结合第 10 节 header 一起做。）

6. **`FutureBuilder<Color>` 包整页。** 取色 future 变化会重建整个 Scaffold + 全部模块。本轮可不改，但**标注为已知问题**，UI 轮处理。

7. **DayAnalysis 不再持有 content 后，day sheet 的"当天明细"语义变化。** 确认产品上能接受"只看时间+书名+卡片序号"，不能接受就得回到懒加载方案（但我们已选择不读 content，默认接受）。

---

## 9. UI 层改进（**单独一轮**，不要和本轮搬代码混做）

这些是第一轮诊断出的 UI 问题，**本轮不做**，避免出问题难定位。列在这里备查：

1. 顶部缺 header：标题 / 统计范围 / 更新时间（也是 `shelfTitle` 的归宿）
2. `ReorderableListView` 当主容器、拖拽柄常驻 → 改默认浏览态，进"自定义布局"才可拖拽
3. 返回箭头硬编码 `Colors.white` → 配合自定义背景在浅色下消失，需按背景动态取色
4. 热力图移动端：月份标签塞 12px 列不可读；数值只靠 Tooltip（长按不可靠）；格子可点但发现性弱
5. 硬编码宽度（150/94/86/760）→ 响应式
6. `_VerticalBar` 混用固定值和 flex（`SizedBox(height:126)` + `Expanded` 里又写死 `74*ratio`）→ 柱高与容器解耦导致错位
7. `FutureBuilder<Color>` 整页重建（见第 8.6）

---

## 10. 后续项（明确标注：本轮不做）

- **isolate / compute**：`ReadingAnalytics.fromEvents` 主线程同步重算。事件已是纯 Dart 轻量对象，**适合**搬 isolate；但先看投影后是否还卡再决定。
- **schema 索引**：给 `readAt` / `favoritedAt` 加 `@Index()`，需 build_runner + 迁移。仅当首开仍慢才做。
- **列表页分页**：`read_cards_page` / `favorite_cards_page` 一次性读全量 content。功能就是展示正文，合理，但量大仍会慢。后续做 `loadReadCardsPage(offset, limit)`。

---

## 11. 执行顺序（带验证闸口，全程 `flutter analyze`）

1. 修 normalize（已验证 bug，独立低风险，先做）
2. 新增 `BookCardActivityEvent` 模型
3. repository 加 `loadReadActivityEvents` / `loadFavoriteActivityEvents`（投影 + zip + 兜底）
4. `ReadingAnalytics` 改吃事件、去 `material.dart`、自带 `_dateOnly`
5. 删除 content 相关分析项（最近收藏/已读、day sheet 正文）
6. controller 改 SWR 全量重算，删增量逻辑，缓存只存 analytics
7. 删 `analysis_cache_entry.dart`
8. 加缓存失效入口（导入/恢复路径清缓存）
9. `flutter analyze` + 手动回归（见第 12 节）

---

## 12. 验收标准

**静态：** `flutter analyze` 干净。

**正确性手动回归：**
- [ ] 打开分析页：各模块正常
- [ ] 下拉刷新：数据刷新
- [ ] 标记已读 → 返回分析页：已读计数 +1、热力图当天 +1
- [ ] **取消已读 → 返回分析页：计数 -1（这是旧增量缓存会漏的核心场景）**
- [ ] 收藏 / 取消收藏：同上验证
- [ ] 点热力图某天：弹层只显示 时间 + 书名 + #cardIndex，无正文
- [ ] 拖拽模块排序 → 退出重进：顺序保留（验证 normalize 修复）
- [ ] 备份导入/恢复后进分析页：数据为新数据，无旧缓存残留

**性能（建议留基线数字）：**
- [ ] 记录改造前后"首开耗时"与"内存峰值"
- [ ] 若投影后首开仍明显卡 → 触发后续项（isolate / 索引）

---

## 附：分层自检（提交前对照）

- [ ] `repository` 没有 import 任何 `features/.../analysis/...`
- [ ] `reading_analytics.dart` 没有 import `flutter/material.dart`
- [ ] `widgets/` 没有 import `repository`
- [ ] analytics / 缓存里**搜不到** `content` 字段引用
- [ ] 投影查询的四条链 filter + sort **逐字相同**
- [ ] zip 处有长度断言 + fallback + null guard


我把它组织成**可对照核验**的结构，重点固化了几个之前讨论里最容易在落地时丢失的判断：

**最该盯的三处**

1. **第 2 节**专门写了"本轮修什么、不修什么"的对照表 —— 这是你纠正我的那条核心：SWR 改善的是感知延迟，真正砍单次成本的是 property 投影查询，两者解决不同问题，别做完一个以为另一个也好了。

2. **第 6 节**把 zip 的三条铁律写死了：四条投影链 filter+sort 必须逐字相同、用 `thenByIdDesc` 稳定排序防错位、`DateTime?` 必须 null guard 不能 `!`。这几条是方案 A 最容易翻车的地方。

3. **第 8 节**把之前漏掉的坑补全了，尤其是**缓存失效入口**（导入/恢复后 bookIds 不变但数据全变，SWR 兜不住）和 **cacheKey 稳定性**（bookIds 顺序不同会导致命中率为 0）。

**两个你后续核验时要重点比对的点**

- 第 5 节的"删除"里，`analysis_cache_entry.dart` 我标了"若该类还承载别的职责需先确认再删" —— 你看代码时确认下它是不是纯缓存容器。
- 第 7 节 cacheKey 要"排序后再拼" —— 核验现在的 key 是怎么生成的，如果直接用了未排序的 bookIds 列表，那是个隐藏 bug。

