class LibraryChangeTracker {
  LibraryChangeTracker._();

  static final instance = LibraryChangeTracker._();

  int _revision = 0;

  int get revision => _revision;

  void markChanged() {
    _revision += 1;
  }
}
