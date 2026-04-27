class ContextSettings {
  static const minCount = 1;
  static const maxCount = 6;
  static const defaultCount = 2;

  const ContextSettings({
    this.before = defaultCount,
    this.after = defaultCount,
  });

  final int before;
  final int after;

  ContextSettings copyWith({int? before, int? after}) {
    return ContextSettings(
      before: before ?? this.before,
      after: after ?? this.after,
    );
  }
}
