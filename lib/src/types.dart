import 'dart:async';

/// Severity levels for crash reports.
enum Severity {
  fatal,
  error,
  warning,
  info;
}

/// A breadcrumb records a discrete event leading up to a crash.
class Breadcrumb {
  /// Creates a [Breadcrumb].
  const Breadcrumb({
    required this.timestamp,
    required this.type,
    required this.message,
    this.data,
  });

  /// ISO-8601 timestamp (auto-set if omitted when adding via buffer).
  final String timestamp;

  /// Category of breadcrumb (e.g. 'navigation', 'http', 'user', 'console').
  final String type;

  /// Human-readable description.
  final String message;

  /// Optional structured data.
  final Map<String, Object?>? data;
}

/// Device and runtime context collected at crash time.
class DeviceContext {
  /// Creates a [DeviceContext].
  const DeviceContext({
    this.platform,
    this.osVersion,
    this.deviceName,
    this.appVersion,
    this.timezone,
    this.locale,
    this.extras = const {},
  });

  final String? platform;
  final String? osVersion;
  final String? deviceName;
  final String? appVersion;
  final String? timezone;
  final String? locale;

  /// Additional context fields not covered by named properties.
  final Map<String, Object?> extras;

  /// Returns all entries (named fields + extras) for iteration.
  /// Named fields appear first in declaration order, then extras.
  Iterable<MapEntry<String, Object?>> get allEntries sync* {
    yield MapEntry('platform', platform);
    yield MapEntry('osVersion', osVersion);
    yield MapEntry('deviceName', deviceName);
    yield MapEntry('appVersion', appVersion);
    yield MapEntry('timezone', timezone);
    yield MapEntry('locale', locale);
    yield* extras.entries;
  }

  /// Returns true if this context has no values set.
  bool get isEmpty =>
      platform == null &&
      osVersion == null &&
      deviceName == null &&
      appVersion == null &&
      timezone == null &&
      locale == null &&
      extras.isEmpty;
}

/// A fully constructed crash report ready for formatting.
class CrashReport {
  /// Creates a [CrashReport].
  const CrashReport({
    required this.id,
    required this.timestamp,
    required this.errorName,
    required this.errorMessage,
    this.stackTrace,
    this.componentStack,
    required this.severity,
    required this.sessionId,
    required this.sessionDurationMs,
    required this.environment,
    required this.device,
    required this.breadcrumbs,
    this.extra,
    required this.tags,
  });

  /// Unique report ID.
  final String id;

  /// ISO-8601 timestamp.
  final String timestamp;

  /// Error name (e.g. 'TypeError', 'StateError').
  final String errorName;

  /// Error message.
  final String errorMessage;

  /// Stack trace string.
  final String? stackTrace;

  /// Component stack (from Flutter error details or framework boundaries).
  final String? componentStack;

  /// Severity level.
  final Severity severity;

  /// Session ID.
  final String sessionId;

  /// Session duration in ms at time of crash.
  final int sessionDurationMs;

  /// Environment tag (e.g. 'production', 'preview', 'development').
  final String environment;

  /// Device/runtime context.
  final DeviceContext device;

  /// Recent breadcrumbs leading up to the crash.
  final List<Breadcrumb> breadcrumbs;

  /// Arbitrary user-provided context.
  final Map<String, Object?>? extra;

  /// Tags for frontmatter (auto-generated + user-provided).
  final List<String> tags;

  /// Creates a copy with the given fields replaced.
  CrashReport copyWith({
    String? id,
    String? timestamp,
    String? errorName,
    String? errorMessage,
    String? stackTrace,
    String? componentStack,
    Severity? severity,
    String? sessionId,
    int? sessionDurationMs,
    String? environment,
    DeviceContext? device,
    List<Breadcrumb>? breadcrumbs,
    Map<String, Object?>? extra,
    List<String>? tags,
  }) {
    return CrashReport(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      errorName: errorName ?? this.errorName,
      errorMessage: errorMessage ?? this.errorMessage,
      stackTrace: stackTrace ?? this.stackTrace,
      componentStack: componentStack ?? this.componentStack,
      severity: severity ?? this.severity,
      sessionId: sessionId ?? this.sessionId,
      sessionDurationMs: sessionDurationMs ?? this.sessionDurationMs,
      environment: environment ?? this.environment,
      device: device ?? this.device,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      extra: extra ?? this.extra,
      tags: tags ?? this.tags,
    );
  }
}

/// A report queued for later upload (offline).
class QueuedReport {
  /// Creates a [QueuedReport].
  const QueuedReport({
    required this.id,
    required this.content,
    required this.path,
    required this.attempts,
    required this.queuedAt,
    this.lastAttemptAt,
  });

  /// Creates a [QueuedReport] from a JSON map.
  factory QueuedReport.fromJson(Map<String, Object?> json) => QueuedReport(
        id: json['id'] as String,
        content: json['content'] as String,
        path: json['path'] as String,
        attempts: json['attempts'] as int,
        queuedAt: json['queuedAt'] as String,
        lastAttemptAt: json['lastAttemptAt'] as String?,
      );

  /// Queue entry ID.
  final String id;

  /// Formatted Markdown content.
  final String content;

  /// Target document path.
  final String path;

  /// Number of upload attempts so far.
  final int attempts;

  /// ISO-8601 timestamp when first queued.
  final String queuedAt;

  /// ISO-8601 timestamp of last attempt.
  final String? lastAttemptAt;

  /// Creates a JSON-serializable map.
  Map<String, Object?> toJson() => {
        'id': id,
        'content': content,
        'path': path,
        'attempts': attempts,
        'queuedAt': queuedAt,
        if (lastAttemptAt != null) 'lastAttemptAt': lastAttemptAt,
      };

  /// Returns a copy with incremented attempts and updated lastAttemptAt.
  QueuedReport markAttempted(String timestamp) => QueuedReport(
        id: id,
        content: content,
        path: path,
        attempts: attempts + 1,
        queuedAt: queuedAt,
        lastAttemptAt: timestamp,
      );
}

/// Result of flushing the offline queue.
class FlushResult {
  /// Creates a [FlushResult].
  const FlushResult({
    required this.sent,
    required this.failed,
    required this.deadLettered,
  });

  /// Number of reports successfully uploaded.
  final int sent;

  /// Number of reports that failed and remain in queue.
  final int failed;

  /// Number of reports moved to dead letter (exceeded max retries).
  final int deadLettered;
}

/// Provider function for collecting device context.
typedef DeviceContextProvider = FutureOr<DeviceContext> Function();

/// Custom request signing function.
typedef CustomSignRequest = FutureOr<Map<String, String>> Function(
  String apiKey,
  String method,
  String path,
  String body,
);
