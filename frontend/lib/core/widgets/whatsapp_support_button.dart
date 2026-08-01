import 'package:flutter/material.dart';

import '../utils/whatsapp_support.dart';

/// Full-width "Contact via WhatsApp" CTA used wherever a patient has a live
/// service window (ongoing-care card, booking tracking sheet).
///
/// Deliberately paints WhatsApp brand green in both themes instead of the
/// ambient palette — the button is recognised by its colour, and it reads
/// correctly on the dark home canvas and the light booking sheet alike.
class WhatsAppSupportButton extends StatelessWidget {
  /// WhatsApp brand green + a darker pressed/border tone.
  static const Color brandGreen = Color(0xFF25D366);
  static const Color brandGreenDark = Color(0xFF128C7E);

  /// Message pre-filled in the chat. Build booking-scoped copy with
  /// [bookingWhatsAppMessage].
  final String message;
  final String label;

  /// Outlined (secondary) rendering for rows that already own a filled CTA.
  final bool outlined;

  const WhatsAppSupportButton({
    super.key,
    required this.message,
    this.label = 'Contact via WhatsApp',
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(Icons.chat_rounded, size: 18);
    final text = Text(label, overflow: TextOverflow.ellipsis);
    final padding = const EdgeInsets.symmetric(vertical: 12);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    void onPressed() => launchWhatsAppSupport(context, message: message);

    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: brandGreen,
          side: const BorderSide(color: brandGreen),
          padding: padding,
          shape: shape,
        ),
        icon: icon,
        label: text,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        padding: padding,
        shape: shape,
      ),
      icon: icon,
      label: text,
    );
  }
}
