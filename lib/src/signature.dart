import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Header name for the HMAC signature.
const signatureHeader = 'x-signature';

/// Header name for the signature timestamp.
const signatureTimestampHeader = 'x-signature-timestamp';

/// Header name for the signature nonce.
const signatureNonceHeader = 'x-signature-nonce';

/// Maximum age for a signed request timestamp (5 minutes).
const maxTimestampAgeMs = 5 * 60 * 1000;

/// Computes SHA-256 hash of [data] as lowercase hex string.
String sha256Hex(String data) => sha256.convert(utf8.encode(data)).toString();

/// Computes HMAC-SHA256 of [data] using [key] as lowercase hex string.
String hmacSha256Hex(String key, String data) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(data)).toString();

/// Constructs the canonical payload string for HMAC signing.
///
/// Format: METHOD\nPATH\nTIMESTAMP\nNONCE\nBODY_HASH
String buildSignaturePayload(
  String method,
  String path,
  String timestamp,
  String nonce,
  String body,
) {
  final bodyHash = sha256Hex(body);
  return '${method.toUpperCase()}\n$path\n$timestamp\n$nonce\n$bodyHash';
}

/// Generates an HMAC-SHA256 signature for a payload.
String signPayload(String secret, String payload) =>
    hmacSha256Hex(secret, payload);

/// Generates a cryptographically secure 16-byte hex nonce.
String generateNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Signs a request and returns the headers to attach.
///
/// Returns a map with [signatureHeader], [signatureTimestampHeader],
/// and [signatureNonceHeader].
Map<String, String> signRequest(
  String apiKey,
  String method,
  String path, [
  String body = '',
]) {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final nonce = generateNonce();
  final payload = buildSignaturePayload(method, path, timestamp, nonce, body);
  final signature = signPayload(apiKey, payload);

  return {
    signatureHeader: signature,
    signatureTimestampHeader: timestamp,
    signatureNonceHeader: nonce,
  };
}
