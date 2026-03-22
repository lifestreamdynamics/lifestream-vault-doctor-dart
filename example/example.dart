import 'package:lifestream_doctor/lifestream_doctor.dart';

void main() async {
  // Create a doctor instance
  final doctor = LifestreamDoctor(
    apiUrl: 'https://vault.example.com',
    vaultId: 'your-vault-id',
    apiKey: 'lsv_k_your_api_key',
  );

  // Grant consent (required before reports are sent)
  await doctor.grantConsent();

  // Add breadcrumbs to track user actions
  doctor.addBreadcrumb(Breadcrumb(
    timestamp: DateTime.now().toUtc().toIso8601String(),
    type: 'navigation',
    message: 'Opened settings',
  ));

  // Capture an exception
  try {
    throw StateError('Something went wrong');
  } catch (e, stack) {
    await doctor.captureException(e, stackTrace: stack);
  }

  // Capture a diagnostic message
  await doctor.captureMessage(
    'User completed onboarding',
    severity: Severity.info,
  );

  // Flush any queued reports (e.g., after reconnecting)
  final result = await doctor.flushQueue();
  print('Flushed: ${result.sent} sent, ${result.failed} failed');
}
