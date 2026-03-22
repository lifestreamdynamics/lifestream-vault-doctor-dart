import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'breadcrumb_buffer.dart';
import 'crash_queue.dart';
import 'formatter.dart';
import 'memory_storage.dart';
import 'rate_limiter.dart';
import 'session.dart';
import 'storage_backend.dart';
import 'types.dart';
import 'uploader.dart';

/// Storage key used for persisting consent state.
const consentKey = 'doctor:consent';

/// Main entry point for the Lifestream Doctor crash reporting SDK.
///
/// Captures exceptions, enriches them with breadcrumbs, device context, and
/// session information, then uploads formatted Markdown reports to a
/// Lifestream Vault instance. Reports that fail to upload are queued offline
/// and retried on the next [flushQueue] call.
///
/// Usage requires calling [grantConsent] (or [setConsentPreVerified]) before
/// any reports will be sent. This ensures GDPR/privacy compliance.
class LifestreamDoctor {
  /// Creates a new [LifestreamDoctor] instance.
  ///
  /// When [enabled] is `true` (the default), [apiUrl], [vaultId], and [apiKey]
  /// must be non-empty strings or an [ArgumentError] is thrown.
  ///
  /// When [enabled] is `false`, the SDK silently no-ops on all capture calls
  /// and credential validation is skipped.
  LifestreamDoctor({
    required String apiUrl,
    required String vaultId,
    required String apiKey,
    String environment = 'production',
    bool enabled = true,
    int maxBreadcrumbs = 50,
    int rateLimitWindowMs = 60000,
    String pathPrefix = 'crash-reports',
    List<String>? tags,
    CrashReport? Function(CrashReport)? beforeSend,
    StorageBackend? storage,
    bool enableRequestSigning = true,
    CustomSignRequest? signRequest,
    bool debug = false,
    http.Client? httpClient,
  }) : this._internal(
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
          resolvedStorage: storage ?? MemoryStorage(),
          enableRequestSigning: enableRequestSigning,
          signRequest: signRequest,
          debug: debug,
          httpClient: httpClient,
        );

  LifestreamDoctor._internal({
    required String apiUrl,
    required String vaultId,
    required String apiKey,
    required String environment,
    required bool enabled,
    required int maxBreadcrumbs,
    required int rateLimitWindowMs,
    required String pathPrefix,
    required List<String>? tags,
    required CrashReport? Function(CrashReport)? beforeSend,
    required StorageBackend resolvedStorage,
    required bool enableRequestSigning,
    required CustomSignRequest? signRequest,
    required bool debug,
    required http.Client? httpClient,
  })  : _apiUrl = apiUrl,
        _vaultId = vaultId,
        _apiKey = apiKey,
        _environment = environment,
        _enabled = enabled,
        _pathPrefix = pathPrefix,
        _tags = tags ?? const [],
        _beforeSend = beforeSend,
        _enableRequestSigning = enableRequestSigning,
        _signRequest = signRequest,
        _debug = debug,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _session = Session(),
        _breadcrumbs = BreadcrumbBuffer(capacity: maxBreadcrumbs),
        _rateLimiter = RateLimiter(windowMs: rateLimitWindowMs),
        _storage = resolvedStorage,
        _queue = CrashQueue(resolvedStorage) {
    if (enabled) {
      if (apiUrl.isEmpty) {
        throw ArgumentError('LifestreamDoctor: apiUrl is required');
      }
      if (vaultId.isEmpty) {
        throw ArgumentError('LifestreamDoctor: vaultId is required');
      }
      if (apiKey.isEmpty) {
        throw ArgumentError('LifestreamDoctor: apiKey is required');
      }
    }
  }

  static const _uuid = Uuid();

  final String _apiUrl;
  final String _vaultId;
  final String _apiKey;
  final String _environment;
  final bool _enabled;
  final String _pathPrefix;
  final List<String> _tags;
  final CrashReport? Function(CrashReport)? _beforeSend;
  final bool _enableRequestSigning;
  final CustomSignRequest? _signRequest;
  final bool _debug;
  final http.Client _httpClient;
  final Session _session;
  final BreadcrumbBuffer _breadcrumbs;
  final RateLimiter _rateLimiter;
  final StorageBackend _storage;
  final CrashQueue _queue;

  final bool _ownsHttpClient;

  DeviceContextProvider? _deviceContextProvider;
  bool _consentPreVerified = false;

  // ---------------------------------------------------------------------------
  // Consent management
  // ---------------------------------------------------------------------------

  /// Grants consent for crash reporting by persisting a flag to storage.
  Future<void> grantConsent() async {
    await _storage.setItem(consentKey, 'true');
  }

  /// Revokes consent, clears the offline queue, and resets the pre-verified
  /// flag. No further reports will be sent until consent is re-granted.
  Future<void> revokeConsent() async {
    _consentPreVerified = false;
    await _storage.removeItem(consentKey);
    await _queue.clear();
  }

  /// Marks consent as pre-verified for the current session without persisting
  /// to storage. This is useful when consent has already been verified by the
  /// host application (e.g., from an onboarding flow).
  void setConsentPreVerified() {
    _consentPreVerified = true;
  }

  /// Returns `true` if consent has been granted via [grantConsent].
  Future<bool> isConsentGranted() async {
    final value = await _storage.getItem(consentKey);
    return value == 'true';
  }

  // ---------------------------------------------------------------------------
  // Breadcrumbs
  // ---------------------------------------------------------------------------

  /// Adds a breadcrumb to the internal buffer.
  ///
  /// Breadcrumbs are included in crash reports to provide context about user
  /// actions and events leading up to an error. If the SDK is disabled, this
  /// is a no-op.
  void addBreadcrumb(Breadcrumb crumb) {
    if (!_enabled) return;
    _breadcrumbs.add(crumb);
  }

  // ---------------------------------------------------------------------------
  // Device context
  // ---------------------------------------------------------------------------

  /// Sets a provider function that will be called to collect device context
  /// each time a crash report is captured.
  void setDeviceContextProvider(DeviceContextProvider fn) {
    _deviceContextProvider = fn;
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// Captures an exception and uploads it as a crash report.
  ///
  /// The [error] can be any Dart object. The [stackTrace] is optional and
  /// defaults to [StackTrace.current] if not provided. Additional metadata
  /// can be attached via [severity], [extra], [componentStack], and [tags].
  ///
  /// Reports are silently dropped when:
  /// - The SDK is disabled
  /// - Consent has not been granted (and not pre-verified)
  /// - The same error is rate-limited within the configured window
  /// - The [beforeSend] callback returns `null`
  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    Severity severity = Severity.error,
    Map<String, Object?>? extra,
    String? componentStack,
    List<String>? tags,
  }) async {
    final errorName = error.runtimeType.toString();
    final errorMessage = error.toString();
    final traceString = stackTrace?.toString() ?? StackTrace.current.toString();

    await _capture(
      errorName: errorName,
      errorMessage: errorMessage,
      stackTrace: traceString,
      severity: severity,
      extra: extra,
      componentStack: componentStack,
      tags: tags,
    );
  }

  /// Captures a plain message as a crash report.
  ///
  /// Internally creates a report with `errorName` set to `'CapturedMessage'`.
  /// Defaults to [Severity.info] severity.
  Future<void> captureMessage(
    String message, {
    Severity severity = Severity.info,
    Map<String, Object?>? extra,
  }) async {
    await _capture(
      errorName: 'CapturedMessage',
      errorMessage: message,
      stackTrace: StackTrace.current.toString(),
      severity: severity,
      extra: extra,
    );
  }

  /// Internal capture implementation shared by [captureException] and
  /// [captureMessage].
  Future<void> _capture({
    required String errorName,
    required String errorMessage,
    required String stackTrace,
    required Severity severity,
    Map<String, Object?>? extra,
    String? componentStack,
    List<String>? tags,
  }) async {
    if (!_enabled) return;
    if (!_consentPreVerified && !(await isConsentGranted())) return;

    final fingerprint = RateLimiter.fingerprint(errorName, errorMessage);
    if (!_rateLimiter.shouldAllow(fingerprint)) return;

    var device = const DeviceContext();
    if (_deviceContextProvider != null) {
      try {
        device = await _deviceContextProvider!();
      } catch (_) {
        // Swallow device context errors — they must not prevent reporting.
      }
    }

    final autoTags = [
      'severity:${severity.name}',
      'env:$_environment',
      errorName.toLowerCase(),
    ];
    final globalTags = _tags;
    final localTags = tags ?? const [];
    final allTags = {...autoTags, ...globalTags, ...localTags}.toList();

    var report = CrashReport(
      id: _uuid.v4(),
      timestamp: DateTime.now().toUtc().toIso8601String(),
      errorName: errorName,
      errorMessage: errorMessage,
      stackTrace: stackTrace,
      componentStack: componentStack,
      severity: severity,
      sessionId: _session.id,
      sessionDurationMs: _session.getDurationMs(),
      environment: _environment,
      device: device,
      breadcrumbs: _breadcrumbs.getAll(),
      extra: extra,
      tags: allTags,
    );

    if (_beforeSend != null) {
      final filtered = _beforeSend(report);
      if (filtered == null) return;
      report = filtered;
    }

    final content = formatReport(report);
    final path = generateDocPath(report, prefix: _pathPrefix);

    try {
      await uploadReport(
        apiUrl: _apiUrl,
        vaultId: _vaultId,
        apiKey: _apiKey,
        content: content,
        path: path,
        enableRequestSigning: _enableRequestSigning,
        customSignRequest: _signRequest,
        httpClient: _httpClient,
      );
    } catch (uploadErr) {
      if (_debug) {
        developer.log(
          '[Doctor] Upload failed, enqueuing for retry: $uploadErr',
          name: 'lifestream_doctor',
        );
      }
      await _queue.enqueue(content, path);
    }
  }

  // ---------------------------------------------------------------------------
  // Queue
  // ---------------------------------------------------------------------------

  /// Flushes the offline queue, uploading all pending reports.
  ///
  /// Returns a [FlushResult] with counts of sent, failed, and dead-lettered
  /// reports. If consent has not been granted, returns a zero-count result
  /// without attempting any uploads.
  Future<FlushResult> flushQueue() async {
    if (!_consentPreVerified && !(await isConsentGranted())) {
      return const FlushResult(sent: 0, failed: 0, deadLettered: 0);
    }

    final result = await _queue.flush((report) async {
      await uploadReport(
        apiUrl: _apiUrl,
        vaultId: _vaultId,
        apiKey: _apiKey,
        content: report.content,
        path: report.path,
        enableRequestSigning: _enableRequestSigning,
        customSignRequest: _signRequest,
        httpClient: _httpClient,
      );
    });

    if (_debug &&
        (result.sent > 0 || result.failed > 0 || result.deadLettered > 0)) {
      developer.log(
        '[Doctor] Queue flush: ${result.sent} sent, '
        '${result.failed} failed, ${result.deadLettered} dead-lettered',
        name: 'lifestream_doctor',
      );
    }

    return result;
  }

  /// Closes the internal HTTP client if it was created by this instance.
  ///
  /// Call this when the SDK is no longer needed to release connection pool
  /// resources. If a custom [httpClient] was provided in the constructor,
  /// this method is a no-op (the caller owns that client's lifecycle).
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}
