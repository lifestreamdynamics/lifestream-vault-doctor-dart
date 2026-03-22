import 'dart:io';

import '../types.dart';

/// Collects device context using `dart:io` [Platform].
///
/// Works in Flutter, CLI, and server Dart environments.
/// Not available on web (dart:io is unsupported on web).
///
/// Usage:
/// ```dart
/// doctor.setDeviceContextProvider(getDartIoDeviceContext);
/// ```
DeviceContext getDartIoDeviceContext() => DeviceContext(
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      locale: Platform.localeName,
    );
