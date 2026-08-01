import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/support_config.dart';

/// Opens the official Taafi support thread in WhatsApp with [message]
/// pre-filled, falling back to a snackbar carrying the dialable number when
/// the handset has no WhatsApp (or the launch is refused).
///
/// Single entry point for every "talk to a human" action in the app — the
/// support number lives in [SupportConfig.whatsappNumber] alone.
Future<void> launchWhatsAppSupport(
  BuildContext context, {
  required String message,
  String? fallbackMessage,
}) async {
  // Captured before the await so the snackbar never touches a stale context.
  final messenger = ScaffoldMessenger.of(context);
  final digits = SupportConfig.whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
  final uri = Uri.parse(
    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
  );
  final fallback = fallbackMessage ??
      'Could not open WhatsApp. Reach us at '
          '${SupportConfig.whatsappNumberDisplay}';
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(fallback)));
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(fallback)));
  }
}

/// Opens a WhatsApp thread with an arbitrary [phone] — the assigned provider,
/// not the support desk — with [message] pre-filled.
///
/// Kept separate from [launchWhatsAppSupport] because the failure copy has to
/// differ: a patient who can't reach their nurse needs the nurse's number read
/// back to them, not the support line's.
Future<void> launchWhatsAppTo(
  BuildContext context, {
  required String phone,
  required String message,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No contact number on file for this provider.')),
    );
    return;
  }
  final uri = Uri.parse(
    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
  );
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open WhatsApp. Their number is $phone')),
      );
    }
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open WhatsApp. Their number is $phone')),
    );
  }
}

/// Places a `tel:` call to [phone] through the handset dialer.
///
/// On failure the number itself goes into the snackbar, so the patient can
/// still dial it by hand — the whole point of the button is reaching a person
/// who is on their way to the door.
Future<void> launchPhoneCall(
  BuildContext context, {
  required String phone,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Keep a leading '+' (country code) and drop spaces/dashes/brackets.
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No contact number on file for this provider.')),
    );
    return;
  }
  try {
    final ok = await launchUrl(Uri(scheme: 'tel', path: cleaned));
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('Could not start a call to $phone')));
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text('Could not start a call to $phone')));
  }
}

/// Opening line for a patient → assigned provider chat. Identifies the patient
/// and the booking straight away, because the provider is mid-round and holds
/// several visits at once.
String providerWhatsAppMessage({
  required String patientName,
  required String bookingId,
  String? serviceTitle,
  String? scheduledLabel,
}) {
  final name = patientName.trim();
  final who = name.isEmpty ? 'I am the patient' : 'I am $name, your patient';
  final service = serviceTitle?.trim() ?? '';
  final about = service.isEmpty ? '' : ' for $service';
  final schedule = scheduledLabel?.trim() ?? '';
  final when = schedule.isEmpty ? '' : ' scheduled $schedule';
  return 'Hello, $who$about (booking #$bookingId)$when.';
}

/// Standard opening line for a booking-scoped support chat, so the agent sees
/// the booking id — plus the service and the admin-committed appointment time
/// when known — without having to ask for any of it.
String bookingWhatsAppMessage({
  required String bookingId,
  String? serviceTitle,
  String? scheduledLabel,
}) {
  final service = serviceTitle?.trim() ?? '';
  final about = service.isEmpty ? '' : ' ($service)';
  final schedule = scheduledLabel?.trim() ?? '';
  final when = schedule.isEmpty ? '' : ' scheduled for $schedule';
  return 'Hi Taafi, I need help with my booking #$bookingId$about$when.';
}
