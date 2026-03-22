/// Crash reporting SDK for Lifestream Vault.
///
/// Captures exceptions and uploads reports as searchable Markdown documents
/// to a Lifestream Vault instance.
library lifestream_doctor;

// Types
export 'src/types.dart';
export 'src/errors.dart';
export 'src/storage_backend.dart';

// Data structures
export 'src/session.dart';
export 'src/breadcrumb_buffer.dart';
export 'src/rate_limiter.dart';

// Formatting
export 'src/formatter.dart';

// Network
export 'src/signature.dart'
    show
        signRequest,
        buildSignaturePayload,
        signPayload,
        generateNonce,
        signatureHeader,
        signatureTimestampHeader,
        signatureNonceHeader,
        maxTimestampAgeMs;
export 'src/uploader.dart';

// Queue
export 'src/crash_queue.dart';
export 'src/memory_storage.dart';

// Main SDK
export 'src/lifestream_doctor.dart';

// Adapters
export 'src/adapters/dart_io_device_context.dart';
