import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/update_check_service.dart';

void main() {
  group('isRemoteVersionNewer', () {
    test('远端主/次/补丁版本更高时判定为有新版本', () {
      expect(isRemoteVersionNewer('1.1.0+2', 'v1.2.1'), isTrue);
      expect(isRemoteVersionNewer('1.1.0', '1.1.1'), isTrue);
      expect(isRemoteVersionNewer('1.1.0', '2.0.0'), isTrue);
    });

    test('相同或更低版本不提示', () {
      expect(isRemoteVersionNewer('1.2.1+3', 'v1.2.1'), isFalse);
      expect(isRemoteVersionNewer('1.2.1', 'v1.2.1'), isFalse);
      expect(isRemoteVersionNewer('1.2.1', 'v1.1.9'), isFalse);
      expect(isRemoteVersionNewer('2.0.0', 'v1.9.9'), isFalse);
    });

    test('语义版本相同时比较构建号', () {
      expect(isRemoteVersionNewer('1.1.0+2', 'v1.1.0+3'), isTrue);
      expect(isRemoteVersionNewer('1.1.0+2', 'v1.1.0+2'), isFalse);
      expect(isRemoteVersionNewer('1.1.0+2', 'v1.1.0+1'), isFalse);
    });

    test('允许 v 前缀和缺省的段', () {
      expect(isRemoteVersionNewer('1.1', 'v1.1.1'), isTrue);
      expect(isRemoteVersionNewer('1.1.0', 'v1.1'), isFalse);
    });

    test('无法解析的版本不提示', () {
      expect(isRemoteVersionNewer('1.1.0', 'beta'), isFalse);
      expect(isRemoteVersionNewer('unknown', 'v1.2.1'), isFalse);
    });
  });
}
