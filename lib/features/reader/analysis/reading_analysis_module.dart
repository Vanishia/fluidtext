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
      ReadingAnalysisModuleType? module;
      if (value is ReadingAnalysisModuleType) {
        module = value;
      } else if (value is String) {
        for (final item in ReadingAnalysisModuleType.values) {
          if (item.name == value) {
            module = item;
            break;
          }
        }
      }
      if (module == null) continue;
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
