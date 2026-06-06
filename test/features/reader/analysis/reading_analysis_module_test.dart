import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/reading_analysis_module.dart';

void main() {
  group('normalizeReadingAnalysisModuleOrder', () {
    test('preserves enum values and appends missing defaults', () {
      final normalized = normalizeReadingAnalysisModuleOrder([
        ReadingAnalysisModuleType.favorites,
        ReadingAnalysisModuleType.overview,
      ]);

      expect(normalized.take(2), [
        ReadingAnalysisModuleType.favorites,
        ReadingAnalysisModuleType.overview,
      ]);
      expect(normalized.toSet(), ReadingAnalysisModuleType.values.toSet());
    });

    test('preserves string values and removes duplicates', () {
      final normalized = normalizeReadingAnalysisModuleOrder([
        'activity',
        'heatmap',
        'activity',
        'unknown',
      ]);

      expect(normalized.take(2), [
        ReadingAnalysisModuleType.activity,
        ReadingAnalysisModuleType.heatmap,
      ]);
      expect(
        normalized.where((item) => item == ReadingAnalysisModuleType.activity),
        hasLength(1),
      );
    });
  });
}
