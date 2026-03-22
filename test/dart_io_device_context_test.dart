import 'dart:io';

import 'package:lifestream_doctor/src/adapters/dart_io_device_context.dart';
import 'package:test/test.dart';

void main() {
  group('getDartIoDeviceContext', () {
    test('returns a DeviceContext with platform info', () {
      final ctx = getDartIoDeviceContext();
      expect(ctx.platform, equals(Platform.operatingSystem));
      expect(ctx.osVersion, equals(Platform.operatingSystemVersion));
      expect(ctx.locale, equals(Platform.localeName));
    });

    test('platform is a non-empty string', () {
      final ctx = getDartIoDeviceContext();
      expect(ctx.platform, isNotEmpty);
    });

    test('osVersion is a non-empty string', () {
      final ctx = getDartIoDeviceContext();
      expect(ctx.osVersion, isNotEmpty);
    });

    test('deviceName, appVersion, timezone are null', () {
      final ctx = getDartIoDeviceContext();
      expect(ctx.deviceName, isNull);
      expect(ctx.appVersion, isNull);
      expect(ctx.timezone, isNull);
    });

    test('extras is empty', () {
      final ctx = getDartIoDeviceContext();
      expect(ctx.extras, isEmpty);
    });
  });
}
