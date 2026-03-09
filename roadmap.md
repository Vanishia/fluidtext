# FluidText Roadmap / 架构规划

目标：做一个“切书的、卡片式阅读”App。核心链路只有一条：**导入 EPUB → 解析章节 HTML → 抽取纯文本 → 按规则切卡 → 批量写入 Isar → 从库里按顺序读取并展示**。

## 当前范围（MVP）

- 导入 `epub`
- 切分文本并写入数据库（批量写入）
- 主界面按顺序展示卡片


## 现有架构（已实现）

### 分层
- `lib/main.dart`
  - UI：导入按钮 + 导入中阻塞加载层 + 卡片流列表（分页/增量加载）
  - 读取数据库中“最近导入的一本书”的卡片并显示
- `lib/services/`
  - `book_import_service.dart`：EPUB bytes → `epub_plus` 解析 → HTML 转纯文本 → 切分 → `Isar.putAll` 批量入库
  - `text_splitter.dart`：线性“传送带”切分算法（目标字数 + 边界字符落刀）
- `lib/models/`
  - `book.dart`：书（目前只存 `title`、`createdAt`）
  - `book_card.dart`：卡片（`bookId`、`bookTitle`、`cardIndex`、`content`）
- `lib/db/isar_db.dart`
  - 统一打开 Isar 实例（单例）

### 数据库（Isar）
- `Book`
  - `id`（自增）
  - `title`
  - `createdAt`（用于“最近一本书”）
- `BookCard`
  - `id`（自增）
  - `bookId`（关联书）
  - `bookTitle`（冗余字段，方便调试/展示；后续可改为 join 查询或直接用 Book 表）
  - `cardIndex`（顺序编号，从 0 开始递增）
  - `content`（卡片正文）

### 导入流程（当前行为）
1. 选取 `.epub` 文件（`file_picker`，读取 bytes 到内存）
2. `EpubReader.readBook(bytes)` 得到章节列表和 `htmlContent`
3. `html` 包解析 HTML 并取 `document.body?.text` 作为纯文本
4. 对每个章节文本执行切分（默认目标 300 字，遇到 `。！？.!?\n` 等边界落刀）
5. 每章切完后一次性 `putAll` 写入 Isar
6. 首页按 `cardIndex` 升序分页读取并渲染

## 下一阶段架构建议（为了后续功能不返工）

### 1) 书架/多书支持（建议优先级：最高）
动机：现在首页默认加载“最近一本书”，对真实使用不够。
- 新增 `BooksPage`：显示所有已导入书籍
- 点击某本书进入 `CardsPage(bookId)`（复用现在的卡片流）
- 增加“删除一本书”（连同 `BookCard` 一起删）

### 2) 更稳定的导入（建议优先级：高）
动机：真实 EPUB 体积可能很大；导入过程要可感知、可恢复。
- 导入进度（至少：章节数进度/卡片数进度）
- 导入中禁止二次导入；支持取消
- Android：常驻通知 + 前台服务（防止切书被系统杀掉）
- 更强的容错：空章节、坏 HTML、特殊编码、极长无标点段落

### 3) 为“上下文展开/乱序阅读”补齐必要字段（建议优先级：中）
动机：这俩都是核心玩法，但最好先把数据结构打好地基。
- `BookCard` 增加：
  - `chapterIndex`
  - （可选）`chapterTitle`
- 增加复合索引（概念上）：`(bookId, chapterIndex, cardIndex)`，方便毫秒级查上下文

### 4 乱序阅读实现
基于 bookId 随机抽 cardIndex 或随机查询

### 5 阅读体验（建议优先级：中）
- 卡片加载策略：更明确的分页/缓存策略（目前已做增量加载）
- 字体/行距/主题等（放到最后）

###  功能扩展（建议优先级：低 → 最后）
- 收藏 / 已读
- 筛选模式（只看收藏、过滤已读）
- 全文搜索（Isar 的全文索引 / 额外倒排）
- 图片（解析 `<img>` 并落地到沙盒目录，用占位符在卡片里渲染）

## 建议的实现顺序（可直接按这个做）
1. 书架（多书列表）+ 进入书的卡片页 + 删除书
2. 导入进度与错误提示（UI/状态机）
3. `chapterIndex` 入库 + 上下文查询所需索引/查询方法
4. Android 前台服务/常驻通知（导入防杀）
5. 乱序阅读
6. 收藏/已读/筛选
7. 全文搜索
8. 图片渲染

