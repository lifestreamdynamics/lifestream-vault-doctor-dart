import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifestream_doctor/src/errors.dart';
import 'package:lifestream_doctor/src/signature.dart';
import 'package:lifestream_doctor/src/uploader.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;

  const apiUrl = 'https://vault.example.com';
  const vaultId = 'vault-123';
  const apiKey = 'test-api-key';
  const content = '# Crash Report\nSome content';
  const path = 'crashes/2024/01/report.md';

  final expectedUrl = '$apiUrl/api/v1/vaults/$vaultId/documents/$path';

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  setUp(() {
    mockClient = MockHttpClient();
  });

  /// Helper to stub a successful PUT response.
  void stubPut({int statusCode = 200, String body = ''}) {
    when(
      () => mockClient.put(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => http.Response(body, statusCode));
  }

  group('uploadReport', () {
    test('successful upload completes without error', () async {
      stubPut();

      await expectLater(
        uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        ),
        completes,
      );
    });

    test('constructs correct URL', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
      );

      final captured = verify(
        () => mockClient.put(
          captureAny(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final uri = captured.first as Uri;
      expect(uri.toString(), equals(expectedUrl));
    });

    test('request method is PUT', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
      );

      verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('Authorization header is Bearer {apiKey}', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
        enableRequestSigning: false,
      );

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final headers = captured.first as Map<String, String>;
      expect(headers['Authorization'], equals('Bearer $apiKey'));
    });

    test('Content-Type is application/json', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
        enableRequestSigning: false,
      );

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final headers = captured.first as Map<String, String>;
      expect(headers['Content-Type'], equals('application/json'));
    });

    test('body contains content and createIntermediateFolders', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
      );

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;

      final body = jsonDecode(captured.first as String) as Map<String, Object?>;
      expect(body['content'], equals(content));
      expect(body['createIntermediateFolders'], isTrue);
    });

    test('signature headers present when signing enabled', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
        enableRequestSigning: true,
      );

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final headers = captured.first as Map<String, String>;
      expect(headers, contains(signatureHeader));
      expect(headers, contains(signatureTimestampHeader));
      expect(headers, contains(signatureNonceHeader));
    });

    test('no signature headers when signing disabled', () async {
      stubPut();

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
        enableRequestSigning: false,
      );

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final headers = captured.first as Map<String, String>;
      expect(headers, isNot(contains(signatureHeader)));
      expect(headers, isNot(contains(signatureTimestampHeader)));
      expect(headers, isNot(contains(signatureNonceHeader)));
    });

    test('custom sign request function used when provided', () async {
      stubPut();

      var customCalled = false;
      Future<Map<String, String>> customSign(
        String key,
        String method,
        String path,
        String body,
      ) async {
        customCalled = true;
        return {'x-custom-sig': 'custom-value'};
      }

      await uploadReport(
        apiUrl: apiUrl,
        vaultId: vaultId,
        apiKey: apiKey,
        content: content,
        path: path,
        httpClient: mockClient,
        enableRequestSigning: true,
        customSignRequest: customSign,
      );

      expect(customCalled, isTrue);

      final captured = verify(
        () => mockClient.put(
          any(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;

      final headers = captured.first as Map<String, String>;
      expect(headers['x-custom-sig'], equals('custom-value'));
    });

    test('404 response throws UploadException with statusCode', () async {
      stubPut(statusCode: 404, body: 'Not Found');

      expect(
        () => uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        ),
        throwsA(
          isA<UploadException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('404')),
        ),
      );
    });

    test('500 response throws UploadException with statusCode', () async {
      stubPut(statusCode: 500, body: 'Internal Server Error');

      expect(
        () => uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        ),
        throwsA(
          isA<UploadException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('500')),
        ),
      );
    });

    test('network error throws UploadException', () async {
      when(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('Connection refused'));

      expect(
        () => uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        ),
        throwsA(
          isA<UploadException>()
              .having((e) => e.message, 'message', contains('Network error')),
        ),
      );
    });

    test('timeout throws UploadException with timeout message', () async {
      when(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(
          const Duration(seconds: 30),
          () => http.Response('', 200),
        ),
      );

      expect(
        () => uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        ),
        throwsA(
          isA<UploadException>()
              .having((e) => e.message, 'message', contains('timed out')),
        ),
      );
    });

    test('UploadException has correct statusCode property', () async {
      stubPut(statusCode: 403, body: 'Forbidden');

      try {
        await uploadReport(
          apiUrl: apiUrl,
          vaultId: vaultId,
          apiKey: apiKey,
          content: content,
          path: path,
          httpClient: mockClient,
        );
        fail('Expected UploadException');
      } on UploadException catch (e) {
        expect(e.statusCode, equals(403));
        expect(e.message, contains('403'));
        expect(e.toString(), contains('HTTP 403'));
      }
    });
  });
}
