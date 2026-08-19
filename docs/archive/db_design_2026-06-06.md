# FluidText 数据模型设计笔记

## 目标

这份文档用于固定当前阶段的关键设计决策，避免后续因为图片、已读、上下文等能力演进而频繁重构数据库。

当前优先级不是补更多 UI 功能，而是先稳定数据主轴。

## 核心对象

### Book

`Book` 表示已经导入到应用中的一本书。

它负责承载书级别信息，例如：

- 书名
- 导入时间
- 未来可扩展的作者、封面、总卡片数

`Book` 是书架层对象，不承载逐段阅读内容。

### BookCard

`BookCard` 表示用户在阅读界面中实际消费的最小内容单元。

它不是“纯文本片段”，而是“阅读内容单元”：

- 当前可以只包含文本
- 未来允许包含图片占位符
- 负责承载已读、收藏、顺序、章节定位等阅读信息

## 主轴定义

### 全书顺序

`cardIndex` 永远表示一本书中的全书顺序。

这是当前阅读主轴，顺序阅读、上下文展开、后续乱序阅读都以它为基础。

### 章节信息

章节信息作为辅助元数据存在，不改变当前主轴。

保留以下字段：

- `chapterIndex`
- `chapterCardIndex`
- `chapterTitle`

这些字段当前可以不直接体现在功能层，但为后续目录、章内定位、调试和搜索结果定位留出空间。

## 已读与收藏

### 已读

采用：

- `isRead`
- `readAt`

其中：

- `readAt` 表示最近一次被标记为已读的时间
- 当取消已读时，`readAt` 清空

自动已读未来再做，本阶段只保留字段和结构空间。

### 收藏

采用：

- `isFavorite`
- `favoritedAt`

即使暂时不使用收藏时间排序，也先保留这个字段，避免以后再补迁移。

## content 字段定义

`content` 不只是给 UI 直接显示的一段字符串，而是卡片内容的规范化内容源。

当前阶段：

- 可以只保存纯文本

未来阶段：

- 允许在内容中包含受控占位符
- 渲染层读取 `content` 并决定如何展示

这意味着 `content` 的职责是描述“这张卡的内容是什么”，而不是“这张卡最终怎么画出来”。

## 导入一致性与书籍身份

### 当前问题

`Book.id` 是数据库自增 id，适合作为本地对象主键，但不适合识别“这是不是同一本书”。

如果每次导入 EPUB 都创建新 `Book`：

- 同一本书会出现多个 `bookId`
- 已读、收藏仍挂在旧 `BookCard` 上
- 打开新副本时旧收藏不可见
- 导入失败还可能留下空书或半本书

因此后续导入必须先建立书籍身份，再写入数据库。

### 第一阶段字段

`Book` 在保留现有字段的基础上新增以下可空字段：

- `fileHash`：EPUB 原始 bytes 的 sha256，用于识别完全相同文件
- `contentFingerprint`：归一化后的卡片内容流生成的内容指纹，用于识别同内容不同文件
- `sourceFileName`：用户导入时的原文件名，只用于提示和排查
- `importedAt`：导入完成时间，旧 `createdAt` 保留
- `cardCount`：导入时生成的卡片数
- `textCharCount`：导入时抽取出的正文字符数

这些字段都必须是可空字段。旧数据打开后字段为 `null`，不能影响旧收藏、旧已读、旧书架显示。

### 重复导入策略

第一阶段采用保守策略：

1. 导入前计算 `fileHash`
2. 解析 EPUB、切卡，并根据归一化卡片内容计算 `contentFingerprint`
3. 先查找相同 `fileHash` 的 `Book`
4. 再查找相同 `contentFingerprint` 的 `Book`
5. 命中已有书时不创建新书、不创建新卡片，直接返回已有 `bookId`

这样旧收藏和已读继续停留在原来的 `BookCard` 上，用户重新导入同一本书时仍会打开旧书。

暂不做“重新导入并合并进度”。那需要把旧卡片状态映射到新卡片，涉及内容 diff、章节变化、卡片重切分等风险，应放到独立阶段处理。

### 原子导入策略

导入流程必须改成：

`EPUB bytes -> 解析 -> 生成全部 BookCard 内存对象 -> 重复检测 -> 单个 writeTxn 写入 Book + BookCard`

禁止在解析过程中先写 `Book`，再按章节分批写 `BookCard`。

如果解析或切卡失败，数据库不应留下空书或半本书。

### 备份定位

JSON 只作为用户主动导出的备份格式，不作为主存储。

主存储仍是 Isar。备份能力用于：

- schema 变更前给用户留出自救文件
- 排查数据问题
- 后续做恢复/导入备份的基础

备份内容至少包括：

- `Book`
- `BookCard`
- `BookRemark`
- `ReaderSession`
- 导出时间和备份格式版本

## 图片策略

### 存储方式

图片不写入数据库二进制字段。

未来采用：

- 图片文件按书分目录存储，例如 `book_assets/<bookId>/<assetHash>.<ext>`
- Isar 只保存图片元数据
- 卡片内容中保存受控渲染语法或结构化 blocks，引用图片资源

例如：

`今天下雨了。⟦img:img_000123⟧然后继续正文。`

### 占位符格式

当前约定图片占位符使用：

`⟦img:asset_key⟧`

选择这个格式的原因：

- 在真实书籍正文里几乎不会自然出现
- 比常见 Markdown 语法更不容易撞脸
- 未来可以扩展为其他内容类型，例如 `⟦note:...⟧`

### 导入方向

当前导入链路是：

`HTML -> 纯文本 -> 切卡`

未来支持图片时，应升级为：

`HTML -> 内容流 -> 切卡 -> 保存图片资源 -> 保存卡片渲染结构`

也就是说：

- 现有“按顺序切卡”的思路保留
- 真正要升级的是导入中间层的数据表示

### EPUB 图片解析规划

`epub_plus` 已能读取 EPUB 的内容资源，其中图片会出现在 `epub.content.images` 中，章节 HTML 中的 `<img src="...">` 负责说明图片在正文里的位置。

图片导入需要拆成两条线：

1. 资源线：读取 EPUB 内所有图片 bytes，按规范路径和 hash 建立图片索引
2. 内容线：遍历章节 HTML DOM，按原文顺序生成文本块和图片块

资源线处理：

- 读取 `epub.content.images`
- 对每张图片计算 `assetHash = sha256(bytes)`
- 记录原始 `href`、规范化后的 `normalizedHref`、`mimeType`
- 图片落盘到 app documents 下的 `book_assets/<bookId>/`
- 相同 hash 的图片只保存一份

内容线处理：

- 不再使用 `document.body?.text` 一次性丢弃结构
- 遍历 DOM 子节点
- 文本节点归一化为空白可控的文本块
- `<p>`、`<div>`、`<br>` 等形成段落或换行边界
- `<img>`、`<image>` 形成图片块
- 图片块通过章节 HTML 所在路径解析相对 `src`
- 解析后的 `src` 去资源线索引中查找对应 `BookAsset`

### 图片资源表草案

未来新增 `BookAsset`：

- `id`
- `bookId`
- `assetHash`
- `originalHref`
- `normalizedHref`
- `mimeType`
- `localPath`
- `width`
- `height`

图片 bytes 不存进 Isar，数据库只保存路径和元数据。

### 卡片渲染结构草案

`BookCard.content` 继续保留为纯文本兼容字段。

未来给 `BookCard` 新增可空字段：

- `blocksJson`

结构示例：

```json
[
  {"type":"text","text":"今天下雨了。"},
  {"type":"image","assetId":123,"alt":"插图"},
  {"type":"text","text":"然后继续正文。"}
]
```

渲染规则：

- 如果 `blocksJson == null`，按旧逻辑渲染 `content`
- 如果有 `blocksJson`，按 block 顺序渲染 `Text` 和 `Image.file`
- 图片加载失败时显示轻量占位，不影响文字阅读
- 收藏、已读、上下文仍绑定在 `BookCard` 上，不绑定到图片资源

### 最小图片切分策略

未来接入图片时，优先采用“图片单独成卡”的策略。

这样可以最大限度复用现有按字数切文本的逻辑，降低改坏现有切分器的风险。

第二阶段再考虑图文混排卡片。也就是说第一版图片支持可以是：

- 文本按原规则切卡
- 图片在原文位置附近单独生成图片卡
- 图片卡的 `content` 可为空或保存 alt 文本
- `blocksJson` 中只包含一个 image block

这样能先打通 EPUB 图片提取、资源落盘、卡片渲染三件事。

## 删书规则

当删除一本书时：

- 删除对应 `Book`
- 删除对应 `BookCard`
- 删除该书对应的图片资源目录

不保留孤立图片资源。

## 当前阶段不处理的事项

- 自动已读规则落地
- 图片资源表
- 图文混排卡片

这些能力以后可以继续演进，但当前不阻塞数据库主轴定型。

## 当前字段草案

### Book

- `id`
- `title`
- `createdAt`
- `fileHash`
- `contentFingerprint`
- `sourceFileName`
- `importedAt`
- `cardCount`
- `textCharCount`

### BookCard

- `id`
- `bookId`
- `bookTitle`
- `cardIndex`
- `chapterIndex`
- `chapterCardIndex`
- `chapterTitle`
- `content`
- `isRead`
- `readAt`
- `isFavorite`
- `favoritedAt`
