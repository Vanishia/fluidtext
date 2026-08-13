import '../storage/storage_layout.dart';
import 'legacy_source.dart';
import 'migration_promotion.dart';
import 'migration_state.dart';

/// Bootstrap outcomes of the plan 5.1 startup state machine.
enum AppBootstrapAction {
  /// No trusted legacy data and no live SQLite: start with a fresh database.
  freshInstall,

  /// Live SQLite exists and the completion marker verifies against it.
  normalStart,

  /// Trusted legacy data exists and there is no complete live SQLite.
  migrationRequired,

  /// A previous migration attempt or an incomplete live database was found;
  /// the user must retry or recover. Staging is never used as the live
  /// database.
  recoveryRequired,

  /// A `default.isar` file exists but cannot be confirmed as FluidText
  /// data; the user must restore from a ZIP backup instead (plan 11.5).
  migrationUnavailable,
}

/// Result of [AppBootstrapCoordinator.decide].
class AppBootstrapDecision {
  const AppBootstrapDecision({
    required this.action,
    required this.targetLayout,
    this.legacyLayout,
    this.detection,
    this.state = MigrationStateSnapshot.idle,
    this.marker,
    this.reason,
  });

  final AppBootstrapAction action;
  final StorageLayout targetLayout;

  /// Resolved legacy layout when legacy detection ran.
  final StorageLayout? legacyLayout;

  /// Legacy probe result when detection ran.
  final LegacySourceDetection? detection;

  final MigrationStateSnapshot state;
  final MigrationCompletionMarker? marker;

  /// Chinese diagnostic for recovery/unavailable outcomes.
  final String? reason;
}

/// Pure-logic bootstrap coordinator (plan 5.1).
///
/// Decides between fresh start, normal start, migration and recovery before
/// any normal repository is opened. All legacy inspection is read-only (the
/// probe works on temporary copies). No Flutter dependencies; the migration
/// page wires this up in a later commit.
class AppBootstrapCoordinator {
  const AppBootstrapCoordinator({
    StorageLayoutProvider? legacyLayoutProvider,
    StorageLayoutProvider? targetLayoutProvider,
    AppStoragePlatform Function()? platformProvider,
    AppBuildMode Function()? buildModeProvider,
    LegacySourceProbe Function(StorageLayout layout)? probeFactory,
    Future<bool> Function(StorageLayout, MigrationCompletionMarker)?
    liveDatabaseVerifier,
  }) : _legacyLayoutProvider = legacyLayoutProvider,
       _targetLayoutProvider = targetLayoutProvider,
       _platformProvider = platformProvider ?? _defaultPlatform,
       _buildModeProvider = buildModeProvider ?? _defaultBuildMode,
       _probeFactory = probeFactory ?? _defaultProbeFactory,
       _liveDatabaseVerifier =
           liveDatabaseVerifier ?? MigrationCompletion.verifyLiveDatabase;

  final StorageLayoutProvider? _legacyLayoutProvider;
  final StorageLayoutProvider? _targetLayoutProvider;
  final AppStoragePlatform Function() _platformProvider;
  final AppBuildMode Function() _buildModeProvider;
  final LegacySourceProbe Function(StorageLayout layout) _probeFactory;

  /// Full verification of the live database against the completion marker.
  /// Runs once after each migration/promotion; later cold starts trust the
  /// recorded verification instead of re-scanning the whole database.
  final Future<bool> Function(StorageLayout, MigrationCompletionMarker)
  _liveDatabaseVerifier;

  static AppStoragePlatform _defaultPlatform() => AppStoragePlatform.current;

  static AppBuildMode _defaultBuildMode() => AppBuildMode.current;

  static LegacySourceProbe _defaultProbeFactory(StorageLayout layout) {
    return LegacySourceProbe(legacyLayout: layout);
  }

  Future<AppBootstrapDecision> decide() async {
    final targetLayout = await (_targetLayoutProvider ??
            AppStorageResolver.targetRuntimeLayout)();
    final stateStore = MigrationStateStore(targetLayout: targetLayout);
    final state = await stateStore.load();
    final marker = await MigrationCompletion.load(targetLayout);
    final databaseExists = await targetLayout.sqliteDatabaseFile.exists();

    AppBootstrapDecision decision(
      AppBootstrapAction action, {
      String? reason,
      StorageLayout? legacyLayout,
      LegacySourceDetection? detection,
    }) {
      return AppBootstrapDecision(
        action: action,
        targetLayout: targetLayout,
        legacyLayout: legacyLayout,
        detection: detection,
        state: state,
        marker: marker,
        reason: reason,
      );
    }

    if (databaseExists) {
      if (marker == null) {
        return decision(
          AppBootstrapAction.recoveryRequired,
          reason: '检测到不完整的新数据库（缺少迁移完成标记），需要恢复或重新迁移',
        );
      }
      // A database verified once after migration is trusted on later cold
      // starts; a full integrity_check on every launch can take seconds.
      if (state.liveDatabaseVerified) {
        return decision(AppBootstrapAction.normalStart);
      }
      final valid = await _liveDatabaseVerifier(targetLayout, marker);
      if (valid) {
        await stateStore.markLiveDatabaseVerified();
        return decision(AppBootstrapAction.normalStart);
      }
      return decision(
        AppBootstrapAction.recoveryRequired,
        reason: '迁移完成标记与当前数据库不一致，需要恢复',
      );
    }

    if (marker != null) {
      return decision(
        AppBootstrapAction.recoveryRequired,
        reason: '迁移完成标记存在但新数据库缺失，需要恢复',
      );
    }

    if (state.status == MigrationLifecycleStatus.migrating ||
        state.status == MigrationLifecycleStatus.failed) {
      return decision(
        AppBootstrapAction.recoveryRequired,
        reason: state.status == MigrationLifecycleStatus.migrating
            ? '上次迁移未完成，可以重试；旧数据仍保留在原位置'
            : '上次迁移失败：${state.message ?? '未知原因'}；旧数据仍保留在原位置',
      );
    }

    if (await MigrationRecovery.hasAttempts(targetLayout)) {
      return decision(
        AppBootstrapAction.recoveryRequired,
        reason: '检测到未完成的迁移暂存数据，需要恢复或重试',
      );
    }

    if (state.status == MigrationLifecycleStatus.abandoned) {
      // The user explicitly abandoned migration; start fresh and keep the
      // legacy data untouched for a later ZIP-based restore.
      return decision(AppBootstrapAction.freshInstall);
    }

    // Legacy detection. Auto-scanning the real Documents directory is only
    // enabled on Windows Release (or non-Windows); Debug/Profile builds must
    // inject an explicit fixture layout instead.
    final legacyProvider = _legacyLayoutProvider;
    StorageLayout legacyLayout;
    if (legacyProvider != null) {
      legacyLayout = await legacyProvider();
    } else {
      final platform = _platformProvider();
      final buildMode = _buildModeProvider();
      final autoScanAllowed =
          platform != AppStoragePlatform.windows ||
          buildMode == AppBuildMode.release;
      if (!autoScanAllowed) {
        return decision(AppBootstrapAction.freshInstall);
      }
      legacyLayout = await const AppStorageResolver().legacyLayout();
    }

    final detection = await _probeFactory(legacyLayout).detect();
    return switch (detection.status) {
      LegacySourceStatus.trusted => decision(
        AppBootstrapAction.migrationRequired,
        legacyLayout: legacyLayout,
        detection: detection,
      ),
      LegacySourceStatus.unstable => decision(
        AppBootstrapAction.recoveryRequired,
        legacyLayout: legacyLayout,
        detection: detection,
        reason: '旧数据可能仍被旧实例或同步软件写入，请关闭后重试',
      ),
      LegacySourceStatus.untrusted => decision(
        AppBootstrapAction.migrationUnavailable,
        legacyLayout: legacyLayout,
        detection: detection,
        reason: '检测到无法确认的 default.isar 文件，请使用 ZIP 备份恢复',
      ),
      LegacySourceStatus.absent => decision(
        AppBootstrapAction.freshInstall,
        legacyLayout: legacyLayout,
        detection: detection,
      ),
    };
  }
}
