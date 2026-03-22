import 'package:lifestream_doctor/src/formatter.dart';
import 'package:lifestream_doctor/src/types.dart';
import 'package:test/test.dart';

/// Creates a [CrashReport] with sensible defaults.
///
/// Override any field by passing the corresponding parameter.
CrashReport makeReport({
  String id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  String timestamp = '2025-06-15T10:30:00.000Z',
  String errorName = 'TypeError',
  String errorMessage = 'null is not an object',
  String? stackTrace = 'Error: null is not an object\n    at main.dart:42',
  String? componentStack,
  Severity severity = Severity.error,
  String sessionId = 'sess-001',
  int sessionDurationMs = 12345,
  String environment = 'production',
  DeviceContext device = const DeviceContext(
    platform: 'ios',
    osVersion: '17.4',
    appVersion: '2.1.0',
  ),
  List<Breadcrumb> breadcrumbs = const [
    Breadcrumb(
      timestamp: '2025-06-15T10:29:50.000Z',
      type: 'navigation',
      message: 'Opened HomeScreen',
    ),
  ],
  Map<String, Object?>? extra,
  List<String> tags = const ['crash', 'ios'],
}) {
  return CrashReport(
    id: id,
    timestamp: timestamp,
    errorName: errorName,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    componentStack: componentStack,
    severity: severity,
    sessionId: sessionId,
    sessionDurationMs: sessionDurationMs,
    environment: environment,
    device: device,
    breadcrumbs: breadcrumbs,
    extra: extra,
    tags: tags,
  );
}

void main() {
  group('formatReport', () {
    group('YAML frontmatter', () {
      test('starts and ends with --- delimiters', () {
        final output = formatReport(makeReport());
        final lines = output.split('\n');
        expect(lines.first, equals('---'));
        // Find the second '---'
        final secondDelimiter = lines.indexOf('---', 1);
        expect(secondDelimiter, greaterThan(0));
        expect(lines[secondDelimiter], equals('---'));
      });

      test('title includes severity uppercased and error info', () {
        final output = formatReport(makeReport(
          severity: Severity.fatal,
          errorName: 'StateError',
          errorMessage: 'Bad state',
        ));
        expect(output, contains('[FATAL] StateError: Bad state'));
      });

      test('tags rendered as YAML array', () {
        final output = formatReport(makeReport(tags: ['crash', 'ios']));
        expect(output, contains('tags:\n  - crash\n  - ios'));
      });

      test('empty tags rendered as tags: []', () {
        final output = formatReport(makeReport(tags: []));
        expect(output, contains('tags: []'));
      });

      test('date field present', () {
        final output =
            formatReport(makeReport(timestamp: '2025-06-15T10:30:00.000Z'));
        expect(output, contains('date: 2025-06-15T10:30:00.000Z'));
      });

      test('severity field present', () {
        final output = formatReport(makeReport(severity: Severity.warning));
        expect(output, contains('severity: warning'));
      });

      test('device field present', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(platform: 'android'),
        ));
        expect(output, contains('device: android'));
      });

      test('os field present', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(osVersion: '14.0'),
        ));
        expect(output, contains('os: "14.0"'));
      });

      test('appVersion field present', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(appVersion: '3.0.0'),
        ));
        expect(output, contains('appVersion: 3.0.0'));
      });

      test('sessionId field present', () {
        final output = formatReport(makeReport(sessionId: 'sess-xyz'));
        expect(output, contains('sessionId: sess-xyz'));
      });

      test('environment field present', () {
        final output = formatReport(makeReport(environment: 'staging'));
        expect(output, contains('environment: staging'));
      });

      test('device defaults to unknown when platform is null', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(),
        ));
        expect(output, contains('device: unknown'));
      });

      test('os defaults to unknown when osVersion is null', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(),
        ));
        expect(output, contains('os: unknown'));
      });

      test('appVersion defaults to unknown when null', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(),
        ));
        expect(output, contains('appVersion: unknown'));
      });
    });

    group('Stack Trace section', () {
      test('rendered in code fence', () {
        final output = formatReport(makeReport(
          stackTrace: 'Error at line 1\n  at line 2',
        ));
        expect(output, contains('## Stack Trace'));
        expect(output, contains('```\nError at line 1\n  at line 2\n```'));
      });

      test('truncated at 4000 chars with [truncated]', () {
        final longTrace = 'x' * 5000;
        final output = formatReport(makeReport(stackTrace: longTrace));
        expect(output, contains('x' * 4000));
        expect(output, contains('[truncated]'));
        // Should NOT contain the full 5000-char string
        expect(output, isNot(contains('x' * 4001)));
      });

      test('stack trace exactly 4000 chars is not truncated', () {
        final exactTrace = 'a' * 4000;
        final output = formatReport(makeReport(stackTrace: exactTrace));
        expect(output, contains(exactTrace));
        expect(output, isNot(contains('[truncated]')));
      });

      test('no stack trace: empty code fence', () {
        final output = formatReport(makeReport(stackTrace: null));
        expect(output, contains('## Stack Trace\n\n```\n```'));
      });
    });

    group('Component Stack section', () {
      test('rendered when present', () {
        final output = formatReport(makeReport(
          componentStack: 'Widget: MyApp\n  Widget: Scaffold',
        ));
        expect(output, contains('## Component Stack'));
        expect(output, contains('```\nWidget: MyApp\n  Widget: Scaffold\n```'));
      });

      test('omitted when null', () {
        final output = formatReport(makeReport(componentStack: null));
        expect(output, isNot(contains('## Component Stack')));
      });
    });

    group('Breadcrumbs section', () {
      test('table rendered with headers', () {
        final output = formatReport(makeReport());
        expect(output, contains('## Breadcrumbs'));
        expect(output, contains('| Time | Type | Message |'));
        expect(output, contains('|------|------|---------|'));
      });

      test('empty breadcrumbs show placeholder row with em dashes', () {
        final output = formatReport(makeReport(breadcrumbs: []));
        expect(output, contains('| \u2014 | \u2014 | \u2014 |'));
      });

      test('breadcrumb data rendered in table', () {
        final output = formatReport(makeReport(
          breadcrumbs: [
            const Breadcrumb(
              timestamp: '2025-06-15T10:29:50.000Z',
              type: 'http',
              message: 'GET /api/data',
            ),
          ],
        ));
        expect(output,
            contains('| 2025-06-15T10:29:50.000Z | http | GET /api/data |'));
      });

      test('pipe characters escaped in breadcrumbs', () {
        final output = formatReport(makeReport(
          breadcrumbs: [
            const Breadcrumb(
              timestamp: '2025|time',
              type: 'type|val',
              message: 'msg|here',
            ),
          ],
        ));
        expect(output, contains(r'2025\|time'));
        expect(output, contains(r'type\|val'));
        expect(output, contains(r'msg\|here'));
      });
    });

    group('Device Context section', () {
      test('entries rendered as bullet list', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(
            platform: 'ios',
            osVersion: '17.4',
            appVersion: '2.1.0',
          ),
        ));
        expect(output, contains('## Device Context'));
        expect(output, contains('- **platform**: ios'));
        expect(output, contains('- **osVersion**: 17.4'));
        expect(output, contains('- **appVersion**: 2.1.0'));
      });

      test('empty device context shows no context message', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(),
        ));
        expect(output, contains('_No device context available._'));
      });

      test('extras included in device context', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(
            platform: 'android',
            extras: {'screenDensity': 2.0, 'ram': '4GB'},
          ),
        ));
        expect(output, contains('- **platform**: android'));
        expect(output, contains('- **screenDensity**: 2.0'));
        expect(output, contains('- **ram**: 4GB'));
      });

      test('only extras when named fields are null', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(extras: {'custom': 'value'}),
        ));
        // Named fields are null so only extras appear
        expect(output, isNot(contains('- **platform**')));
        expect(output, contains('- **custom**: value'));
        expect(output, isNot(contains('_No device context available._')));
      });
    });

    group('Additional Context section', () {
      test('rendered as JSON code fence', () {
        final output = formatReport(makeReport(
          extra: {'userId': 'u123', 'action': 'checkout'},
        ));
        expect(output, contains('## Additional Context'));
        expect(output, contains('```json'));
        expect(output, contains('"userId": "u123"'));
        expect(output, contains('"action": "checkout"'));
      });

      test('omitted when extra is null', () {
        final output = formatReport(makeReport(extra: null));
        expect(output, isNot(contains('## Additional Context')));
      });

      test('extra context >50KB shows error message', () {
        // Create a map whose JSON serialization exceeds 50000 chars
        final largeExtra = <String, Object?>{
          'data': 'x' * 60000,
        };
        final output = formatReport(makeReport(extra: largeExtra));
        expect(output, contains('{"_error":"Extra context too large"}'));
      });
    });

    group('YAML special scalar quoting', () {
      test('YAML boolean-like values are quoted', () {
        final output = formatReport(makeReport(environment: 'true'));
        expect(output, contains('environment: "true"'));
      });

      test('YAML null-like value is quoted', () {
        final output = formatReport(makeReport(environment: 'null'));
        expect(output, contains('environment: "null"'));
      });

      test('numeric string values are quoted', () {
        final output = formatReport(makeReport(
          device: const DeviceContext(osVersion: '17'),
        ));
        expect(output, contains('os: "17"'));
      });

      test('yes/no YAML 1.1 booleans are quoted', () {
        final output = formatReport(makeReport(environment: 'yes'));
        expect(output, contains('environment: "yes"'));
      });

      test('tags that are YAML-special scalars are quoted', () {
        final output = formatReport(makeReport(tags: ['true', 'false', '42']));
        expect(output, contains('  - "true"'));
        expect(output, contains('  - "false"'));
        expect(output, contains('  - "42"'));
      });
    });

    group('_yamlValue edge cases', () {
      test('value with leading spaces is quoted', () {
        final output = formatReport(makeReport(environment: ' leading'));
        expect(output, contains('environment: " leading"'));
      });

      test('value with trailing spaces is quoted', () {
        final output = formatReport(makeReport(environment: 'trailing '));
        expect(output, contains('environment: "trailing "'));
      });

      test('value with single quote is quoted', () {
        final output = formatReport(makeReport(environment: "it's"));
        expect(output, contains("environment: \"it's\""));
      });

      test('value with newline is quoted and escaped', () {
        final output = formatReport(makeReport(environment: 'line1\nline2'));
        expect(output, contains(r'environment: "line1\nline2"'));
      });
    });

    group('Extra context serialization', () {
      test('extra context with non-serializable value shows error', () {
        // An object that jsonEncode cannot serialize
        final output = formatReport(makeReport(extra: {'bad': DateTime.now()}));
        expect(
            output, contains('{"_error":"Failed to serialize extra context"}'));
      });
    });

    group('YAML escaping', () {
      test('colon-space is quoted', () {
        final output = formatReport(makeReport(
          errorMessage: 'key: value',
        ));
        // The title YAML value should be quoted
        expect(output, contains('"'));
      });

      test('hash character is quoted', () {
        final output = formatReport(makeReport(
          errorMessage: 'error #42',
        ));
        final lines = output.split('\n');
        final titleLine = lines.firstWhere((l) => l.startsWith('title:'));
        expect(titleLine, contains('"'));
      });

      test('brackets are quoted', () {
        final output = formatReport(makeReport(
          errorMessage: 'value [0]',
        ));
        final lines = output.split('\n');
        final titleLine = lines.firstWhere((l) => l.startsWith('title:'));
        expect(titleLine, contains('"'));
      });

      test('braces are quoted', () {
        final output = formatReport(makeReport(
          errorMessage: 'Map {}',
        ));
        final lines = output.split('\n');
        final titleLine = lines.firstWhere((l) => l.startsWith('title:'));
        expect(titleLine, contains('"'));
      });

      test('control characters stripped by sanitize', () {
        final output = formatReport(makeReport(
          errorMessage: 'bad\x00char\x07here\x1f',
        ));
        expect(output, isNot(contains('\x00')));
        expect(output, isNot(contains('\x07')));
        expect(output, isNot(contains('\x1f')));
        expect(output, contains('badcharhere'));
      });
    });
  });

  group('generateDocPath', () {
    test('produces correct format: prefix/YYYY-MM-DD/errorname-shortid.md', () {
      final report = makeReport(
        timestamp: '2025-06-15T10:30:00.000Z',
        errorName: 'TypeError',
        id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      );
      final path = generateDocPath(report);
      expect(path, equals('crash-reports/2025-06-15/typeerror-a1b2c3d4.md'));
    });

    test('sanitizes error name (only a-z0-9- allowed)', () {
      final report = makeReport(
        errorName: 'My.Custom_Error!',
      );
      final path = generateDocPath(report);
      // All non-[a-z0-9-] chars become hyphens
      expect(path, contains('my-custom-error-'));
    });

    test('default prefix is crash-reports', () {
      final report = makeReport();
      final path = generateDocPath(report);
      expect(path, startsWith('crash-reports/'));
    });

    test('custom prefix is used', () {
      final report = makeReport();
      final path = generateDocPath(report, prefix: 'errors');
      expect(path, startsWith('errors/'));
    });

    test('generateDocPath with short timestamp still works', () {
      // This tests the substring(0, 10) behavior - if timestamp is valid ISO it works
      final report = makeReport(timestamp: '2026-03-22T14:23:01.482Z');
      final path = generateDocPath(report);
      expect(path, contains('2026-03-22'));
    });

    test('shortId is first 8 characters of ID without hyphens', () {
      final report = makeReport(id: 'abcd1234-5678-9abc-def0-123456789012');
      final path = generateDocPath(report);
      // ID without hyphens: abcd123456789abcdef0123456789012
      // First 8: abcd1234
      expect(path, contains('-abcd1234.md'));
    });
  });
}
