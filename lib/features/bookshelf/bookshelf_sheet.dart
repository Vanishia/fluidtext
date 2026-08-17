import 'dart:developer' as developer;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_settings.dart';
import '../../models/book.dart';
import '../../repositories/library_data_access.dart';
import '../../repositories/library_repository.dart';
import '../../migration/migration_state.dart';
import '../../services/app_logger.dart';
import '../../services/backup/backup_restore_service.dart';
import '../../services/backup/pre_restore_backup.dart';
import '../../services/book_import_service.dart';
import '../../services/import_notification_service.dart';
import '../../storage/storage_layout.dart';
import '../../widgets/blocking_loader.dart';
import '../../widgets/glass.dart';
import '../migration/migration_page.dart';

Future<List<Book>?> showBookshelfSheet(
  BuildContext context, {
  List<int> initialSelectedBookIds = const <int>[],
}) {
  return showModalBottomSheet<List<Book>>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        BookshelfSheet(initialSelectedBookIds: initialSelectedBookIds),
  );
}

/// Shows a user-friendly import failure dialog. The technical detail stays
/// out of the UI: it is already in the log file, and can be copied to the
/// clipboard for a bug report.
Future<void> showImportFailureDialog(
  BuildContext context, {
  required Object error,
  required StackTrace stackTrace,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('导入失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(describeBookImportError(error)),
            const SizedBox(height: 10),
            Text(
              '详细错误已写入应用日志，反馈问题时可点击「复制详情」获取。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: '$error\n\n$stackTrace'),
              );
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('复制详情'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      );
    },
  );
}

class BookshelfSheet extends StatefulWidget {
  const BookshelfSheet({
    super.key,
    this.initialSelectedBookIds = const <int>[],
    this.dataAccessLoader,
    this.migrationEntryChecker,
    this.backupFilePicker,
    this.preRestoreBackup,
    this.backupRestoreRunner,
    this.settingsReloader,
  });

  final List<int> initialSelectedBookIds;

  /// Injectable seams for widget tests (the production defaults hit real IO
  /// which never completes inside the fake-async test zone).
  final Future<LibraryDataAccess> Function()? dataAccessLoader;
  final Future<bool> Function()? migrationEntryChecker;
  final Future<String?> Function()? backupFilePicker;
  final Future<String> Function()? preRestoreBackup;
  final Future<BackupRestoreResult> Function(File backupFile)?
  backupRestoreRunner;
  final Future<void> Function()? settingsReloader;

  @override
  State<BookshelfSheet> createState() => _BookshelfSheetState();
}

class _BookshelfSheetState extends State<BookshelfSheet> {
  final _books = <Book>[];
  final _remarks = <int, String>{};
  final _stats = <int, BookCardStats>{};
  late final Set<int> _selectedIds = widget.initialSelectedBookIds.toSet();

  LibraryRepository? _repository;
  LibraryDataAccess? _dataAccess;
  bool _isLoading = true;
  bool _isBusy = false;
  bool _showMigrationEntry = false;
  String? _status;
  String? _restoreProgressStage;
  double? _restoreProgressValue;
  String? _importProgressLabel;
  double? _importProgressValue;
  String? _lastImportNotificationText;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final dataAccess =
        await (widget.dataAccessLoader ?? () => LibraryDataAccess.instance)();
    final repository = dataAccess.repository;
    final books = await repository.loadBooks();
    final remarks = await dataAccess.loadRemarks();
    final stats = await repository.loadBookStats(
      books.map((book) => book.id).toList(),
    );
    await repository.logDatabaseSnapshot('bookshelf init');

    final showMigrationEntry = await _checkMigrationEntry();

    if (!mounted) return;
    setState(() {
      _dataAccess = dataAccess;
      _repository = repository;
      _books
        ..clear()
        ..addAll(books);
      _remarks
        ..clear()
        ..addAll(remarks);
      _stats
        ..clear()
        ..addAll(stats);
      _selectedIds.removeWhere((id) => !_books.any((book) => book.id == id));
      _showMigrationEntry = showMigrationEntry;
      _isLoading = false;
    });
  }

  /// Offers re-detection when the user previously abandoned a migration.
  Future<bool> _checkMigrationEntry() async {
    final checker = widget.migrationEntryChecker;
    if (checker != null) return checker();
    try {
      final targetLayout = await AppStorageResolver.targetRuntimeLayout();
      final state = await MigrationStateStore(
        targetLayout: targetLayout,
      ).load();
      return state.status == MigrationLifecycleStatus.abandoned;
    } catch (_) {
      return false;
    }
  }

  Future<void> _redetectMigration() async {
    final targetLayout = await AppStorageResolver.targetRuntimeLayout();
    await MigrationStateStore(targetLayout: targetLayout).markIdle();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const MigrationBootstrapPage()),
    );
    if (!mounted) return;
    setState(() => _showMigrationEntry = false);
    await _reloadBooks();
  }

  Future<void> _reloadBooks() async {
    final repository = _repository;
    if (repository == null) return;

    final books = await repository.loadBooks();
    final remarks = await repository.loadRemarks();
    final stats = await repository.loadBookStats(
      books.map((book) => book.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _books
        ..clear()
        ..addAll(books);
      _remarks
        ..clear()
        ..addAll(remarks);
      _stats
        ..clear()
        ..addAll(stats);
      _selectedIds.removeWhere((id) => !_books.any((book) => book.id == id));
    });
  }

  Future<void> _pickAndImportEpub() async {
    final dataAccess = _dataAccess;
    if (dataAccess == null || _isBusy) return;

    final targetCharsPerCard = await _chooseTargetCharsPerCard();
    if (targetCharsPerCard == null) return;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _status = '正在导入…';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;

      if (bytes == null) {
        if (!mounted) return;
        setState(() => _status = '未选择文件');
        return;
      }

      final notifications = ImportNotificationService.instance;
      final notificationTitle = '正在导入《${file?.name ?? 'EPUB 文件'}》';
      await notifications.ensurePermission();
      await notifications.showProgress(
        title: notificationTitle,
        text: '导入中请勿退出',
      );

      final imported = await dataAccess.importEpubBytes(
        bytes: bytes,
        sourceFileName: file?.name,
        targetCharsPerCard: targetCharsPerCard,
        onProgress: (progress) =>
            _onImportProgress(progress, notificationTitle),
      );
      await notifications.showCompleted(text: '《${imported.bookTitle}》');
      await _reloadBooks();
      if (!mounted) return;

      setState(() {
        _selectedIds.add(imported.bookId);
        _status = imported.wasDuplicate
            ? '《${imported.bookTitle}》已存在，已选中原书（${imported.matchedBy ?? '重复匹配'}）'
            : '已导入《${imported.bookTitle}》 · ${imported.insertedCards} 张卡片';
      });
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'BookshelfSheet',
        'EPUB import failed',
        error: error,
        stackTrace: stackTrace,
      );
      await ImportNotificationService.instance.cancel();
      if (!mounted) return;
      setState(() => _status = '导入失败：${describeBookImportError(error)}');
      await showImportFailureDialog(
        context,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _importProgressLabel = null;
          _importProgressValue = null;
        });
      }
    }
  }

  void _onImportProgress(
    BookImportProgress progress,
    String notificationTitle,
  ) {
    final fraction = progress.fraction;
    final label = switch (progress.stage) {
      BookImportStage.parsing => '正在解析 EPUB 结构…',
      BookImportStage.readingChapters =>
        '正在读取章节 ${progress.completedUnits}/${progress.totalUnits}',
      BookImportStage.buildingCards =>
        '正在切分卡片… 已生成 ${progress.producedCards} 张',
      BookImportStage.writing => '正在写入书库…',
    };
    if (mounted) {
      setState(() {
        _importProgressLabel = label;
        _importProgressValue = fraction;
      });
    }

    final percent = fraction == null ? null : (fraction * 100).round();
    final text = percent == null ? '导入中请勿退出' : '导入中请勿退出 · $percent%';
    if (text == _lastImportNotificationText) return;
    _lastImportNotificationText = text;
    ImportNotificationService.instance.showProgress(
      title: notificationTitle,
      text: text,
      percent: percent,
    );
  }

  Future<int?> _chooseTargetCharsPerCard() {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return AlertDialog(
          title: const Text('选择切分长度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '按字符数切分，达到所选长度后会尽量在句号、问号、感叹号或换行处断开。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _ImportLengthOption(
                icon: Icons.menu_book_rounded,
                title: '300字符',
                subtitle: '建议中文书籍选择',
                onTap: () => Navigator.of(context).pop(300),
              ),
              const SizedBox(height: 10),
              _ImportLengthOption(
                icon: Icons.notes_rounded,
                title: '750字符',
                subtitle: '建议英文书籍选择、或需要长卡片的中文书籍',
                onTap: () => Navigator.of(context).pop(750),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportBackup() async {
    final dataAccess = _dataAccess;
    if (dataAccess == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '正在导出备份…';
    });

    try {
      final path = await dataAccess.exportBackup();
      if (!mounted) return;
      setState(() {
        _status = path == null ? '已取消导出备份' : '备份已导出：$path';
      });
    } catch (error, stackTrace) {
      developer.log(
        'Backup export failed in bookshelf sheet',
        name: 'BookshelfSheet',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _status = '备份导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Imports a v2/v3 backup with whole-library replacement (plan 7.4):
  /// confirm on a non-empty library, write a pre-restore insurance backup,
  /// then swap atomically and reload everything.
  Future<void> _importBackup() async {
    final dataAccess = _dataAccess;
    if (dataAccess == null || _isBusy) return;

    final path = await (widget.backupFilePicker ?? _pickBackupFilePath)();
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() => _status = '未选择文件');
      return;
    }

    if (_books.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入备份'),
          content: Text('恢复备份将替换当前书库（${_books.length} 本书），是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续恢复'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }

    setState(() {
      _isBusy = true;
      _status = '正在备份当前书库…';
    });

    try {
      // Pre-restore insurance backup of the current library (pointless and
      // therefore skipped when the library is empty).
      try {
        if (_books.isNotEmpty) {
          await (widget.preRestoreBackup ?? _writePreRestoreBackup)();
        }
      } catch (error) {
        developer.log(
          'Pre-restore backup failed in bookshelf sheet',
          name: 'BookshelfSheet',
          error: error,
        );
        if (!mounted) return;
        setState(() => _isBusy = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('自动备份失败'),
            content: Text('恢复前备份当前书库失败：$error\n仍要继续恢复吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('仍要继续恢复'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (proceed != true) {
          setState(() => _status = '已取消恢复');
          return;
        }
        setState(() => _isBusy = true);
      }

      setState(() {
        _status = '正在恢复备份…';
        _restoreProgressStage = '正在恢复备份…';
        _restoreProgressValue = 0;
      });
      final runner = widget.backupRestoreRunner ?? _runBackupRestore;
      final result = await runner(File(path));

      // The restore closed and swapped the live database; drop the stale
      // repository before reloading so every read hits the restored data.
      final freshAccess =
          await (widget.dataAccessLoader ?? () => LibraryDataAccess.instance)();
      if (!mounted) return;
      setState(() {
        _dataAccess = freshAccess;
        _repository = freshAccess.repository;
      });
      await _reloadBooks();
      // The swap also replaced the appearance settings files (background,
      // font, behavior). Reload the settings view model so the in-memory
      // notifiers pick up the restored values live; otherwise a stale
      // in-memory default could be saved back over the restored files.
      await (widget.settingsReloader ?? initializeAppSettings)();
      if (!mounted) return;

      final legacyNote = result.formatVersion == 2
          ? '；核心书库已恢复，外观设置未包含在旧版备份中'
          : '';
      setState(() {
        _status =
            '已恢复${result.formatVersion == 2 ? ' 1.0.0 旧版备份' : '备份'}：'
            '书籍 ${result.bookCount} 本 · '
            '卡片 ${result.cardCount} 张 · 警告 ${result.warnings.length} 条'
            '$legacyNote';
      });
    } catch (error, stackTrace) {
      developer.log(
        'Backup restore failed in bookshelf sheet',
        name: 'BookshelfSheet',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      // The restore may have closed the live database before failing (the
      // swap then rolled back); reopen the singleton so the sheet does not
      // keep a stale, closed repository.
      try {
        final freshAccess =
            await (widget.dataAccessLoader ??
                () => LibraryDataAccess.instance)();
        if (!mounted) return;
        _dataAccess = freshAccess;
        _repository = freshAccess.repository;
      } catch (_) {
        // Reopen is best effort; the next launch rebuilds the singleton.
      }
      setState(() => _status = '恢复失败：$error，当前书库未受影响');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _restoreProgressStage = null;
          _restoreProgressValue = null;
        });
      }
    }
  }

  Future<String?> _pickBackupFilePath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 FluidText 备份',
      type: FileType.custom,
      allowedExtensions: const ['zip', 'json'],
      withData: false,
    );
    return result?.files.firstOrNull?.path;
  }

  Future<String> _writePreRestoreBackup() async {
    final repository = _repository;
    if (repository == null) {
      throw StateError('书库尚未加载，无法备份');
    }
    final layout = await AppStorageResolver.activeRuntimeLayout();
    final file = await PreRestoreBackup.write(
      repository: repository,
      layout: layout,
    );
    return file.path;
  }

  Future<BackupRestoreResult> _runBackupRestore(File backupFile) async {
    final layout = await AppStorageResolver.activeRuntimeLayout();
    return const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: layout,
      closeLiveDatabase: () async {
        await (await LibraryDataAccess.instance).close();
      },
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _restoreProgressStage = progress.stage;
          _restoreProgressValue = progress.fraction;
        });
      },
    );
  }

  Future<void> _deleteBook(Book book) async {
    final repository = _repository;
    if (repository == null || _isBusy) return;
    final title = _displayTitle(book);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('将删除《$title》及其所有卡片，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _isBusy = true;
      _status = '正在删除…';
    });

    try {
      await repository.deleteBook(book.id);
      await _dataAccess?.removeRemark(book.id);
      await _reloadBooks();
      if (!mounted) return;
      setState(() {
        _selectedIds.remove(book.id);
        _remarks.remove(book.id);
        _status = '已删除《$title》';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '删除失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _editRemark(Book book) async {
    if (_isBusy) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => _BookRemarkDialog(
        initialValue: _remarks[book.id] ?? book.title,
        originalTitle: book.title,
      ),
    );
    if (result == null) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _status = '正在保存备注…';
    });

    try {
      await _dataAccess?.saveRemark(book.id, result);
      final trimmed = result.trim();
      if (!mounted) return;
      setState(() {
        if (trimmed.isEmpty) {
          _remarks.remove(book.id);
          _status = '已清除《${book.title}》的备注';
        } else {
          _remarks[book.id] = trimmed;
          _status = '已备注为《$trimmed》';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '备注保存失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  String _displayTitle(Book book) => _remarks[book.id] ?? book.title;

  List<Book> _selectedBooks() {
    return _books.where((book) => _selectedIds.contains(book.id)).toList();
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (_selectedIds.contains(book.id)) {
        _selectedIds.remove(book.id);
      } else {
        _selectedIds.add(book.id);
      }
    });
  }

  void _close() {
    Navigator.of(context).pop(List<Book>.unmodifiable(_selectedBooks()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope<List<Book>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Stack(
              children: [
                Glass(
                  color: cs.surface.withValues(alpha: isDark ? 0.46 : 0.84),
                  borderColor: cs.outlineVariant.withValues(
                    alpha: isDark ? 0.2 : 0.32,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                        child: Row(
                          children: [
                            Text(
                              '书架',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            if (_showMigrationEntry)
                              IconButton(
                                tooltip: '重新检测旧数据并迁移',
                                onPressed: _isBusy ? null : _redetectMigration,
                                icon: const Icon(Icons.restore_rounded),
                              ),
                            IconButton(
                              tooltip: '导入 EPUB',
                              onPressed: _isBusy ? null : _pickAndImportEpub,
                              icon: const Icon(Icons.add_rounded),
                            ),
                            IconButton(
                              tooltip: '导出备份',
                              onPressed: _isBusy ? null : _exportBackup,
                              icon: const Icon(Icons.ios_share_rounded),
                            ),
                            IconButton(
                              tooltip: '导入备份',
                              onPressed: _isBusy ? null : _importBackup,
                              icon: const Icon(
                                Icons.settings_backup_restore_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: _close,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '备份为 ZIP 格式，包含书库、阅读数据、阅读背景与导入字体；也可以导入 1.0.0 旧版导出的备份（旧版备份不含阅读背景与字体）',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _status!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      const Divider(height: 1),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _books.isEmpty
                            ? Center(
                                child: Text(
                                  '还没有书',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  84,
                                ),
                                itemCount: _books.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final book = _books[index];
                                  final selected = _selectedIds.contains(
                                    book.id,
                                  );
                                  final remark = _remarks[book.id];
                                  final displayTitle = _displayTitle(book);
                                  final stats =
                                      _stats[book.id] ?? BookCardStats.empty;

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: _isBusy
                                          ? null
                                          : () => _toggleSelected(book),
                                      child: Ink(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? cs.secondaryContainer
                                                    .withValues(alpha: 0.7)
                                              : cs.surfaceContainerHigh
                                                    .withValues(alpha: 0.52),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: selected,
                                              onChanged: _isBusy
                                                  ? null
                                                  : (_) =>
                                                        _toggleSelected(book),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    displayTitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.copyWith(
                                                          fontWeight: selected
                                                              ? FontWeight.w700
                                                              : FontWeight.w500,
                                                        ),
                                                  ),
                                                  if (remark != null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      book.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 7),
                                                  _BookProgress(stats: stats),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              enabled: !_isBusy,
                                              tooltip: '更多',
                                              icon: const Icon(
                                                Icons.more_horiz_rounded,
                                                size: 22,
                                              ),
                                              onSelected: (value) {
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) {
                                                      if (!mounted) return;
                                                      switch (value) {
                                                        case 'remark':
                                                          _editRemark(book);
                                                          break;
                                                        case 'delete':
                                                          _deleteBook(book);
                                                          break;
                                                      }
                                                    });
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'remark',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.edit_note_rounded,
                                                    ),
                                                    title: Text('备注'),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                    ),
                                                    title: Text('删除'),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _close,
                      child: Ink(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Icon(
                          Icons.done_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isBusy)
                  BlockingLoader(
                    label: _restoreProgressStage ?? _importProgressLabel,
                    progress: _restoreProgressValue ?? _importProgressValue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportLengthOption extends StatelessWidget {
  const _ImportLengthOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          ),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookRemarkDialog extends StatefulWidget {
  const _BookRemarkDialog({
    required this.initialValue,
    required this.originalTitle,
  });

  final String initialValue;
  final String originalTitle;

  @override
  State<_BookRemarkDialog> createState() => _BookRemarkDialogState();
}

class _BookRemarkDialogState extends State<_BookRemarkDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('备注书名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '备注名',
          hintText: widget.originalTitle,
          helperText: '留空会清除备注，原书名不会被修改',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _BookProgress extends StatelessWidget {
  const _BookProgress({required this.stats});

  final BookCardStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (stats.readProgress * 100).round();
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: stats.readProgress,
            minHeight: 3,
            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            color: cs.primary.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已读 ${stats.readCount}/${stats.totalCount} · $percent% · 收藏 ${stats.favoriteCount}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        ),
      ],
    );
  }
}
