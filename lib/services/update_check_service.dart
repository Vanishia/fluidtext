import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_logger.dart';

/// GitHub 上一个 release 里可下载的附件。
class UpdateAsset {
  const UpdateAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

/// 远端发现的可用新版本。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.notes,
    required this.releasePageUrl,
    required this.assets,
  });

  /// 形如 `v1.2.1` 的 tag（去掉前导 v 后的版本号见 [plainVersion]）。
  final String version;

  /// release 的说明正文（Markdown 原文）。
  final String notes;

  /// release 页面地址，没有匹配附件时作为下载兜底。
  final String releasePageUrl;

  final List<UpdateAsset> assets;

  String get plainVersion =>
      version.startsWith('v') ? version.substring(1) : version;

  /// 按当前平台挑一个最可能合适的下载附件；挑不到返回 null。
  UpdateAsset? preferredAsset() {
    if (assets.isEmpty) return null;
    if (Platform.isAndroid) {
      return _firstWhere((asset) => asset.name.endsWith('.apk'));
    }
    if (Platform.isWindows) {
      return _firstWhere(
        (asset) =>
            asset.name.toLowerCase().contains('windows') &&
            (asset.name.endsWith('.zip') || asset.name.endsWith('.exe')),
      );
    }
    if (Platform.isMacOS) {
      return _firstWhere((asset) => asset.name.toLowerCase().contains('mac'));
    }
    if (Platform.isLinux) {
      return _firstWhere((asset) => asset.name.toLowerCase().contains('linux'));
    }
    return null;
  }

  UpdateAsset? _firstWhere(bool Function(UpdateAsset asset) test) {
    for (final asset in assets) {
      if (test(asset)) return asset;
    }
    return null;
  }

  /// 下载地址：优先平台附件，否则回退到 release 页面。
  String get downloadUrl => preferredAsset()?.downloadUrl ?? releasePageUrl;
}

/// 比较两个版本号（允许 `v` 前缀和 `+构建号`），远端更新时返回 true。
bool isRemoteVersionNewer(String currentVersion, String remoteVersion) {
  final current = _VersionParts.parse(currentVersion);
  final remote = _VersionParts.parse(remoteVersion);
  if (current == null || remote == null) return false;
  for (var i = 0; i < 3; i++) {
    if (remote.numbers[i] != current.numbers[i]) {
      return remote.numbers[i] > current.numbers[i];
    }
  }
  return remote.build > current.build;
}

class _VersionParts {
  _VersionParts(this.numbers, this.build);

  final List<int> numbers;
  final int build;

  static _VersionParts? parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v')) value = value.substring(1);
    final buildSplit = value.split('+');
    final core = buildSplit.first.split('.');
    if (core.isEmpty || core.length > 3) return null;
    final numbers = <int>[];
    for (final part in core) {
      final number = int.tryParse(part);
      if (number == null) return null;
      numbers.add(number);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    final build = buildSplit.length > 1
        ? int.tryParse(buildSplit[1]) ?? 0
        : 0;
    return _VersionParts(numbers, build);
  }
}

/// 启动时后台检查 GitHub 最新 release，发现更新版本时通过
/// [availableUpdate] 暴露给侧边栏通知块。所有失败都只记日志，不影响使用。
class UpdateCheckService {
  UpdateCheckService._();

  static final instance = UpdateCheckService._();

  static const _latestReleaseUrl =
      'https://api.github.com/repos/Vanishia/fluidtext/releases/latest';

  /// 当前发现的可用更新；为 null 表示已是最新或尚未检查。
  final availableUpdate = ValueNotifier<AppUpdateInfo?>(null);

  bool _checked = false;

  /// 检查一次更新；重复调用直接忽略（一次会话只查一次）。
  Future<void> checkForUpdate() async {
    if (_checked || kIsWeb) return;
    _checked = true;
    try {
      final info = await _fetchLatestRelease();
      if (info == null) return;
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.buildNumber.isEmpty
          ? packageInfo.version
          : '${packageInfo.version}+${packageInfo.buildNumber}';
      if (isRemoteVersionNewer(current, info.version)) {
        availableUpdate.value = info;
      }
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'UpdateCheck',
        '检查更新失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AppUpdateInfo?> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set(HttpHeaders.acceptHeader,
          'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FluidText-App');
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        AppLogger.instance.warning(
          'UpdateCheck',
          '检查更新返回 ${response.statusCode}',
        );
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String?;
      if (tagName == null || tagName.isEmpty) return null;
      final assets = <UpdateAsset>[];
      for (final asset in json['assets'] as List<dynamic>? ?? const []) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'] as String?;
        final url = asset['browser_download_url'] as String?;
        if (name != null && url != null) {
          assets.add(UpdateAsset(name: name, downloadUrl: url));
        }
      }
      return AppUpdateInfo(
        version: tagName,
        notes: (json['body'] as String?)?.trim() ?? '',
        releasePageUrl: (json['html_url'] as String?) ??
            'https://github.com/Vanishia/fluidtext/releases/latest',
        assets: assets,
      );
    } finally {
      client.close();
    }
  }
}
