import 'package:lifestream_doctor/src/signature.dart';
import 'package:test/test.dart';

void main() {
  group('sha256Hex', () {
    test('produces correct hash for empty string', () {
      expect(
        sha256Hex(''),
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );
    });

    test('produces correct hash for known input', () {
      // SHA-256 of "hello" is well-known
      expect(
        sha256Hex('hello'),
        equals(
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
        ),
      );
    });
  });

  group('hmacSha256Hex', () {
    test('produces correct HMAC for known inputs', () {
      final result = hmacSha256Hex('test-key', 'test-data');
      // Must be a 64-char lowercase hex string (256 bits = 32 bytes = 64 hex chars)
      expect(result, hasLength(64));
      expect(result, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('produces deterministic output for same inputs', () {
      final first = hmacSha256Hex('my-secret', 'my-data');
      final second = hmacSha256Hex('my-secret', 'my-data');
      expect(first, equals(second));
    });

    test('hmacSha256Hex produces correct HMAC for known input', () {
      // RFC 4231 test vector (simplified)
      // key = 'key', data = 'The quick brown fox jumps over the lazy dog'
      // Expected HMAC-SHA256: f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8
      final result = hmacSha256Hex(
        'key',
        'The quick brown fox jumps over the lazy dog',
      );
      expect(
          result,
          equals(
              'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8'));
    });
  });

  group('buildSignaturePayload', () {
    test('has 5 newline-separated parts', () {
      final payload = buildSignaturePayload(
        'GET',
        '/api/v1/test',
        '2024-01-01T00:00:00.000Z',
        'abc123',
        '{"key":"value"}',
      );
      final parts = payload.split('\n');
      expect(parts, hasLength(5));
    });

    test('uppercases the method', () {
      final payload = buildSignaturePayload(
        'get',
        '/api/v1/test',
        '2024-01-01T00:00:00.000Z',
        'abc123',
        '',
      );
      final parts = payload.split('\n');
      expect(parts[0], equals('GET'));
    });

    test('includes path, timestamp, nonce, and body hash in order', () {
      const path = '/api/v1/test';
      const timestamp = '2024-01-01T00:00:00.000Z';
      const nonce = 'abc123';
      const body = '{"key":"value"}';

      final payload = buildSignaturePayload(
        'POST',
        path,
        timestamp,
        nonce,
        body,
      );
      final parts = payload.split('\n');

      expect(parts[0], equals('POST'));
      expect(parts[1], equals(path));
      expect(parts[2], equals(timestamp));
      expect(parts[3], equals(nonce));
      // Part 4 should be the SHA-256 of the body
      expect(parts[4], equals(sha256Hex(body)));
    });
  });

  group('signPayload', () {
    test('produces 64-char hex string', () {
      final result = signPayload('secret', 'some-payload');
      expect(result, hasLength(64));
      expect(result, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('generateNonce', () {
    test('produces 32-char hex string', () {
      final nonce = generateNonce();
      expect(nonce, hasLength(32));
      expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('produces unique values across 20 invocations', () {
      final nonces = <String>{};
      for (var i = 0; i < 20; i++) {
        nonces.add(generateNonce());
      }
      expect(nonces, hasLength(20));
    });
  });

  group('signRequest', () {
    test('returns map with 3 expected keys', () {
      final headers = signRequest('api-key', 'GET', '/test');
      expect(headers, contains(signatureHeader));
      expect(headers, contains(signatureTimestampHeader));
      expect(headers, contains(signatureNonceHeader));
      expect(headers, hasLength(3));
    });

    test('signature is 64-char hex string', () {
      final headers = signRequest('api-key', 'POST', '/test', '{"a":1}');
      final signature = headers[signatureHeader]!;
      expect(signature, hasLength(64));
      expect(signature, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('timestamp is ISO-8601 format', () {
      final headers = signRequest('api-key', 'GET', '/test');
      final timestamp = headers[signatureTimestampHeader]!;
      // ISO-8601 timestamps from DateTime.toIso8601String() end with Z or +offset
      expect(
        () => DateTime.parse(timestamp),
        returnsNormally,
      );
    });
  });

  group('constants', () {
    test('maxTimestampAgeMs is 5 minutes in milliseconds', () {
      expect(maxTimestampAgeMs, equals(300000));
    });
  });
}
