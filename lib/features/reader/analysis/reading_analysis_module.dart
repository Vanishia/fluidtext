enum ReadingAnalysisModuleType {
  overview,
  heatmap,
  streaks,
  activity,
  rankings,
  depth,
  favorites,
}

const defaultReadingAnalysisModuleOrder = <ReadingAnalysisModuleType>[
  ReadingAnalysisModuleType.overview,
  ReadingAnalysisModuleType.heatmap,
  ReadingAnalysisModuleType.streaks,
  ReadingAnalysisModuleType.activity,
  ReadingAnalysisModuleType.rankings,
  ReadingAnalysisModuleType.depth,
  ReadingAnalysisModuleType.favorites,
];

List<ReadingAnalysisModuleType> normalizeReadingAnalysisModuleOrder(
  Iterable<Object?>? values,
) {
  final resolved = <ReadingAnalysisModuleType>[];

  if (values != null) {
    for (final value in values) {
      if (value is! String) continue;
      final match = ReadingAnalysisModuleType.values.where(
        (item) => item.name == value,
      );
      if (match.isEmpty) continue;
      final module = match.first;
      if (!resolved.contains(module)) {
        resolved.add(module);
      }
    }
  }

  for (final module in defaultReadingAnalysisModuleOrder) {
    if (!resolved.contains(module)) {
      resolved.add(module);
    }
  }

  return List<ReadingAnalysisModuleType>.unmodifiable(resolved);
}
