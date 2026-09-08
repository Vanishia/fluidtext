# FluidText

<p align="center">
  An EPUB e-book client that splits books into "card-based reading" and "shuffled reading" fragments.
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-lightgrey.svg" alt="Platform">
</p>
<p align="center">
  <a href="README.md">中文</a> | <b>English</b>
</p>
## Introduction

**FluidText** is a Flutter app that shreds long-form EPUB books into short reading cards and supports shuffled reading.

It lets you:

**Know what happens later without reading everything before it** — don't miss the good parts just because a book is linear.

**Lower the psychological barrier to reading** — no need to plan to finish, sit up straight, or carve out a big block of time; read whenever you have a moment.

**Mix multiple books and read them shuffled** — scroll through books the way you scroll a streaming app.

Data stays on your device. The bookshelf management page can export a full backup (including images and appearance settings) and import it back at any time. Custom backgrounds, custom fonts, and light/dark mode switching are supported.

*README last updated on 2026-09-08*

---

## Core Features

### 📖 Bookshelf Management
- **EPUB import**: pick `.epub` files from the local file system; EPUBs with mixed text and images are supported.
- **Multi-book management**: browse all imported books on the bookshelf; enter reading with a single book or a multi-selection.
- **Auto resume**: automatically restores the last opened reading list — no manual hunting required. (Restoring the exact last-read card is not supported yet.)
- **Delete books**: delete a single book; all of its card data and image assets are cleaned up automatically.
- **Book remarks**: set a custom display remark for each book without changing the file name.
- **Backup & restore**: one-tap export of a v3 ZIP backup (library data + images + backgrounds + fonts + reading sessions); supports restoring v3 and legacy v2 backups (v2 contains no appearance settings). Restoring into a non-empty library automatically writes a `recovery/` backup first and asks for a second confirmation.

### ✂️ Text Splitting (Import Engine)
- **Conveyor-belt splitting algorithm**: a linear O(N) pass over chapter text, cutting at sentence boundaries (Chinese/English periods, exclamation and question marks, line breaks, etc.) into cards of a target length (300 or 750 characters, selectable).
- **Content-flow parsing**: chapters are parsed into a sequence of text blocks, image blocks, and line-break blocks.
- **Image viewing**: books containing images can be imported.
- **Fault-tolerant import**: a single chapter that fails to parse does not fail the whole book; missing or corrupted images are logged and skipped without affecting text import.
- **Foreground import notification (Android)**: a persistent foreground notification (dataSync foreground service) is shown during import to keep the process from being reclaimed by the system.

### 📱 Reading Experience
- **Sequential reading**: browse cards in ascending `cardIndex` order — the book's original order.
- **Shuffled reading**: randomly drawn cards presented on the home page out of order.
- **Mixed reading**: tick multiple books and read them mixed together — break the boundaries between books.
- **Context expansion**: tap a card to expand neighboring cards within a configurable range (2 cards above and below by default; the count is adjustable).
- **Favorites & read marks**:
  - Manually mark a card as "read" or "favorite"; tap the blank area of a card to mark it read.
  - Read cards can be filtered out.
  - Dedicated favorite and read list pages, with filtering by time range and by book, multiple sort orders, and a filter bar that scrolls with the list.
- **Full-text search**: library-wide search powered by SQLite FTS5, matching both Chinese and English; results are collapsed to a hit summary with highlighted keywords, tap to expand the full card, and scrolling to the bottom loads the next page; the index for existing cards is built lazily in the background the first time you open search.
- **Reading analysis**: a dedicated statistics page with overview, heatmap, reading streaks, activity, rankings, depth, favorites, and more; the module order is customizable.
- **Reading background**: solid-color backgrounds or custom image backgrounds.
- **Custom fonts**: import local font files (`.ttf` / `.otf`, etc.) as the app's reading font.
- **Copy text**: a copy button on desktop; long-press a card on mobile to copy its text to the clipboard.
- **Incremental loading**: the card stream uses paged/incremental loading to avoid jank from loading too much data at once.
- **Desktop adaptation (Windows)**: a dedicated docked side panel and page-turn buttons; the launch window docks to the right of the primary display's work area. Mobile keeps the native floating frosted-glass Drawer.

### ⚙️ Reading Settings
- **Theme mode**: follow system / light / dark.
- **Reading order**: sequential / shuffled, switchable at any time.
- **Context range**: customize how many cards are expanded before and after the tapped card.
- **Filter read**: hide read cards with one tap.

### 🔔 App Updates
- **In-app update check**: a "show update notifications" toggle in settings; when enabled, the app checks the latest GitHub release at startup. When a new version is found, a notice block appears in the sidebar where you can read the release notes and download the installer for your platform.

### 🔄 Data Consistency
- **Atomic writes**: parsing and card cutting finish entirely in memory, then `books` + `book_cards` + `book_assets` are written in a single SQLite transaction — no empty or half-imported books.
- **Constraint safety net**: the cards table has a foreign key (`ON DELETE CASCADE`), a unique key (`book_id + card_index`), and CHECK constraints; deleting a book cascades automatically.

---

## Usage Flow

```
[Bookshelf] ──pick books──> [Card Reading Page] ──tap a card──> [Context Expansion]
   │                              │
   │<── sidebar ── import books   │<── sidebar ── order/filter/background/font/settings
   │                              │
   └────── Favorites / Read List / Reading Analysis
```

### First Time

1. **Import books**: open the sidebar (swipe right or tap the menu on mobile; see the docked panel on the right on desktop), choose "Import books", and pick a `.epub` file from the file manager; two splitting lengths are available.
2. **Open the bookshelf**: imported books appear on the bookshelf. Tap one to start reading; tick several to enter "mixed reading" — cards from multiple books are presented together.
3. **Start reading**: switch between sequential and shuffled reading in the sidebar.
4. **Read several books at once**: tick multiple books on the bookshelf to add them to the reading card pool.

### Daily Reading

- **Mark as read**: tap a card to mark it read; read cards can be hidden with one tap in the sidebar so you only see what's left.
- **Favorite cards**: tap the favorite button on a card; favorites and read cards each have a dedicated list page, reachable from the bookshelf page or the sidebar.
- **Expand context**: in shuffled mode, when a card makes you want its context, tap the arrow in its lower-right corner to expand (the number of cards is adjustable in settings).
- **Copy text**: on desktop, click the copy button in a card's upper-right corner; on mobile, long-press the card.

### Personalization

- **Appearance**: switch between dark and light mode in the sidebar, set a solid-color or image reading background, and import local `.ttf` / `.otf` fonts as the reading font.

### Data & Statistics

- **Reading analysis**: enter the statistics page from the sidebar to see the overview, heatmap, reading streaks, rankings, and other modules; the module order is customizable.
- **Backup**: export a full ZIP backup from the bookshelf management page (books, cards, images, backgrounds, and font settings).

---

## Tech Stack

| Category | Choice | Notes |
|------|---------|------|
| Framework | [Flutter](https://flutter.dev/) | Cross-platform UI framework; one Dart codebase covers all platforms |
| Database | [Drift](https://drift.simonbinder.eu/) + [sqlite3](https://pub.dev/packages/sqlite3) / [sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) | Type-safe SQLite access layer; the database connection runs in a background isolate; built-in FTS5 full-text index |
| Legacy migration | [Isar](https://isar.dev/) | Only used to open the 1.0.0 Isar database read-only and migrate it to SQLite; not involved in new reads/writes |
| EPUB parsing | [epub_plus](https://pub.dev/packages/epub_plus) | EPUB package reading, chapter navigation, image asset extraction |
| HTML parsing | [html](https://pub.dev/packages/html) | Parses chapter HTML into a content flow; handles DOM traversal |
| File picking | [file_picker](https://pub.dev/packages/file_picker) | Cross-platform file picking for EPUB / font / backup files |
| Paths | [path_provider](https://pub.dev/packages/path_provider) | Locates the app sandbox directory for image assets |
| Archives | [archive](https://pub.dev/packages/archive) | Export and import of v3 backup ZIPs |
| Crypto / hashing | [crypto](https://pub.dev/packages/crypto) | SHA-256 for file hashes and content fingerprints |
| Update check | [package_info_plus](https://pub.dev/packages/package_info_plus) + [url_launcher](https://pub.dev/packages/url_launcher) | Reads the local version, queries the latest GitHub release, and opens download links |
| State management | `ChangeNotifier` + `ValueListenable` | Minimal dependencies; no heavy frameworks like Riverpod / Bloc |

---

## Project Architecture

FluidText uses **MVVM + layered architecture** with strictly one-way dependencies:

```
lib/
├── main.dart                           # App entry, theme configuration
│
├── features/                           # Organized by feature domain (close to Clean Architecture's Presentation layer)
│   ├── bookshelf/                      # Bookshelf
│   │   ├── launch_page.dart            # Launch page: cold-start skeleton, half-imported book cleanup, auto resume
│   │   └── bookshelf_sheet.dart        # Bookshelf management panel (import, backup, delete)
│   ├── reader/                         # Reading core
│   │   ├── reader_page.dart            # Card stream page
│   │   ├── reader_controller.dart      # Reading state control (loading, order switching, filtering)
│   │   ├── card_list_page.dart         # Read / favorite lists (distinguished by CardListKind)
│   │   ├── analysis/                   # Reading analysis (statistics page)
│   │   ├── reading_order.dart          # Sequential / shuffled enum
│   │   ├── reader_background_settings.dart
│   │   └── widgets/                    # Card tiles, card stream, page-turn buttons, background layer
│   ├── context/                        # Context expansion
│   │   ├── context_sheet.dart
│   │   ├── context_controller.dart
│   │   └── context_settings.dart
│   ├── search/                         # Full-text search (FTS5 query, result highlighting, pagination)
│   ├── migration/                      # Isar → SQLite migration page
│   └── settings/                       # Settings and sidebar
│       ├── app_drawer.dart             # Mobile Drawer
│       ├── app_font_settings.dart      # Custom font settings
│       └── reader_background_sheet.dart
│
├── models/                             # Data entities (pure Dart DTOs)
│   ├── book.dart                       # Book metadata
│   ├── book_card.dart                  # Reading card
│   ├── book_asset.dart                 # Image asset metadata
│   └── book_remark.dart                # Book remark
│
├── repositories/                       # Data access layer
│   ├── library_repository.dart         # LibraryRepository interface (Repository snapshot contract)
│   ├── book_card_repository.dart       # Card query wrapper
│   └── library_snapshot.dart           # Data snapshot shared by import/backup
│
├── services/                           # Business logic layer (pure Dart, no UI dependencies)
│   ├── book_import_service.dart        # EPUB import engine (core)
│   ├── text_splitter.dart              # Plain-text splitter (legacy path)
│   ├── book_asset_store.dart           # Image file persistence and cleanup
│   ├── reader_session_service.dart     # Reading session persistence
│   ├── reader_background_service.dart  # Reading background persistence
│   ├── app_font_service.dart           # Custom font import and registration
│   ├── backup/                         # v3 ZIP backup export / restore / safety checks
│   ├── update_check_service.dart       # GitHub release update check
│   ├── search_index_notification_service.dart # Android search-index build notification
│   ├── import_notification_service.dart    # Android import foreground notification
│   └── migration_notification_service.dart # Android migration foreground notification
│
├── viewmodels/                         # Globally shared ViewModels
│   └── app_settings_viewmodel.dart     # Consolidated settings state (ChangeNotifier singleton)
│
├── storage/                            # Storage layer
│   ├── storage_layout.dart             # Data directory layout (isolated per platform and build mode)
│   ├── json_file_store.dart            # JSON settings file I/O
│   └── sqlite/                         # Drift database and SQLite Repository implementation
│
├── migration/                          # One-time Isar → SQLite migration
│   ├── library_migrator.dart           # Migration main flow (staging → validation → switchover)
│   ├── legacy_isar_reader.dart         # Opens the legacy Isar database read-only
│   └── ...                             # Progress, state, recovery, promotion, etc.
│
├── db/
│   └── isar_db.dart                    # Legacy Isar singleton (only used during migration)
│
├── widgets/                            # Shared UI components
│   ├── glass.dart                      # Frosted-glass effect container
│   ├── side_panel.dart                 # Desktop docked side panel
│   └── reading_skeleton.dart           # Reading skeleton placeholder
│
└── app_settings.dart                   # ValueListenable exposure of settings (compatibility layer)
```

1. **Views never hold a Repository directly**: `reader_page.dart` manipulates data through `ReaderController` instead of calling the Repository itself.
2. **Services have no Flutter dependencies**: pure logic such as import, splitting, and file storage lives in `services/` and can run in unit tests independently.
3. **Atomic transactions**: all write operations (import, book deletion, batch card state updates) are wrapped in SQLite transactions.

---

## Data Model

Since 1.1.0, the app uses SQLite (schema managed by Drift). The database file is `fluidtext_library.sqlite` in the data root directory, with 5 tables plus a `book_cards_fts` FTS5 virtual table (an external-content index serving full-text search):

### books

| Column | Type | Notes |
|------|------|------|
| `id` | `INTEGER` | Primary key |
| `title` | `TEXT` | Book title (from EPUB metadata) |
| `created_at_ms` | `INTEGER` | Record creation time (millisecond timestamp) |
| `file_hash` | `TEXT?` | SHA-256 of the EPUB file, for duplicate detection |
| `content_fingerprint` | `TEXT?` | SHA-256 of the normalized card content flow, for content-level duplicate detection |
| `source_file_name` | `TEXT?` | Original file name at import time |
| `imported_at_ms` | `INTEGER?` | Import completion time |
| `card_count` | `INTEGER?` | Total number of cards generated at import |
| `text_char_count` | `INTEGER?` | Number of body-text characters extracted at import |
| `asset_root_key` | `TEXT?` | Key identifying the image asset storage directory |

### book_cards (reading cards)

| Column | Type | Notes |
|------|------|------|
| `id` | `INTEGER` | Primary key |
| `book_id` | `INTEGER` | Owning book (foreign key, `ON DELETE CASCADE`) |
| `book_title` | `TEXT` | Denormalized book title (handy for debugging and display) |
| `card_index` | `INTEGER` | Book-wide sequence number (unique together with `book_id`) |
| `chapter_index` | `INTEGER` | Owning chapter index |
| `chapter_card_index` | `INTEGER` | Card sequence number within the chapter |
| `chapter_title` | `TEXT?` | Chapter title |
| `content` | `TEXT` | Card plain-text content |
| `blocks_json` | `TEXT?` | Structured render-block JSON (used by cards with images) |
| `is_read` / `read_at_ms` | `INTEGER` / `INTEGER?` | Read flag and timestamp |
| `is_favorite` / `favorited_at_ms` | `INTEGER` / `INTEGER?` | Favorite flag and timestamp |

### book_assets (image assets)

| Column | Type | Notes |
|------|------|------|
| `id` | `INTEGER` | Primary key |
| `book_id` | `INTEGER` | Owning book (foreign key, cascading delete) |
| `asset_key` | `TEXT` | SHA-256 of the image content (dedup identifier) |
| `original_href` / `normalized_href` | `TEXT?` | Original / normalized path inside the EPUB |
| `mime_type` | `TEXT?` | MIME type |
| `relative_path` | `TEXT` | Path relative to the local sandbox |
| `byte_length` | `INTEGER?` | File size in bytes |
| `created_at_ms` | `INTEGER` | Creation time |

### book_remarks (book remarks)

| Column | Type | Notes |
|------|------|------|
| `book_id` | `INTEGER` | Primary key (foreign key, cascading delete) |
| `title` | `TEXT` | Remark display name |
| `updated_at_ms` | `INTEGER` | Update time |

### storage_metadata

A key-value table recording internal markers such as the schema version and storage format version.

---

## Import Engine in Detail

The flow for importing an EPUB book:

```
User picks an EPUB file
    │
    ▼
Read bytes into memory
    │
    ▼
EpubReader.openBook(bytes) ──> parse the EPUB package structure
    │
    ├── Extract all image assets (bytes -> sha256 -> candidate index)
    └── Extract the chapter tree (recursively read HTML content)
    │
    ▼
Content-flow parsing (per chapter)
    ├── Walk the HTML DOM
    ├── Text nodes -> text blocks
    ├── <img> / <image> -> image blocks (resolved via href against the image index)
    └── <br>, <p>, <div>, etc. -> line-break / paragraph boundaries
    │
    ▼
Card packing (_CardBlockPacker)
    ├── Text is cut at the target length + boundary characters
    ├── When an image arrives: if the current text is long enough, seal the text card first; then start a new image card
    └── Guarantee at most 2 images per card to keep rendering cheap
    │
    ▼
Duplicate detection
    ├── Match fileHash -> return the existing book on hit
    └── Match contentFingerprint -> return the existing book on hit
    │
    ▼
Atomic write (single SQLite transaction)
    ├── Write books
    ├── Write all book_cards
    └── If images exist: write files to disk + write book_assets
    │
    ▼
Return the import result (bookId, inserted card count, duplicate flag)
```

### Design Decisions

- **No database writes during splitting**: generate all in-memory objects first, then batch-write in one shot, so a partial failure leaves no dirty data.
- **Dual duplicate detection**: `fileHash` identifies the same file; `contentFingerprint` identifies "different file, same content" (e.g., a re-downloaded EPUB).
- **Lazy backfill for old books**: books imported before identity fields existed get their `contentFingerprint` computed and backfilled during duplicate detection, so they can be recognized later.
- **Failure cap**: if the chapter skip rate exceeds 35% and there are ≥ 4 chapters, the import aborts with a prompt, instead of silently swallowing a badly corrupted EPUB.

---

## Build & Run

### Requirements

- Flutter SDK `3.38.3` or newer is recommended.
- Dart SDK `>= 3.10.1 < 4.0.0` (matches `pubspec.yaml`).
- The build toolchain for your target platform (Android Studio / Visual Studio C++ desktop workload).

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/Vanishia/fluidtext.git
cd fluidtext

# 2. Install dependencies
flutter pub get

# 3. Generate Drift / Isar code (only needed after changing storage/ or models/)
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Run
flutter run

# 5. Build release artifacts
flutter build apk --release      # Android (requires android/key.properties signing config)
flutter build windows --release  # Windows
```

### Tests

```bash
flutter test
```

### Build icons

```bash
flutter pub run flutter_launcher_icons:main
```

---

## Data Location

Since 1.1.0, data has moved from the system "Documents" directory to the app's private directory, and the data directories of Debug / Profile / Release builds are isolated from each other:

- **Windows Release**: `%LOCALAPPDATA%\Vanishia\FluidText\` (Debug / Profile use `FluidText-Debug` / `FluidText-Profile` respectively)
- **Android Release**: the app-private directory (build modes cannot read or write each other)

Directory contents: the SQLite database `fluidtext_library.sqlite`, `book_assets/` (book images), `reader_backgrounds/` (background images), `app_fonts/` (custom fonts), `settings/` (JSON settings files), `recovery/` (automatic pre-restore backups).

The database is not encrypted at the application layer; it relies on system account isolation and device encryption.

---

## Upgrading from 1.0.0

1.0.0 used Isar for storage; since 1.1.0 the app uses SQLite. After installing over the old version, the first launch enters a migration page:

1. It is recommended to **export a ZIP backup** on the migration page before starting the migration.
2. If the migration fails or is interrupted: the old Isar data is **kept intact** — you can retry, or uninstall and reinstall 1.0.0 to use the old data.
3. Old files are not deleted after migration; **do not manually delete** the old directory until you have confirmed the new version works.
4. Note: the old version (1.0.0) cannot read the SQLite data in the new directory — do not downgrade and open it directly.

---

## Platform Support

| Platform | Status | Notes |
|------|------|------|
| Android | ✅ Primary verified platform | Package name `com.bird.fluidtext`; foreground-service notifications for import/migration |
| Windows | ✅ Desktop adapted | Docked side panel, page-turn buttons, launch window docked to the right of the work area |
| iOS | ⚠️ Project exists, unverified | Requires macOS + Xcode to verify build and run yourself |
| macOS | ⚠️ Project exists, unverified | No macOS-specific adaptation yet |
| Linux | ⚠️ Project exists, unverified | No Linux-specific adaptation yet |
| Web | ⚠️ Experimental / unverified | SQLite support on the Web is limited; some features may be unavailable |

---

## Documentation Index

| Document | Contents |
|------|------|
| [`README.md`](README.md) | 中文版项目总览与使用指南 |
| [`README_EN.md`](README_EN.md) | This file — project overview and usage guide in English |
| [`fts_implementation_plan.md`](fts_implementation_plan.md) | Full-text search (FTS5) implementation plan |
| [`docs/sqlite_storage_migration_plan.md`](docs/sqlite_storage_migration_plan.md) | Isar → SQLite migration design and phased implementation record |
| [`docs/sqlite_release_checklist.md`](docs/sqlite_release_checklist.md) | 1.1.0 release checklist, acceptance matrix, and rollback manual |
| [`docs/sqlite_migration_code_review_2026-08-15.md`](docs/sqlite_migration_code_review_2026-08-15.md) | SQLite migration code review record |
| [`docs/db_design.md`](docs/db_design.md) | Data model design notes, import consistency strategy |
| [`docs/reading_pages_optimization_review.md`](docs/reading_pages_optimization_review.md) | Reading pages optimization review record |
| [`docs/i18n_english_support_plan.md`](docs/i18n_english_support_plan.md) | English i18n support implementation plan (pending) |

---

## License

This project is open-sourced under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

See the [`LICENSE`](LICENSE) file for details.

---

<p align="center">
  Made with 💙 for readers who love fragments.
</p>
