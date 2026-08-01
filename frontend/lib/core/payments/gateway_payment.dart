import 'package:url_launcher/url_launcher.dart';

/// Shared SSLCommerz gateway runner (init session → hosted checkout OR
/// simulated settle → confirm). Extracted from the booking deposit /
/// balance flow so any future payment reuses the same orchestration.
///
/// [session] is the `init` endpoint's response: `{simulated, tranId,
/// gatewayUrl, settled?}`. [confirm] posts the matching `confirm`
/// endpoint; its return value is intentionally untyped — each flow
/// parses its own row (care request map, Prescription, …).
///
/// With a real gateway session the hosted page opens externally and
/// settlement completes server-side via the IPN webhook — the caller's
/// poll/socket refresh surfaces the new status when the patient returns.
Future<void> completeGatewayPayment({
  required Map<String, dynamic> session,
  required Future<dynamic> Function(String? tranId) confirm,
}) async {
  final simulated = session['simulated'] == true;
  final tranId = session['tranId']?.toString();
  final gatewayUrl = session['gatewayUrl']?.toString();
  final settledServerSide = session['settled'] == true;

  if (!simulated && gatewayUrl != null && gatewayUrl.isNotEmpty) {
    await launchUrl(Uri.parse(gatewayUrl),
        mode: LaunchMode.externalApplication);
  } else if (!settledServerSide) {
    // Simulated / zero-amount: settle immediately.
    await confirm(tranId);
  }
}
