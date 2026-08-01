import 'package:flutter/material.dart';

import '../../../../core/models/assigned_provider.dart';
import '../../../../core/models/booking_milestone.dart';
import '../../../../core/models/provider_type.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/whatsapp_support.dart';
import '../../../../core/widgets/initials_avatar.dart';
import 'booking_milestone_theme.dart';
import 'pulsing_status_dot.dart';

/// The direct line to the person coming to the patient's door.
///
/// Rendered once a booking reaches SCHEDULED / EN_ROUTE / IN_SERVICE and a
/// provider has actually been dispatched. It answers the three questions a
/// waiting patient has, in the order they ask them: who is coming, are they
/// really who the app says (name + designation + council registration), and
/// how do I reach them right now.
///
/// Deliberately separate from the Taafi support desk further down the tracking
/// screen: this card is for coordinating the visit itself — arrival time,
/// directions, "the gate is locked" — while support handles payments and
/// escalations. Mixing the two into one "contact us" button is what sends
/// patients to a call-centre queue when they need the nurse in their street.
class AssignedProviderCard extends StatelessWidget {
  final AssignedProvider provider;
  final MilestoneStyle style;

  /// Drives the status badge: "ON THE WAY" while the provider travels,
  /// "SCHEDULED FOR 4:00 PM" while the visit is still queued.
  final BookingMilestone milestone;

  /// Server-formatted appointment window ("Today, 04:00 PM"). Null until an
  /// admin commits to a time, in which case the badge falls back to the
  /// milestone's own wording rather than inventing a slot.
  final String? scheduledLabel;

  /// Pre-filled opening line for the WhatsApp thread.
  final String whatsAppMessage;

  const AssignedProviderCard({
    super.key,
    required this.provider,
    required this.style,
    required this.milestone,
    required this.scheduledLabel,
    required this.whatsAppMessage,
  });

  /// Short, shouty state for the badge. SCHEDULED folds in the committed time
  /// because "when" is the only thing the patient is waiting to learn at that
  /// point in the booking.
  String get _badgeText {
    if (milestone == BookingMilestone.scheduled) {
      final when = scheduledLabel?.trim();
      // "Today, 04:00 PM" → "SCHEDULED FOR 04:00 PM": the date carries no
      // information inside a badge that only shows on an in-flight booking.
      if (when != null && when.isNotEmpty) {
        final time = when.contains(',') ? when.split(',').last.trim() : when;
        return 'SCHEDULED FOR ${time.toUpperCase()}';
      }
    }
    return milestone.shortLabel;
  }

  @override
  Widget build(BuildContext context) {
    final accent = BookingMilestoneTheme.accentFor(context, milestone);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        // A heavier border than the neighbouring cards: this is the one block
        // on the screen the patient is meant to act from.
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(text: _badgeText, accent: accent, milestone: milestone),
          const SizedBox(height: 12),
          _IdentityRow(provider: provider, style: style, accent: accent),
          if (provider.isReachable) ...[
            const SizedBox(height: 14),
            _ContactActions(
              provider: provider,
              accent: accent,
              whatsAppMessage: whatsAppMessage,
            ),
          ] else ...[
            const SizedBox(height: 12),
            // No number on file: say so plainly instead of rendering buttons
            // that can't do anything. The support desk below is the fallback.
            Text(
              'Direct contact for this ${provider.type.roleLabel.toLowerCase()} '
              "isn't available yet — reach the Taafi support desk below and "
              'we will connect you.',
              style: MtTextStyles.bodySm.copyWith(color: style.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulsing state capsule. The dot animates only while something is actually
/// happening, so a scheduled-but-not-started visit doesn't imply movement.
class _StatusBadge extends StatelessWidget {
  final String text;
  final Color accent;
  final BookingMilestone milestone;

  const _StatusBadge({
    required this.text,
    required this.accent,
    required this.milestone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingStatusDot(
            color: accent,
            size: 8,
            animate: milestone.isLive,
            intense: milestone.isOnTheMove,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: MtTextStyles.labelSm.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo, name, role chip and the credential line.
class _IdentityRow extends StatelessWidget {
  final AssignedProvider provider;
  final MilestoneStyle style;
  final Color accent;

  const _IdentityRow({
    required this.provider,
    required this.style,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final photo = provider.photoUrl?.trim() ?? '';
    final credential = provider.credentialLine;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photo.isNotEmpty)
          ClipOval(
            child: Image.network(
              photo,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => InitialsAvatar(
                name: provider.name,
                size: 54,
                backgroundColor: style.surfaceHi,
                textColor: accent,
              ),
            ),
          )
        else
          InitialsAvatar(
            name: provider.name,
            size: 54,
            backgroundColor: style.surfaceHi,
            textColor: accent,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      provider.name,
                      style: MtTextStyles.labelLg.copyWith(
                        color: style.title,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      provider.type.roleLabel,
                      style: MtTextStyles.labelSm.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              // Only rendered when the provider's profile actually carries a
              // designation or a registration number — never a placeholder.
              if (credential.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  credential,
                  style: MtTextStyles.bodySm.copyWith(color: style.body),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Call + WhatsApp, side by side and equally weighted — a patient reaching for
/// this row is not in a state to read which one is "primary".
class _ContactActions extends StatelessWidget {
  final AssignedProvider provider;
  final Color accent;
  final String whatsAppMessage;

  const _ContactActions({
    required this.provider,
    required this.accent,
    required this.whatsAppMessage,
  });

  @override
  Widget build(BuildContext context) {
    final role = provider.type.roleLabel;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const padding = EdgeInsets.symmetric(vertical: 12);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () =>
                launchPhoneCall(context, phone: provider.dialablePhone),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: padding,
              shape: shape,
            ),
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text('Call $role', overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => launchWhatsAppTo(
              context,
              phone: provider.dialablePhone,
              message: whatsAppMessage,
            ),
            style: FilledButton.styleFrom(
              // WhatsApp brand green in both themes — the button is
              // recognised by its colour before its label is read.
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: padding,
              shape: shape,
            ),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('WhatsApp', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}
