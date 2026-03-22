import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'signature.dart' as sig;
import 'types.dart';

/// Uploads a formatted crash report to the Lifestream Vault API.
///
/// Throws [UploadException] on network errors, timeouts, or non-2xx responses.
Future<void> uploadReport({
  required String apiUrl,
  required String vaultId,
  required String apiKey,
  required String content,
  required String path,
  bool enableRequestSigning = true,
  CustomSignRequest? customSignRequest,
  http.Client? httpClient,
}) async {
  final url = '$apiUrl/api/v1/vaults/$vaultId/documents/$path';
  final body = jsonEncode({
    'content': content,
    'createIntermediateFolders': true,
  });

  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  if (enableRequestSigning) {
    final uri = Uri.parse(url);
    if (customSignRequest != null) {
      final sigHeaders = await customSignRequest(apiKey, 'PUT', uri.path, body);
      headers.addAll(sigHeaders);
    } else {
      final sigHeaders = sig.signRequest(apiKey, 'PUT', uri.path, body);
      headers.addAll(sigHeaders);
    }
  }

  final client = httpClient ?? http.Client();
  final shouldCloseClient = httpClient == null;

  try {
    final http.Response response;
    try {
      response = await client
          .put(Uri.parse(url), headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw UploadException('Upload timed out after 15 seconds');
    } catch (e) {
      if (e is UploadException) rethrow;
      throw UploadException('Network error: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.isNotEmpty
          ? response.body
          : response.reasonPhrase ?? 'Unknown error';
      throw UploadException(
        'Upload failed with HTTP ${response.statusCode}: $detail',
        statusCode: response.statusCode,
      );
    }
  } finally {
    if (shouldCloseClient) {
      client.close();
    }
  }
}
