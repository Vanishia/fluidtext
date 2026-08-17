import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/migration_progress.dart';

void main() {
  group('MigrationProgressEvent', () {
    test('fraction is null without total and clamped otherwise', () {
      expect(
        const MigrationProgressEvent(
          phase: MigrationPhase.migratingCards,
          completed: 5,
        ).fraction,
        isNull,
      );
      expect(
        const MigrationProgressEvent(
          phase: MigrationPhase.migratingCards,
          completed: 1,
          total: 4,
        ).fraction,
        0.25,
      );
      expect(
        const MigrationProgressEvent(
          phase: MigrationPhase.migratingCards,
          completed: 9,
          total: 4,
        ).fraction,
        1.0,
      );
      expect(
        const MigrationProgressEvent(
          phase: MigrationPhase.migratingCards,
          completed: 0,
          total: 0,
        ).fraction,
        isNull,
      );
    });
  });

  group('MigrationProgressThrottler', () {
    test('merges events inside the interval', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final throttler = MigrationProgressThrottler(
        minInterval: const Duration(milliseconds: 150),
        clock: () => now,
      );
      const phase = MigrationPhase.migratingCards;

      // First event of a phase always passes.
      expect(
        throttler.allow(
          const MigrationProgressEvent(phase: phase, completed: 0, total: 10),
        ),
        isTrue,
      );
      // Inside the interval: dropped.
      now = now.add(const Duration(milliseconds: 50));
      expect(
        throttler.allow(
          const MigrationProgressEvent(phase: phase, completed: 1, total: 10),
        ),
        isFalse,
      );
      // After the interval: passes.
      now = now.add(const Duration(milliseconds: 150));
      expect(
        throttler.allow(
          const MigrationProgressEvent(phase: phase, completed: 2, total: 10),
        ),
        isTrue,
      );
    });

    test('phase changes and completion events are never dropped', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final throttler = MigrationProgressThrottler(
        minInterval: const Duration(milliseconds: 150),
        clock: () => now,
      );

      expect(
        throttler.allow(
          const MigrationProgressEvent(
            phase: MigrationPhase.migratingCards,
            completed: 1,
            total: 2,
          ),
        ),
        isTrue,
      );
      // Completion passes even inside the interval.
      now = now.add(const Duration(milliseconds: 10));
      expect(
        throttler.allow(
          const MigrationProgressEvent(
            phase: MigrationPhase.migratingCards,
            completed: 2,
            total: 2,
          ),
        ),
        isTrue,
      );
      // First event of the next phase passes immediately.
      now = now.add(const Duration(milliseconds: 10));
      expect(
        throttler.allow(
          const MigrationProgressEvent(
            phase: MigrationPhase.migratingSettings,
            completed: 0,
            total: 4,
          ),
        ),
        isTrue,
      );
    });

    test('bind forwards only allowed events', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final throttler = MigrationProgressThrottler(
        minInterval: const Duration(milliseconds: 150),
        clock: () => now,
      );
      final received = <MigrationProgressEvent>[];
      final listener = throttler.bind(received.add);
      const phase = MigrationPhase.copyingDatabase;

      listener(
        const MigrationProgressEvent(phase: phase, completed: 0, total: 3),
      );
      now = now.add(const Duration(milliseconds: 10));
      listener(
        const MigrationProgressEvent(phase: phase, completed: 1, total: 3),
      );
      now = now.add(const Duration(milliseconds: 10));
      listener(
        const MigrationProgressEvent(phase: phase, completed: 2, total: 3),
      );
      listener(
        const MigrationProgressEvent(phase: phase, completed: 3, total: 3),
      );

      expect(received.map((event) => event.completed), [0, 3]);
    });
  });
}
