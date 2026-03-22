import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifestream_doctor/src/lifestream_doctor.dart';
import 'package:lifestream_doctor/src/memory_storage.dart';
import 'package:lifestream_doctor/src/storage_backend.dart';
import 'package:lifestream_doctor/src/types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

/// Helper to build a [LifestreamDoctor] with sensible test defaults.
///
/// Request signing is disabled by default to simplify mock verification.
LifestreamDoctor makeDoctor({
  String apiUrl = 'https://vault.example.com',
  String vaultId = 'test-vault',
  String apiKey = 'lsv_k_test',
  String environment = 'production',
  bool enabled = true,
  int maxBreadcrumbs = 50,
  int rateLimitWindowMs = 60000,
  String pathPrefix = 'crash-reports',
  List<String>? tags,
  CrashReport? Function(CrashReport)? beforeSend,
  StorageBackend? storage,
  bool enableRequestSigning = false,
  CustomSignRequest? signRequest,
  bool debug = false,
  http.Client? httpClient,
}) {
  return LifestreamDoctor(
    apiUrl: apiUrl,
    vaultId: vaultId,
    apiKey: apiKey,
    environment: environment,
    enabled: enabled,
    maxBreadcrumbs: maxBreadcrumbs,
    rateLimitWindowMs: rateLimitWindowMs,
    pathPrefix: pathPrefix,
    tags: tags,
    beforeSend: beforeSend,
    storage: storage,
    enableRequestSigning: enableRequestSigning,
    signRequest: signRequest,
    debug: debug,
    httpClient: httpClient,
  );
}

/// Stubs a successful PUT on [mockClient] with the given [statusCode].
void stubPut(MockHttpClient mockClient, {int statusCode = 200}) {
  when(
    () => mockClient.put(
      any(),
      headers: any(named: 'headers'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async => http.Response('', statusCode));
}

/// Stubs a PUT that throws an exception to simulate network failures.
void stubPutThrows(MockHttpClient mockClient, Object error) {
  when(
    () => mockClient.put(
      any(),
      headers: any(named: 'headers'),
      body: any(named: 'body'),
    ),
  ).thenThrow(error);
}

/// Returns the captured body argument from the most recent PUT call.
Map<String, Object?> capturePutBody(MockHttpClient mockClient) {
  final captured = verify(
    () => mockClient.put(
      any(),
      headers: any(named: 'headers'),
      body: captureAny(named: 'body'),
    ),
  ).captured;
  return jsonDecode(captured.first as String) as Map<String, Object?>;
}

/// Returns the content field from the most recent PUT call body.
String capturePutContent(MockHttpClient mockClient) {
  final body = capturePutBody(mockClient);
  return body['content'] as String;
}

void main() {
  late MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  setUp(() {
    mockClient = MockHttpClient();
  });

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  group('constructor', () {
    test('throws ArgumentError when apiUrl is empty and enabled', () {
      expect(
        () => makeDoctor(apiUrl: ''),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('apiUrl'),
          ),
        ),
      );
    });

    test('throws ArgumentError when vaultId is empty and enabled', () {
      expect(
        () => makeDoctor(vaultId: ''),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('vaultId'),
          ),
        ),
      );
    });

    test('throws ArgumentError when apiKey is empty and enabled', () {
      expect(
        () => makeDoctor(apiKey: ''),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('apiKey'),
          ),
        ),
      );
    });

    test('does NOT throw when disabled with empty credentials', () {
      expect(
        () => makeDoctor(
          apiUrl: '',
          vaultId: '',
          apiKey: '',
          enabled: false,
        ),
        returnsNormally,
      );
    });

    test('creates successfully with valid options', () {
      expect(
        () => makeDoctor(httpClient: mockClient),
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Consent
  // ---------------------------------------------------------------------------

  group('consent', () {
    test('captureException silently returns when no consent', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);

      await doctor.captureException(StateError('boom'));

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('captureException works after grantConsent', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);

      await doctor.grantConsent();
      await doctor.captureException(StateError('boom'));

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('revokeConsent clears queue and resets preVerified', () async {
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
      );

      // Pre-verify and capture — upload will fail, so report goes to queue.
      stubPutThrows(mockClient, Exception('network error'));
      doctor.setConsentPreVerified();
      await doctor.captureException(StateError('queued'));

      // Revoke consent.
      await doctor.revokeConsent();

      // After revoking, pre-verified is false and consent is not granted.
      expect(await doctor.isConsentGranted(), isFalse);

      // Reset mock to track only new calls.
      reset(mockClient);
      registerFallbackValue(Uri.parse('http://example.com'));
      stubPut(mockClient);

      // Capture should be silently dropped now (no consent).
      await doctor.captureException(StateError('dropped'));

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('setConsentPreVerified bypasses async consent check', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);

      // No grantConsent called, but pre-verified.
      doctor.setConsentPreVerified();
      await doctor.captureException(StateError('boom'));

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('isConsentGranted returns false initially', () async {
      final doctor = makeDoctor(httpClient: mockClient);
      expect(await doctor.isConsentGranted(), isFalse);
    });

    test('isConsentGranted returns true after grant', () async {
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();
      expect(await doctor.isConsentGranted(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Rate limiting
  // ---------------------------------------------------------------------------

  group('rate limiting', () {
    test('same error blocked within window', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        rateLimitWindowMs: 60000,
      );
      await doctor.grantConsent();

      final error = StateError('same message');

      // First capture should succeed.
      await doctor.captureException(error);

      // Second capture with same error should be rate-limited.
      await doctor.captureException(error);

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Breadcrumbs
  // ---------------------------------------------------------------------------

  group('breadcrumbs', () {
    test('addBreadcrumb adds to buffer and appears in captured report',
        () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      doctor.addBreadcrumb(const Breadcrumb(
        timestamp: '2025-01-01T00:00:00.000Z',
        type: 'navigation',
        message: 'Opened settings',
      ));

      await doctor.captureException(StateError('test'));

      final content = capturePutContent(mockClient);
      expect(content, contains('Opened settings'));
      expect(content, contains('navigation'));
    });

    test('addBreadcrumb does nothing when disabled', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        enabled: false,
        apiUrl: '',
        vaultId: '',
        apiKey: '',
      );

      // Should not throw or do anything.
      doctor.addBreadcrumb(const Breadcrumb(
        timestamp: '2025-01-01T00:00:00.000Z',
        type: 'test',
        message: 'should be ignored',
      ));

      // Cannot verify buffer directly, but captureException should also no-op.
      await doctor.captureException(StateError('test'));

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Device context
  // ---------------------------------------------------------------------------

  group('device context', () {
    test('device context provider called during capture', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      doctor.setDeviceContextProvider(() async {
        return const DeviceContext(
          platform: 'android',
          osVersion: '14',
          appVersion: '2.0.0',
        );
      });

      await doctor.captureException(StateError('test'));

      final content = capturePutContent(mockClient);
      expect(content, contains('android'));
      expect(content, contains('2.0.0'));
    });

    test('device context provider error handled gracefully', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      doctor.setDeviceContextProvider(() async {
        throw Exception('context collection failed');
      });

      // Should not throw — report is still sent.
      await doctor.captureException(StateError('test'));

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // beforeSend
  // ---------------------------------------------------------------------------

  group('beforeSend', () {
    test('beforeSend can modify report', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        beforeSend: (report) {
          return report.copyWith(
            errorMessage: 'modified-message',
          );
        },
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('original'));

      final content = capturePutContent(mockClient);
      expect(content, contains('modified-message'));
    });

    test('beforeSend returning null discards report', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        beforeSend: (report) => null,
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('should be discarded'));

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Upload and queue fallback
  // ---------------------------------------------------------------------------

  group('upload and queue', () {
    test('successful upload calls uploadReport', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureException(StateError('test'));

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('failed upload enqueues to queue', () async {
      stubPutThrows(mockClient, Exception('network error'));
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('test'));

      // Verify the queue has an entry by checking storage.
      final queueData = await storage.getItem('doctor:queue');
      expect(queueData, isNotNull);
      final parsed = jsonDecode(queueData!) as List;
      expect(parsed, hasLength(1));
    });

    test('flushQueue calls uploadReport for queued items', () async {
      // First: fail the upload so it goes to queue.
      stubPutThrows(mockClient, Exception('network error'));
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
      );
      await doctor.grantConsent();
      await doctor.captureException(StateError('queued'));

      // Reset mock to succeed.
      reset(mockClient);
      stubPut(mockClient);

      final result = await doctor.flushQueue();
      expect(result.sent, equals(1));
      expect(result.failed, equals(0));
      expect(result.deadLettered, equals(0));

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('flushQueue returns empty result when no consent', () async {
      final doctor = makeDoctor(httpClient: mockClient);

      // No consent granted.
      final result = await doctor.flushQueue();

      expect(result.sent, equals(0));
      expect(result.failed, equals(0));
      expect(result.deadLettered, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // captureMessage
  // ---------------------------------------------------------------------------

  group('captureMessage', () {
    test('creates report with errorName CapturedMessage', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureMessage('Something happened');

      final content = capturePutContent(mockClient);
      expect(content, contains('CapturedMessage'));
      expect(content, contains('Something happened'));
    });

    test('uses default severity info', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureMessage('info message');

      final content = capturePutContent(mockClient);
      // Title should contain [INFO]
      expect(content, contains('[INFO]'));
      // Tags should contain severity:info
      expect(content, contains('severity:info'));
    });
  });

  // ---------------------------------------------------------------------------
  // Disabled
  // ---------------------------------------------------------------------------

  group('disabled', () {
    test('captureException silently returns when disabled', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        enabled: false,
        apiUrl: '',
        vaultId: '',
        apiKey: '',
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('should be ignored'));

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('addBreadcrumb silently returns when disabled', () {
      final doctor = makeDoctor(
        enabled: false,
        apiUrl: '',
        vaultId: '',
        apiKey: '',
      );

      // Should not throw.
      doctor.addBreadcrumb(const Breadcrumb(
        timestamp: '2025-01-01T00:00:00.000Z',
        type: 'test',
        message: 'ignored',
      ));
    });
  });

  // ---------------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------------

  group('tags', () {
    test('auto tags include severity, env, error name', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureException(
        StateError('test'),
        severity: Severity.warning,
      );

      final content = capturePutContent(mockClient);
      expect(content, contains('severity:warning'));
      expect(content, contains('env:production'));
      expect(content, contains('stateerror'));
    });

    test('global tags included', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        tags: ['team:backend', 'priority:high'],
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('test'));

      final content = capturePutContent(mockClient);
      expect(content, contains('team:backend'));
      expect(content, contains('priority:high'));
    });

    test('local tags included', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureException(
        StateError('test'),
        tags: ['feature:checkout', 'screen:payment'],
      );

      final content = capturePutContent(mockClient);
      expect(content, contains('feature:checkout'));
      expect(content, contains('screen:payment'));
    });

    test('tags are deduplicated', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        tags: ['shared-tag'],
      );
      await doctor.grantConsent();

      await doctor.captureException(
        StateError('test'),
        tags: ['shared-tag'],
      );

      final content = capturePutContent(mockClient);
      // Count occurrences of 'shared-tag' in the tags section.
      // The tags section uses '  - ' prefix for each tag in YAML.
      final tagLines = content
          .split('\n')
          .where((line) => line.trim() == '- shared-tag')
          .toList();
      expect(tagLines, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Extra and component stack
  // ---------------------------------------------------------------------------

  group('extra and componentStack', () {
    test('extra data included in report', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureException(
        StateError('test'),
        extra: {'userId': '123', 'screen': 'home'},
      );

      final content = capturePutContent(mockClient);
      expect(content, contains('userId'));
      expect(content, contains('123'));
      expect(content, contains('screen'));
      expect(content, contains('home'));
    });

    test('componentStack included in report', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      await doctor.captureException(
        StateError('test'),
        componentStack: 'Widget > Scaffold > Column',
      );

      final content = capturePutContent(mockClient);
      expect(content, contains('Component Stack'));
      expect(content, contains('Widget > Scaffold > Column'));
    });
  });

  // ---------------------------------------------------------------------------
  // Debug mode
  // ---------------------------------------------------------------------------

  group('debug mode', () {
    test('debug mode does not cause errors on upload failure', () async {
      stubPutThrows(mockClient, Exception('fail'));
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
        debug: true,
      );
      await doctor.grantConsent();

      // Should not throw — just log and enqueue.
      await doctor.captureException(StateError('debug test'));

      final queueData = await storage.getItem('doctor:queue');
      expect(queueData, isNotNull);
    });

    test('debug mode does not cause errors on flush', () async {
      stubPut(mockClient);
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
        debug: true,
      );
      await doctor.grantConsent();

      // Enqueue something first by failing.
      stubPutThrows(mockClient, Exception('fail'));
      await doctor.captureException(StateError('test'));

      // Now succeed on flush.
      reset(mockClient);
      stubPut(mockClient);
      final result = await doctor.flushQueue();
      expect(result.sent, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------

  group('environment', () {
    test('custom environment appears in report', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        environment: 'staging',
      );
      await doctor.grantConsent();

      await doctor.captureException(StateError('test'));

      final content = capturePutContent(mockClient);
      expect(content, contains('env:staging'));
      expect(content, contains('environment: staging'));
    });
  });

  // ---------------------------------------------------------------------------
  // close
  // ---------------------------------------------------------------------------

  group('close', () {
    test('closes internally created HTTP client', () {
      final doctor = makeDoctor();
      // Should not throw — the internal client is closed.
      doctor.close();
    });

    test('does not close user-provided HTTP client', () {
      final doctor = makeDoctor(httpClient: mockClient);
      doctor.close();
      // Verify close was NOT called on the user-provided mock client.
      verifyNever(() => mockClient.close());
    });
  });

  // ---------------------------------------------------------------------------
  // flushQueue with consentPreVerified
  // ---------------------------------------------------------------------------

  group('flushQueue with consentPreVerified', () {
    test('flushQueue works with consentPreVerified but no grantConsent',
        () async {
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
      );

      // Use pre-verified consent instead of grantConsent.
      doctor.setConsentPreVerified();

      // Force a failed upload to enqueue a report.
      stubPutThrows(mockClient, Exception('network down'));
      await doctor.captureException(StateError('test'));

      // Reset mock to succeed for flush.
      reset(mockClient);
      stubPut(mockClient);

      // flushQueue should work because consentPreVerified is true.
      final result = await doctor.flushQueue();
      expect(result.sent, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // captureMessage when disabled or no consent
  // ---------------------------------------------------------------------------

  group('captureMessage guards', () {
    test('captureMessage does nothing when disabled', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        enabled: false,
        apiUrl: '',
        vaultId: '',
        apiKey: '',
      );
      await doctor.captureMessage('test');

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('captureMessage does nothing without consent', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);

      // No grantConsent called.
      await doctor.captureMessage('test');

      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // captureException with explicit stackTrace
  // ---------------------------------------------------------------------------

  group('captureException with explicit stackTrace', () {
    test('captureException includes provided stackTrace', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(httpClient: mockClient);
      await doctor.grantConsent();

      final customTrace = StackTrace.fromString('#0 main (test.dart:1:1)');
      await doctor.captureException(
        StateError('boom'),
        stackTrace: customTrace,
      );

      final content = capturePutContent(mockClient);
      expect(content, contains('#0 main (test.dart:1:1)'));
    });
  });

  // ---------------------------------------------------------------------------
  // beforeSend throwing
  // ---------------------------------------------------------------------------

  group('beforeSend throwing', () {
    test('beforeSend exception propagates to caller', () async {
      stubPut(mockClient);
      final doctor = makeDoctor(
        httpClient: mockClient,
        beforeSend: (report) => throw StateError('beforeSend broke'),
      );
      await doctor.grantConsent();

      expect(
        () => doctor.captureException(StateError('test')),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // revokeConsent clears queue
  // ---------------------------------------------------------------------------

  group('revokeConsent clears queue', () {
    test('revokeConsent clears the offline queue', () async {
      final storage = MemoryStorage();
      final doctor = makeDoctor(
        httpClient: mockClient,
        storage: storage,
      );
      await doctor.grantConsent();

      // Force a failed upload to enqueue a report.
      stubPutThrows(mockClient, Exception('offline'));
      await doctor.captureException(StateError('queued'));

      // Verify something is in the queue.
      final queueBefore = await storage.getItem('doctor:queue');
      expect(queueBefore, isNotNull);
      expect(queueBefore, isNot(equals('[]')));

      // Revoke consent.
      await doctor.revokeConsent();

      // Queue should be cleared (saved as empty list).
      final queueAfter = await storage.getItem('doctor:queue');
      expect(queueAfter, equals('[]'));
    });
  });
}
