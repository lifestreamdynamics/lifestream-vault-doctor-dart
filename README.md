# lifestream_doctor

Crash reporting SDK for Lifestream Vault — captures exceptions and uploads them as searchable, taggable Markdown documents via the Vault API.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Dart port of [`@lifestreamdynamics/doctor`](https://github.com/lifestreamdynamics/lifestream-vault-doctor) — produces format-compatible reports and uses the same HMAC-SHA256 signing protocol.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Platform Compatibility](#platform-compatibility)
- [API Reference](#api-reference)
  - [LifestreamDoctor](#lifestreamdoctor)
  - [Consent Methods](#consent-methods)
  - [captureException](#captureexception)
  - [captureMessage](#capturemessage)
  - [addBreadcrumb](#addbreadcrumb)
  - [setDeviceContextProvider](#setdevicecontextprovider)
  - [flushQueue](#flushqueue)
- [DoctorOptions](#doctoroptions)
- [Flutter Integration](#flutter-integration)
- [Document Format](#document-format)
- [Consent Management](#consent-management)
- [beforeSend Filter](#beforesend-filter)
- [Offline Queue](#offline-queue)
- [Custom Context](#custom-context)
- [Cross-Platform Signing Compatibility](#cross-platform-signing-compatibility)
- [License](#license)

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  lifestream_doctor: ^1.0.0
```

Or install from git:

```yaml
dependencies:
  lifestream_doctor:
    git:
      url: https://github.com/lifestreamdynamics/lifestream-vault-doctor-dart.git
```

Then run:

```bash
dart pub get
```

---

## Quick Start

```dart
import 'package:lifestream_doctor/lifestream_doctor.dart';

final doctor = LifestreamDoctor(
  apiUrl: 'https://vault.example.com',
  vaultId: 'your-vault-id',
  apiKey: 'lsv_k_your_api_key',
  environment: 'production',
);

// Crash reports are only uploaded after the user grants consent.
await doctor.grantConsent();

// Capture an exception manually.
try {
  await riskyOperation();
} catch (e, stack) {
  await doctor.captureException(e, stackTrace: stack, severity: Severity.error);
}
```

Each captured exception becomes a Markdown document inside your vault, searchable by error name, severity, tag, date, or any text in the stack trace.

---

## Platform Compatibility

This is a **pure Dart package** with no Flutter dependency. It works in:

- **Flutter** apps (iOS, Android, macOS, Linux, Windows)
- **Dart CLI** tools and scripts
- **Dart server** applications

The package depends only on `package:http`, `package:crypto`, and `package:uuid` — all pure Dart.

The built-in device context adapter (`getDartIoDeviceContext`) uses `dart:io` and is available everywhere except Dart web. For web targets, implement a custom `DeviceContextProvider`.

---

## API Reference

### LifestreamDoctor

```dart
import 'package:lifestream_doctor/lifestream_doctor.dart';

final doctor = LifestreamDoctor(
  apiUrl: 'https://vault.example.com',
  vaultId: 'your-vault-id',
  apiKey: 'lsv_k_your_api_key',
);
```

The main SDK class. Manages consent state, breadcrumb history, the offline queue, and report upload. A new session ID is generated on construction and included in every report produced by this instance.

---

### Consent Methods

#### `grantConsent()`

```dart
Future<void> grantConsent()
```

Marks consent as granted in the configured storage backend and enables report uploads.

#### `revokeConsent()`

```dart
Future<void> revokeConsent()
```

Revokes consent and clears the pending offline queue. Subsequent calls to `captureException` and `captureMessage` silently no-op until consent is re-granted.

#### `isConsentGranted()`

```dart
Future<bool> isConsentGranted()
```

Returns `true` if consent is currently active.

#### `setConsentPreVerified()`

```dart
void setConsentPreVerified()
```

Sets an in-memory flag that bypasses the async storage read in `captureException`. This eliminates the race window where an exception thrown immediately after `grantConsent()` could be dropped because the storage write has not yet completed.

```dart
await doctor.grantConsent();
doctor.setConsentPreVerified();
// Exceptions captured immediately after this point are guaranteed to be processed
```

---

### captureException

```dart
Future<void> captureException(
  Object error, {
  StackTrace? stackTrace,
  Severity severity = Severity.error,
  Map<String, Object?>? extra,
  String? componentStack,
  List<String>? tags,
})
```

Builds a crash report from the error and current breadcrumb buffer, runs it through `beforeSend` (if configured), and uploads it to the vault. If the upload fails, the report is placed in the offline queue for later retry via `flushQueue()`.

Duplicate errors (same error type and message) are suppressed within the `rateLimitWindowMs` window to prevent report storms.

```dart
try {
  await placeOrder();
} catch (e, stack) {
  await doctor.captureException(
    e,
    stackTrace: stack,
    severity: Severity.fatal,
    tags: ['checkout', 'payment'],
    extra: {'orderId': 'ord_123', 'userId': 'usr_456'},
  );
}
```

---

### captureMessage

```dart
Future<void> captureMessage(
  String message, {
  Severity severity = Severity.info,
  Map<String, Object?>? extra,
})
```

Captures a plain message (not an exception) as a crash report. Useful for logging degraded states or manual checkpoints.

```dart
await doctor.captureMessage(
  'Payment gateway returned unexpected status code 202',
  severity: Severity.warning,
  extra: {'gatewayResponse': rawBody},
);
```

---

### addBreadcrumb

```dart
void addBreadcrumb(Breadcrumb crumb)
```

Adds an event to the breadcrumb buffer. The buffer holds the most recent `maxBreadcrumbs` entries (default 50); older entries are evicted automatically. Timestamps are auto-set by the buffer if missing.

```dart
doctor.addBreadcrumb(Breadcrumb(
  timestamp: DateTime.now().toUtc().toIso8601String(),
  type: 'navigation',
  message: 'Navigated to /checkout',
));
doctor.addBreadcrumb(Breadcrumb(
  timestamp: DateTime.now().toUtc().toIso8601String(),
  type: 'http',
  message: 'POST /api/v1/orders',
  data: {'statusCode': 500, 'durationMs': 342},
));
```

---

### setDeviceContextProvider

```dart
void setDeviceContextProvider(DeviceContextProvider provider)
```

Registers a function that returns device and runtime context. Called at capture time (not construction), so it always reflects current state. Use the built-in adapter or provide your own:

```dart
// Built-in dart:io adapter
doctor.setDeviceContextProvider(getDartIoDeviceContext);

// Custom provider with app-specific context
doctor.setDeviceContextProvider(() => DeviceContext(
  platform: Platform.operatingSystem,
  osVersion: Platform.operatingSystemVersion,
  appVersion: '2.1.0',
  timezone: DateTime.now().timeZoneName,
  locale: Platform.localeName,
  extras: {'memoryMB': ProcessInfo.currentRss ~/ 1000000},
));
```

---

### flushQueue

```dart
Future<FlushResult> flushQueue()
```

Attempts to upload all reports in the offline queue. Returns a summary:

```dart
final result = await doctor.flushQueue();
// result.sent, result.failed, result.deadLettered
```

Call `flushQueue()` when the device comes back online or on app resume.

---

## DoctorOptions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `apiUrl` | `String` | required | Base URL of your Vault instance |
| `vaultId` | `String` | required | UUID of the target vault |
| `apiKey` | `String` | required | API key with write scope (`lsv_k_` prefix) |
| `environment` | `String` | `'production'` | Environment tag in every report |
| `enabled` | `bool` | `true` | Master switch. When `false`, all capture calls no-op |
| `maxBreadcrumbs` | `int` | `50` | Maximum breadcrumb buffer size |
| `rateLimitWindowMs` | `int` | `60000` | Suppression window (ms) for duplicate errors |
| `pathPrefix` | `String` | `'crash-reports'` | Document path prefix |
| `tags` | `List<String>?` | `[]` | Tags attached to every report |
| `beforeSend` | `CrashReport? Function(CrashReport)?` | `null` | Filter/transform reports before upload |
| `storage` | `StorageBackend?` | `MemoryStorage` | Persistence backend for queue and consent |
| `enableRequestSigning` | `bool` | `true` | Sign uploads with HMAC-SHA256 |
| `signRequest` | `CustomSignRequest?` | `null` | Custom signing function |
| `debug` | `bool` | `false` | Enable debug logging via `dart:developer` |
| `httpClient` | `http.Client?` | `null` | Custom HTTP client (useful for testing) |

### Disabled instances

When `enabled: false`, credential fields are not validated:

```dart
final doctor = LifestreamDoctor(
  apiUrl: '',
  vaultId: '',
  apiKey: '',
  enabled: false, // All capture calls return immediately
);
```

---

## Flutter Integration

This package is pure Dart by design. Flutter-specific integration requires a few lines of glue code in your app.

### Error Hooks

Install global error handlers in your `main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'dart:ui';

void installFlutterErrorHandlers(LifestreamDoctor doctor) {
  FlutterError.onError = (details) {
    doctor.captureException(
      details.exception,
      stackTrace: details.stack,
      severity: Severity.fatal,
      extra: {'library': details.library},
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    doctor.captureException(
      error,
      stackTrace: stack,
      severity: Severity.fatal,
    );
    return true;
  };
}
```

### Hive Storage Backend

Persist the offline queue and consent state across app restarts:

```dart
import 'package:hive/hive.dart';

class HiveStorageBackend implements StorageBackend {
  final Box<String> _box;
  HiveStorageBackend(this._box);

  @override
  Future<String?> getItem(String key) async => _box.get(key);

  @override
  Future<void> setItem(String key, String value) async =>
      _box.put(key, value);

  @override
  Future<void> removeItem(String key) async => _box.delete(key);
}
```

### Riverpod Provider

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final doctorProvider = Provider<LifestreamDoctor>((ref) {
  final doctor = LifestreamDoctor(
    apiUrl: Environment.apiBaseUrl,
    vaultId: 'your-vault-id',
    apiKey: 'lsv_k_your_api_key',
    storage: HiveStorageBackend(Hive.box<String>('doctor')),
  );
  doctor.setDeviceContextProvider(getDartIoDeviceContext);
  return doctor;
});
```

### AppInitializer Integration

```dart
Future<void> initializeApp() async {
  // ... other init steps ...

  final doctor = LifestreamDoctor(
    apiUrl: Environment.apiBaseUrl,
    vaultId: 'your-vault-id',
    apiKey: 'lsv_k_your_api_key',
    storage: HiveStorageBackend(await Hive.openBox<String>('doctor')),
  );
  doctor.setDeviceContextProvider(getDartIoDeviceContext);

  // Grant consent (call after user agrees in your UI)
  await doctor.grantConsent();
  doctor.setConsentPreVerified();

  // Install Flutter error handlers
  installFlutterErrorHandlers(doctor);

  // Flush any reports queued from previous sessions
  await doctor.flushQueue();
}
```

### Flush on Connectivity Change

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

Connectivity().onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    doctor.flushQueue();
  }
});
```

---

## Document Format

Each crash report is stored as a Markdown document with YAML frontmatter. The path follows this pattern:

```
{pathPrefix}/{YYYY-MM-DD}/{errorname-lowercase}-{first8charsOfId}.md
```

For example: `crash-reports/2026-03-13/stateerror-a3f2c1b0.md`

The document format is identical to the TypeScript SDK, ensuring cross-platform compatibility within the same vault.

### Example Document

```markdown
---
title: "[ERROR] StateError: Bad state: No element"
tags:
  - severity:error
  - env:production
  - stateerror
date: 2026-03-13T14:23:01.482Z
severity: error
device: ios
os: Version 17.4 (Build 21E219)
appVersion: 2.1.0
sessionId: f47ac10b-58cc-4372-a567-0e02b2c3d479
environment: production
---

## Stack Trace

\```
Bad state: No element
#0      List.first (dart:core/list.dart:101:5)
#1      CheckoutScreen._getSelectedItem (checkout_screen.dart:142:18)
#2      CheckoutScreen._handlePlaceOrder (checkout_screen.dart:87:22)
\```

## Breadcrumbs

| Time | Type | Message |
|------|------|---------|
| 2026-03-13T14:22:58.100Z | navigation | Navigated to /checkout |
| 2026-03-13T14:23:00.340Z | http | POST /api/v1/orders |
| 2026-03-13T14:23:01.100Z | user | Tapped "Place Order" button |

## Device Context

- **platform**: ios
- **osVersion**: Version 17.4 (Build 21E219)
- **locale**: en-CA

## Additional Context

\```json
{
  "orderId": "ord_missing",
  "cartItems": 3
}
\```
```

---

## Consent Management

Crash reporting is gated on explicit user consent. `captureException` and `captureMessage` are silent no-ops until `grantConsent()` is called. This design satisfies GDPR Article 7 and PIPEDA Principle 3.

Consent state is persisted in the configured `StorageBackend` so it survives app restarts.

```dart
// Show your consent UI, then:
Future<void> onUserAcceptsReporting() async {
  await doctor.grantConsent();
}

Future<void> onUserDeclinesReporting() async {
  await doctor.revokeConsent(); // Queue cleared, captures suppressed
}

// Check on startup to restore UI state
final hasConsent = await doctor.isConsentGranted();
if (!hasConsent) {
  showConsentBanner();
}
```

---

## beforeSend Filter

Register a `beforeSend` callback to inspect, transform, or discard reports before upload.

### Redacting PII

```dart
final doctor = LifestreamDoctor(
  // ...
  beforeSend: (report) {
    if (report.extra?['userEmail'] != null) {
      return report.copyWith(
        extra: {...report.extra!, 'userEmail': '[redacted]'},
      );
    }
    return report;
  },
);
```

### Discarding Reports

```dart
final doctor = LifestreamDoctor(
  // ...
  beforeSend: (report) {
    // Don't report known benign errors
    if (report.errorMessage.contains('ResizeObserver')) return null;
    return report;
  },
);
```

`beforeSend` is called synchronously. Avoid expensive work inside it.

---

## Offline Queue

When a report upload fails, the report is placed in the offline queue rather than being dropped.

### Queue Behaviour

- Maximum queue size: **50 entries**. Oldest evicted when full.
- Maximum retry attempts: **5**. After 5 failures, the entry is dead-lettered and removed.
- The queue is NOT flushed automatically. Call `flushQueue()` to trigger.

### Custom StorageBackend

Implement `StorageBackend` to adapt to any storage mechanism:

```dart
class SharedPrefsStorageBackend implements StorageBackend {
  final SharedPreferences _prefs;
  SharedPrefsStorageBackend(this._prefs);

  @override
  Future<String?> getItem(String key) async => _prefs.getString(key);

  @override
  Future<void> setItem(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> removeItem(String key) async => _prefs.remove(key);
}
```

---

## Custom Context

Add arbitrary structured data to individual reports:

```dart
await doctor.captureException(error, stackTrace: stack, extra: {
  'userId': currentUser.id,
  'planTier': subscription.tier,
  'requestId': response.headers['x-request-id'],
});
```

Extra context payloads over 50 KB are replaced with an error marker. Circular references are handled gracefully.

Add custom tags to every report via the constructor:

```dart
final doctor = LifestreamDoctor(
  // ...
  tags: ['flutter', 'mobile', 'version:2.1.0'],
);
```

---

## Cross-Platform Signing Compatibility

This Dart SDK uses the same HMAC-SHA256 signing protocol as the TypeScript `@lifestreamdynamics/doctor` package. Signatures produced by either SDK are verified by the same server-side logic. The canonical payload format is:

```
METHOD\nPATH\nTIMESTAMP\nNONCE\nBODY_SHA256
```

The Dart implementation uses `package:crypto` (synchronous), while the TypeScript version uses Web Crypto API (async). The output is identical for the same inputs.

---

## License

MIT — see [LICENSE](./LICENSE) for details.
