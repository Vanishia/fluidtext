/// Phases of the one-shot legacy Isar → SQLite migration.
///
/// The order matches the execution order; UI can rely on phases never
/// moving backwards within one migration run.
enum MigrationPhase {
  detectingLegacyData,
  copyingDatabase,
  readingBooks,
  migratingCards,
  migratingRemarksAndAssets,
  copyingBookAssets,
  migratingSettings,
  validating,
  finalizing,
}

/// One migration progress update.
///
/// [completed] and [total] use the natural unit of the phase (bytes for copy
/// phases, record counts otherwise). [total] is null while the total is not
/// yet known.
class MigrationProgressEvent {
  const MigrationProgressEvent({
    required this.phase,
    required this.completed,
    this.total,
  });

  final MigrationPhase phase;
  final int completed;
  final int? total;

  /// Progress within the phase in 0..1, or null when [total] is unknown.
  double? get fraction {
    final total = this.total;
    if (total == null || total <= 0) return null;
    return (completed / total).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'MigrationProgressEvent($phase, $completed/${total ?? '?'})';
}

typedef MigrationProgressCallback = void Function(MigrationProgressEvent event);

/// Rate-limits progress events for UI consumption.
///
/// The first event of every phase and the completion event of every phase
/// (completed >= total) always pass; intermediate events pass at most once
/// per [minInterval].
class MigrationProgressThrottler {
  MigrationProgressThrottler({
    this.minInterval = const Duration(milliseconds: 150),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration minInterval;
  final DateTime Function() _clock;

  MigrationPhase? _lastPhase;
  DateTime? _lastEmittedAt;

  /// Returns true when [event] should be forwarded to listeners.
  bool allow(MigrationProgressEvent event) {
    final now = _clock();
    final phaseChanged = event.phase != _lastPhase;
    final total = event.total;
    final isCompletion = total != null && event.completed >= total;
    final intervalElapsed =
        _lastEmittedAt == null ||
        now.difference(_lastEmittedAt!) >= minInterval;
    if (phaseChanged || isCompletion || intervalElapsed) {
      _lastPhase = event.phase;
      _lastEmittedAt = now;
      return true;
    }
    return false;
  }

  /// Wraps [listener] so it only receives allowed events.
  MigrationProgressCallback bind(MigrationProgressCallback listener) {
    return (event) {
      if (allow(event)) listener(event);
    };
  }
}
