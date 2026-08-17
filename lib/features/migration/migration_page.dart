import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../migration/app_bootstrap_coordinator.dart';
import '../../migration/legacy_backup_exporter.dart';
import '../../migration/library_migrator.dart';
import '../../migration/migration_progress.dart';
import '../../migration/migration_runner.dart';
import '../../repositories/library_change_tracker.dart';
import '../../services/backup/backup_restore_service.dart';
import '../../services/migration_notification_service.dart';
import '../../storage/storage_layout.dart';
import '../../theme/app_theme.dart';
import '../reader/reader_background_settings.dart';

/// Factory for the legacy ZIP backup exporter used by the migration page.
typedef LegacyBackupExporterFactory =
    LegacyBackupExporter Function(AppBootstrapDecision decision);

/// Runs a backup restore for the migration page's "导入备份恢复" entry.
/// Injectable for widget tests; the production default picks a file and
/// restores it into the target layout (no live database exists yet, so the
/// close callback is a no-op).
typedef MigrationRestoreRunner =
    Future<BackupRestoreResult> Function(StorageLayout targetLayout);

/// Light-weight app tree shown while migration is pending. Uses the default
/// seed color and does not touch the settings services or repositories.
class MigrationRootApp extends StatelessWidget {
  const MigrationRootApp({
    super.key,
    required this.decision,
    required this.onEnterApp,
    this.runTask,
    this.exporterFactory,
    this.restoreRunner,
    this.decideAgain,
    this.abandonHandler,
    this.retryCleanupHandler,
    this.throttleInterval = const Duration(milliseconds: 150),
  });

  final AppBootstrapDecision decision;
  final Future<void> Function() onEnterApp;
  final MigrationRunTask? runTask;
  final LegacyBackupExporterFactory? exporterFactory;
  final MigrationRestoreRunner? restoreRunner;
  final Future<AppBootstrapDecision> Function()? decideAgain;
  final Future<void> Function(StorageLayout targetLayout)? abandonHandler;
  final Future<void> Function(StorageLayout targetLayout)? retryCleanupHandler;
  final Duration throttleInterval;

  @override
  Widget build(BuildContext context) {
    final seed = readerBackgroundPalettes.first.color;
    return MaterialApp(
      title: 'FluidText',
      theme: buildAppTheme(brightness: Brightness.light, seedColor: seed),
      darkTheme: buildAppTheme(brightness: Brightness.dark, seedColor: seed),
      builder: (context, child) {
        final theme = Theme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemUiOverlayStyleForTheme(theme),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MigrationPage(
        decision: decision,
        onEnterApp: onEnterApp,
        runTask: runTask,
        exporterFactory: exporterFactory,
        restoreRunner: restoreRunner,
        decideAgain: decideAgain,
        abandonHandler: abandonHandler,
        retryCleanupHandler: retryCleanupHandler,
        throttleInterval: throttleInterval,
      ),
    );
  }
}

/// Full-screen route that re-runs the bootstrap decision (used by the
/// bookshelf "重新检测旧数据并迁移" entry). Pops itself when there is nothing
/// to migrate.
class MigrationBootstrapPage extends StatefulWidget {
  const MigrationBootstrapPage({
    super.key,
    this.decide,
    this.runTask,
    this.exporterFactory,
  });

  final Future<AppBootstrapDecision> Function()? decide;
  final MigrationRunTask? runTask;
  final LegacyBackupExporterFactory? exporterFactory;

  @override
  State<MigrationBootstrapPage> createState() =>
      _MigrationBootstrapPageState();
}

class _MigrationBootstrapPageState extends State<MigrationBootstrapPage> {
  AppBootstrapDecision? _decision;
  bool _nothingToMigrate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final decide =
        widget.decide ?? () => const AppBootstrapCoordinator().decide();
    final decision = await decide();
    if (!mounted) return;
    final needsMigration =
        decision.action == AppBootstrapAction.migrationRequired ||
        decision.action == AppBootstrapAction.recoveryRequired ||
        decision.action == AppBootstrapAction.migrationUnavailable;
    setState(() {
      _decision = needsMigration ? decision : null;
      _nothingToMigrate = !needsMigration;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_nothingToMigrate) {
      return Scaffold(
        appBar: AppBar(title: const Text('数据迁移')),
        body: const Center(child: Text('未检测到需要迁移的旧数据。')),
      );
    }
    final decision = _decision;
    if (decision == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MigrationPage(
      decision: decision,
      runTask: widget.runTask,
      exporterFactory: widget.exporterFactory,
      onEnterApp: () async {
        LibraryChangeTracker.instance.markChanged();
        Navigator.of(context).maybePop();
      },
    );
  }
}

enum _MigrationPageStatus {
  detected,
  exportingBackup,
  restoringBackup,
  ready,
  migrating,
  validating,
  success,
  failed,
}

/// The blocking migration page (plan section 6).
class MigrationPage extends StatefulWidget {
  const MigrationPage({
    super.key,
    required this.decision,
    required this.onEnterApp,
    this.runTask,
    this.exporterFactory,
    this.restoreRunner,
    this.decideAgain,
    this.abandonHandler,
    this.retryCleanupHandler,
    this.throttleInterval = const Duration(milliseconds: 150),
  });

  final AppBootstrapDecision decision;
  final Future<void> Function() onEnterApp;
  final MigrationRunTask? runTask;
  final LegacyBackupExporterFactory? exporterFactory;

  /// Runs the ZIP/JSON backup restore for the "导入备份恢复" entry.
  /// Defaults to [_restoreFromPickedBackup]; injectable for tests.
  final MigrationRestoreRunner? restoreRunner;
  final Future<AppBootstrapDecision> Function()? decideAgain;

  /// Performs the abandon-migration work (state, staging cleanup, fresh
  /// database). Defaults to [abandonMigration]; injectable for tests.
  final Future<void> Function(StorageLayout targetLayout)? abandonHandler;

  /// Cleans up incomplete migration state before a retry. Defaults to
  /// [prepareMigrationRetry]; injectable for tests.
  final Future<void> Function(StorageLayout targetLayout)? retryCleanupHandler;
  final Duration throttleInterval;

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  static const _phaseLabels = <MigrationPhase, String>{
    MigrationPhase.detectingLegacyData: '检测旧数据',
    MigrationPhase.copyingDatabase: '复制数据库副本',
    MigrationPhase.readingBooks: '读取书籍',
    MigrationPhase.migratingCards: '迁移卡片',
    MigrationPhase.migratingRemarksAndAssets: '迁移备注与资源',
    MigrationPhase.copyingBookAssets: '复制书籍图片',
    MigrationPhase.migratingSettings: '迁移设置',
    MigrationPhase.validating: '校验数据库与文件',
    MigrationPhase.finalizing: '完成切换',
  };

  late AppBootstrapDecision _decision = widget.decision;
  late final MigrationProgressThrottler _throttler =
      MigrationProgressThrottler(minInterval: widget.throttleInterval);

  _MigrationPageStatus _status = _MigrationPageStatus.detected;
  bool _backupCompleted = false;
  MigrationProgressEvent? _event;
  MigrationException? _error;
  MigrationRunResult? _result;
  bool _busy = false;

  bool get _isRunning =>
      _status == _MigrationPageStatus.migrating ||
      _status == _MigrationPageStatus.validating ||
      _status == _MigrationPageStatus.exportingBackup ||
      _status == _MigrationPageStatus.restoringBackup;

  /// The "导入备份恢复" entry is a low-key escape hatch for states where
  /// automatic migration is stuck (failure, recovery, untrusted source); it
  /// is deliberately hidden on the normal first-run flow so it does not
  /// dilute the "backup first, then migrate" guidance.
  bool get _showRestoreEntry =>
      !_isRunning &&
      (_status == _MigrationPageStatus.failed ||
          _status == _MigrationPageStatus.detected &&
              (_decision.action == AppBootstrapAction.recoveryRequired ||
                  _decision.action ==
                      AppBootstrapAction.migrationUnavailable));

  double? get _overallFraction {
    final event = _event;
    if (event == null) return null;
    final within = event.fraction ?? 0;
    return (event.phase.index + within) / MigrationPhase.values.length;
  }

  // -- actions ----------------------------------------------------------

  Future<void> _exportBackup() async {
    final legacyLayout = _decision.legacyLayout;
    if (legacyLayout == null || _busy) return;
    final exporter =
        widget.exporterFactory?.call(_decision) ??
        LegacyBackupExporter(legacyLayout: legacyLayout);
    setState(() {
      _busy = true;
      _status = _MigrationPageStatus.exportingBackup;
    });
    // The export can take a while on large libraries; keep the process
    // alive via the foreground notification while the user is away.
    final notifications = MigrationNotificationService.instance;
    await notifications.ensurePermission();
    await notifications.start(title: '正在导出旧数据备份', text: '导出中请勿退出应用');
    try {
      final path = await exporter.exportToPickedFile();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (path == null) {
          _status = _backupCompleted
              ? _MigrationPageStatus.ready
              : _MigrationPageStatus.detected;
        } else {
          _backupCompleted = true;
          _status = _MigrationPageStatus.ready;
        }
      });
      _showSnackBar(path == null ? '已取消导出备份' : '备份已导出，可以开始迁移');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = _backupCompleted
            ? _MigrationPageStatus.ready
            : _MigrationPageStatus.detected;
      });
      _showSnackBar('备份导出失败：${_errorText(error)}');
    } finally {
      await notifications.stop();
    }
  }

  Future<void> _startMigration() async {
    if (!_backupCompleted) {
      final confirmed = await _confirm(
        title: '跳过备份并继续？',
        content: '旧数据仍会保留，但没有额外 ZIP 备份。',
        confirmLabel: '继续迁移',
      );
      if (!confirmed) return;
    }
    await _runMigration();
  }

  Future<void> _runMigration() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = _MigrationPageStatus.migrating;
      _event = null;
      _error = null;
    });
    final task = widget.runTask ?? MigrationRunner.runDecision;
    // One-shot migration of the whole library: run as a foreground service
    // on Android so the system does not kill the app mid-migration when the
    // user switches away.
    final notifications = MigrationNotificationService.instance;
    await notifications.ensurePermission();
    await notifications.start(title: '正在迁移数据', text: '迁移中请勿退出应用');
    try {
      final result = await task(decision: _decision, onProgress: _onProgress);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
        _status = _MigrationPageStatus.success;
      });
    } on MigrationException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
        _status = _MigrationPageStatus.failed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = MigrationException(
          phase: _event?.phase ?? MigrationPhase.copyingDatabase,
          message: '迁移失败',
          diagnostic: _errorText(error),
        );
        _status = _MigrationPageStatus.failed;
      });
    } finally {
      await notifications.stop();
    }
  }

  void _onProgress(MigrationProgressEvent event) {
    if (!_throttler.allow(event) || !mounted) return;
    setState(() {
      _event = event;
      if (event.phase.index >= MigrationPhase.validating.index) {
        _status = _MigrationPageStatus.validating;
      }
    });
    _updateMigrationNotification(event);
  }

  /// Mirrors the in-page progress into the foreground notification. Called
  /// on the same throttle as the UI rebuild; failures are logged and
  /// swallowed by the service.
  void _updateMigrationNotification(MigrationProgressEvent event) {
    final label = _phaseLabels[event.phase] ?? event.phase.name;
    final total = event.total;
    final text = total == null
        ? label
        : '$label（${event.completed} / $total）';
    final fraction = _overallFraction;
    MigrationNotificationService.instance.updateProgress(
      title: '正在迁移数据',
      text: text,
      percent: fraction == null ? null : (fraction * 100).round(),
    );
  }

  Future<void> _retryRecovery() async {
    if (_busy) return;
    setState(() => _busy = true);
    final target = _decision.targetLayout;
    final cleanup = widget.retryCleanupHandler ?? prepareMigrationRetry;
    await cleanup(target);
    final decide =
        widget.decideAgain ?? () => const AppBootstrapCoordinator().decide();
    final decision = await decide();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _decision = decision;
      _error = null;
      _event = null;
      _status = switch (decision.action) {
        AppBootstrapAction.migrationRequired =>
          _MigrationPageStatus.detected,
        _ => _MigrationPageStatus.failed,
      };
    });
    if (decision.action != AppBootstrapAction.migrationRequired) {
      _showSnackBar(decision.reason ?? '暂时无法重新迁移，请稍后重试');
    }
  }

  Future<void> _abandonMigration() async {
    final confirmed = await _confirm(
      title: '放弃迁移并进入空书架？',
      content: '当前书架为空，旧数据仍在原位置。之后可在书架中重新检测旧数据并迁移，或导入备份。',
      confirmLabel: '放弃迁移',
    );
    if (!confirmed || _busy) return;
    setState(() => _busy = true);
    final abandon = widget.abandonHandler ?? abandonMigration;
    await abandon(_decision.targetLayout);
    if (!mounted) return;
    await widget.onEnterApp();
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Restores a picked v2/v3 backup directly into the target layout — the
  /// escape hatch when automatic migration cannot proceed. No live database
  /// exists in this state, so there is nothing to close before the swap.
  Future<void> _restoreFromBackup() async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: '导入备份恢复？',
      content: '将用备份文件替换目标书库；旧数据仍保留在原位置，不受影响。',
      confirmLabel: '选择备份文件',
    );
    if (!confirmed || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _status = _MigrationPageStatus.restoringBackup;
    });
    // A large restore can take a while; keep the process alive via the
    // foreground notification like the migration itself.
    final notifications = MigrationNotificationService.instance;
    await notifications.ensurePermission();
    await notifications.start(title: '正在恢复备份', text: '恢复中请勿退出应用');
    try {
      final runner = widget.restoreRunner ?? _runBackupRestore;
      final result = await runner(_decision.targetLayout);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = null;
        _error = null;
      });
      _showSnackBar(
        '备份恢复完成${result.formatVersion == 2 ? '（1.0.0 旧版备份）' : ''}：书籍 ${result.bookCount} 本 · '
        '卡片 ${result.cardCount} 张 · 警告 ${result.warnings.length} 条',
      );
      await widget.onEnterApp();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Stay on the previous state; the error is surfaced as a snackbar
        // so the migration options remain available.
        if (_status == _MigrationPageStatus.restoringBackup) {
          _status = _MigrationPageStatus.failed;
          _error = MigrationException(
            phase: MigrationPhase.finalizing,
            message: '备份恢复失败',
            diagnostic: _errorText(error),
          );
        }
      });
      _showSnackBar('备份恢复失败：${_errorText(error)}');
    } finally {
      await notifications.stop();
    }
  }

  /// Production default for [MigrationPage.restoreRunner]: pick a backup
  /// file and restore it into the target layout.
  Future<BackupRestoreResult> _runBackupRestore(StorageLayout targetLayout) {
    return _pickBackupFile().then((path) {
      if (path == null || path.isEmpty) {
        throw const FormatException('未选择备份文件');
      }
      return const BackupRestoreService().restore(
        backupFile: File(path),
        targetLayout: targetLayout,
        closeLiveDatabase: () async {},
      );
    });
  }

  Future<String?> _pickBackupFile() {
    return FilePicker.platform.pickFiles(
      dialogTitle: '选择 FluidText 备份',
      type: FileType.custom,
      allowedExtensions: const ['zip', 'json'],
      withData: false,
    ).then((result) => result?.files.firstOrNull?.path);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) =>
      error is LegacyBackupException ? error.message : error.toString();

  // -- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRunning,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('数据迁移'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: switch (_decision.action) {
                AppBootstrapAction.migrationUnavailable =>
                  _buildUnavailable(context),
                _ => _buildMigrationFlow(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '无法自动迁移旧数据',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          '检测到无法确认的 default.isar 文件，为避免误迁移其他应用的数据，'
          'FluidText 不会自动处理它。\n\n'
          '如果其中有你的书库，请在旧版本中导出 ZIP 备份，然后在新书架中使用"导入备份"恢复。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _abandonMigration,
          child: const Text('进入空书架'),
        ),
        if (_showRestoreEntry) _buildRestoreEntry(context),
      ],
    );
  }

  Widget _buildMigrationFlow(BuildContext context) {
    return switch (_status) {
      _MigrationPageStatus.migrating ||
      _MigrationPageStatus.validating => _buildProgress(context),
      _MigrationPageStatus.restoringBackup => _buildRestoring(context),
      _MigrationPageStatus.success => _buildSuccess(context),
      _MigrationPageStatus.failed => _buildFailed(context),
      _ => _buildDetected(context),
    };
  }

  Widget _buildDetected(BuildContext context) {
    final isRecovery =
        _decision.action == AppBootstrapAction.recoveryRequired;
    final exporting = _status == _MigrationPageStatus.exportingBackup;
    final legacyPath = _decision.legacyLayout?.rootDirectory.path;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isRecovery ? '迁移需要继续' : '发现旧版本数据',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          isRecovery
              ? '${_decision.reason ?? '上次迁移未完成。'}\n旧数据仍保留在原位置，可以直接重试。'
              : 'FluidText 需要把旧版本的书库迁移到新的存储位置与格式。\n'
                  '旧数据位置：${legacyPath ?? '应用文档目录'}\n'
                  '迁移只读取旧数据，不会修改或删除旧文件。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (_backupCompleted) ...[
          const SizedBox(height: 10),
          Text(
            '备份已完成，可以开始迁移。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy || _decision.legacyLayout == null
              ? null
              : _exportBackup,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(exporting ? '正在导出备份…' : '导出 ZIP 备份'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _busy || !_backupCompleted ? null : _startMigration,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('开始迁移'),
        ),
        TextButton(
          onPressed: _busy || _backupCompleted ? null : _startMigration,
          child: const Text('跳过备份并继续'),
        ),
        if (isRecovery || _showRestoreEntry) ...[
          if (isRecovery)
            TextButton(
              onPressed: _busy ? null : _retryRecovery,
              child: const Text('重新检测并迁移'),
            ),
          if (isRecovery)
            TextButton(
              onPressed: _busy ? null : _abandonMigration,
              child: Text(
                '放弃迁移并进入空书架',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_showRestoreEntry) _buildRestoreEntry(context),
        ],
      ],
    );
  }

  /// Low-key restore entry (grey small text) shown only in stuck states.
  Widget _buildRestoreEntry(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton(
        onPressed: _busy ? null : _restoreFromBackup,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          textStyle: Theme.of(context).textTheme.bodySmall,
        ),
        child: const Text('已有备份文件？导入备份恢复'),
      ),
    );
  }

  Widget _buildRestoring(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '正在恢复备份',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          '请不要关闭应用；旧数据不会被修改。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final event = _event;
    final phaseLabel = event == null
        ? '正在准备…'
        : _phaseLabels[event.phase] ?? event.phase.name;
    final total = event?.total;
    final countText = event == null || total == null
        ? null
        : '${event.completed} / $total';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _status == _MigrationPageStatus.validating ? '正在校验' : '正在迁移',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        LinearProgressIndicator(value: _overallFraction),
        const SizedBox(height: 12),
        Text(
          countText == null ? phaseLabel : '$phaseLabel（$countText）',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '请不要关闭应用；旧数据不会被修改。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final result = _result;
    final warnings = result?.warnings ?? const <String>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '迁移完成',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          '书籍 ${result?.bookCount ?? 0} 本 · 卡片 ${result?.cardCount ?? 0} 张 · '
          '备注 ${result?.remarkCount ?? 0} 条\n'
          '警告 ${warnings.length} 条；旧数据仍保留在原位置。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '若迁移后发现图片缺失，可在书架中重新导入备份文件。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  await widget.onEnterApp();
                },
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('进入应用'),
        ),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '迁移失败',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '旧数据仍保留，未被删除。\n'
          '你可以重试，也可以先导出 ZIP 备份；如果稍后重装应用或进入新书架，可使用"导入备份"恢复。',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _runMigration,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试迁移'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _busy || _decision.legacyLayout == null
              ? null
              : _exportBackup,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('导出 ZIP 备份'),
        ),
        TextButton(
          onPressed: _busy ? null : _abandonMigration,
          child: Text(
            '放弃迁移并进入空书架',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        if (_showRestoreEntry) _buildRestoreEntry(context),
        if (error != null) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('错误详情'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '阶段：${error.phase.name}\n${error.message}'
                  '${error.diagnostic == null ? '' : '\n${error.diagnostic}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: _diagnosticText(error)),
                  );
                  _showSnackBar('已复制诊断信息');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制诊断信息'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _diagnosticText(MigrationException error) {
    return 'FluidText 迁移诊断\n阶段: ${error.phase.name}\n信息: ${error.message}\n'
        '诊断: ${error.diagnostic ?? '无'}';
  }
}
