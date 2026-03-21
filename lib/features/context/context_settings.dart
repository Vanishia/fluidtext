class ContextSettings {
  const ContextSettings({
    this.before = 2,
    this.after = 2,
  });

  final int before;
  final int after;

  ContextSettings copyWith({
    int? before,
    int? after,
  }) {
    return ContextSettings(
      before: before ?? this.before,
      after: after ?? this.after,
    );
  }
}
