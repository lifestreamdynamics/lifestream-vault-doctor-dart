import 'dart:convert';

import 'types.dart';

/// Strips control characters (U+0000–U+0009, U+000B–U+001F, U+007F)
/// from [value], leaving only printable characters and newlines (U+000A).
String _sanitize(String value) {
  return value.replaceAll(
    RegExp(r'[\x00-\x09\x0b-\x1f\x7f]'),
    '',
  );
}

/// Escapes [value] for safe inclusion as a YAML scalar.
///
/// If the value contains characters that require quoting (`:`, `#`, `"`, `'`,
/// newlines, brackets, braces, or leading/trailing spaces), it is returned
/// double-quoted with internal backslashes, double-quotes, and newlines
/// escaped. Otherwise the sanitized value is returned as-is.
String _yamlValue(String value) {
  final clean = _sanitize(value);
  if (clean.contains(': ') ||
      clean.contains('#') ||
      clean.contains('"') ||
      clean.contains("'") ||
      clean.contains('\n') ||
      clean.contains('[') ||
      clean.contains(']') ||
      clean.contains('{') ||
      clean.contains('}') ||
      clean.startsWith(' ') ||
      clean.endsWith(' ') ||
      _isYamlSpecialScalar(clean)) {
    final escaped = clean
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
  return clean;
}

/// Returns true if [value] would be interpreted as a non-string scalar
/// by a YAML parser (boolean, null, or numeric).
bool _isYamlSpecialScalar(String value) {
  final lower = value.toLowerCase();
  // YAML 1.1 and 1.2 boolean/null literals
  if (const {
    'true',
    'false',
    'yes',
    'no',
    'on',
    'off',
    'null',
    '~',
  }.contains(lower)) {
    return true;
  }
  // Numeric: integer or float (including .inf, -.inf, .nan)
  if (lower == '.inf' || lower == '-.inf' || lower == '.nan') return true;
  if (double.tryParse(value) != null) return true;
  return false;
}

/// Builds a list of [MapEntry]s representing device context fields that
/// have non-null values (from named fields) plus all extras, matching the
/// behavior of `Object.entries()` in TypeScript where only defined
/// properties appear.
List<MapEntry<String, Object?>> _deviceEntries(DeviceContext device) {
  final entries = <MapEntry<String, Object?>>[];
  if (device.platform != null) {
    entries.add(MapEntry('platform', device.platform));
  }
  if (device.osVersion != null) {
    entries.add(MapEntry('osVersion', device.osVersion));
  }
  if (device.deviceName != null) {
    entries.add(MapEntry('deviceName', device.deviceName));
  }
  if (device.appVersion != null) {
    entries.add(MapEntry('appVersion', device.appVersion));
  }
  if (device.timezone != null) {
    entries.add(MapEntry('timezone', device.timezone));
  }
  if (device.locale != null) {
    entries.add(MapEntry('locale', device.locale));
  }
  entries.addAll(device.extras.entries);
  return entries;
}

/// Formats a [CrashReport] as a Markdown document with YAML frontmatter.
///
/// The output contains:
/// - YAML frontmatter with title, tags, date, severity, device info, etc.
/// - Stack trace section (truncated at 4000 characters)
/// - Optional component stack section
/// - Breadcrumbs table
/// - Device context list
/// - Optional additional context as JSON
String formatReport(CrashReport report) {
  final lines = <String>[];

  // --- YAML frontmatter ---
  lines.add('---');
  lines.add(
    'title: ${_yamlValue('[${report.severity.name.toUpperCase()}] '
        '${report.errorName}: ${report.errorMessage}')}',
  );

  // Tags as YAML array
  final allTags = [...report.tags];
  if (allTags.isEmpty) {
    lines.add('tags: []');
  } else {
    lines.add('tags:');
    for (final tag in allTags) {
      lines.add('  - ${_yamlValue(tag)}');
    }
  }

  lines.add('date: ${report.timestamp}');
  lines.add('severity: ${report.severity.name}');
  lines.add('device: ${_yamlValue(report.device.platform ?? 'unknown')}');
  lines.add('os: ${_yamlValue(report.device.osVersion ?? 'unknown')}');
  lines.add('appVersion: ${_yamlValue(report.device.appVersion ?? 'unknown')}');
  lines.add('sessionId: ${report.sessionId}');
  lines.add('environment: ${_yamlValue(report.environment)}');
  lines.add('---');
  lines.add('');

  // --- Stack Trace ---
  lines.add('## Stack Trace');
  lines.add('');
  lines.add('```');
  if (report.stackTrace != null) {
    const maxStack = 4000;
    if (report.stackTrace!.length > maxStack) {
      lines.add(report.stackTrace!.substring(0, maxStack));
      lines.add('[truncated]');
    } else {
      lines.add(report.stackTrace!);
    }
  }
  lines.add('```');
  lines.add('');

  // --- Component Stack (optional) ---
  if (report.componentStack != null) {
    lines.add('## Component Stack');
    lines.add('');
    lines.add('```');
    lines.add(report.componentStack!);
    lines.add('```');
    lines.add('');
  }

  // --- Breadcrumbs ---
  lines.add('## Breadcrumbs');
  lines.add('');
  lines.add('| Time | Type | Message |');
  lines.add('|------|------|---------|');
  if (report.breadcrumbs.isEmpty) {
    lines.add('| \u2014 | \u2014 | \u2014 |');
  } else {
    for (final crumb in report.breadcrumbs) {
      final time = crumb.timestamp.replaceAll('|', r'\|');
      final type = crumb.type.replaceAll('|', r'\|');
      final message = crumb.message.replaceAll('|', r'\|');
      lines.add('| $time | $type | $message |');
    }
  }
  lines.add('');

  // --- Device Context ---
  lines.add('## Device Context');
  lines.add('');
  final deviceEntries = _deviceEntries(report.device);
  if (deviceEntries.isEmpty) {
    lines.add('_No device context available._');
  } else {
    for (final entry in deviceEntries) {
      final displayValue = entry.value == null ? '_unknown_' : '${entry.value}';
      lines.add('- **${entry.key}**: $displayValue');
    }
  }
  lines.add('');

  // --- Additional Context (optional) ---
  if (report.extra != null) {
    lines.add('## Additional Context');
    lines.add('');
    lines.add('```json');
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      final serialized = encoder.convert(report.extra);
      if (serialized.length > 50000) {
        lines.add('{"_error":"Extra context too large"}');
      } else {
        lines.add(serialized);
      }
    } catch (_) {
      lines.add('{"_error":"Failed to serialize extra context"}');
    }
    lines.add('```');
    lines.add('');
  }

  return lines.join('\n');
}

/// Generates a document path for a crash report.
///
/// The path has the form `<prefix>/YYYY-MM-DD/<errorname>-<shortid>.md`,
/// where `<errorname>` is the lowercased error name with non-alphanumeric
/// characters (except hyphens) replaced by hyphens, and `<shortid>` is the
/// first 8 hex characters of the report ID (with hyphens stripped).
String generateDocPath(CrashReport report, {String prefix = 'crash-reports'}) {
  final date = report.timestamp.substring(0, 10);
  final errorName =
      report.errorName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
  final shortId = report.id.replaceAll('-', '').substring(0, 8);
  return '$prefix/$date/$errorName-$shortId.md';
}
