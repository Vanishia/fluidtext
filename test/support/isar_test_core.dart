import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:isar/isar.dart';

Future<void> initializeIsarTestCore() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString());
  final packages = config['packages'] as List<dynamic>;
  final package = packages.cast<Map<String, dynamic>>().singleWhere(
    (entry) => entry['name'] == 'isar_flutter_libs',
  );
  final packageRoot = configFile.uri.resolve(package['rootUri'] as String);
  final packageRootDirectory = Directory.fromUri(packageRoot);

  final relativeLibraryPath = switch (Platform.operatingSystem) {
    'windows' => 'windows/isar.dll',
    'linux' => 'linux/libisar.so',
    'macos' => 'macos/libisar.dylib',
    _ => throw UnsupportedError(
      'Isar integration tests are not supported on '
      '${Platform.operatingSystem}',
    ),
  };
  final library = File(
    '${packageRootDirectory.path}${Platform.pathSeparator}'
    '${relativeLibraryPath.replaceAll('/', Platform.pathSeparator)}',
  );
  if (!await library.exists()) {
    throw StateError('Isar test library not found at ${library.path}');
  }

  await Isar.initializeIsarCore(libraries: {Abi.current(): library.path});
}
