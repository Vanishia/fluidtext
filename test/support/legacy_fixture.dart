import 'dart:io';

/// Root of the checked-in 1.0.0 legacy Isar fixture.
final Directory legacyFixtureRoot = Directory('test/fixtures/legacy_isar_1_0_0');

/// Copies the legacy fixture into [target], which must not exist yet.
Future<Directory> copyLegacyFixture(Directory target) async {
  await copyDirectoryRecursive(legacyFixtureRoot, target);
  return target;
}

Future<void> copyDirectoryRecursive(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: false, followLinks: false)) {
    final targetPath =
        '${target.path}${Platform.pathSeparator}${pathBaseName(entity.path)}';
    if (entity is Directory) {
      await copyDirectoryRecursive(entity, Directory(targetPath));
    } else if (entity is File) {
      await entity.copy(targetPath);
    }
  }
}

String pathBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
