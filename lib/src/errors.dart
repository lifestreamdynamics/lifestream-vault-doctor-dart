/// Base exception for all Doctor SDK errors.
class DoctorException implements Exception {
  /// Creates a [DoctorException] with the given [message].
  DoctorException(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'DoctorException: $message';
}

/// Thrown when a crash report upload fails.
class UploadException extends DoctorException {
  /// Creates an [UploadException] with the given [message] and optional
  /// [statusCode].
  UploadException(super.message, {this.statusCode});

  /// HTTP status code, if available.
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode != null ? ' (HTTP $statusCode)' : '';
    return 'UploadException: $message$status';
  }
}

/// Thrown when an operation requires consent that has not been granted.
class ConsentException extends DoctorException {
  /// Creates a [ConsentException] with an optional [message].
  ConsentException([
    super.message = 'Crash reporting consent has not been granted',
  ]);

  @override
  String toString() => 'ConsentException: $message';
}
