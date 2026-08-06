import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/patient_active_request.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../booking_flow_pages.dart' show money;
import 'patient_home_palette.dart';

/// The booking's own facts — service, address, schedule, provider — kept
/// separate from the lifecycle timeline above it.
///
/// The timeline answers "where is my booking"; this answers "what did I
/// actually book". They were previously interleaved on the review tab, which
/// is why a patient checking their address had to read past five status rows.
class BookingSummaryCard extends StatelessWidget {
  final PatientActiveRequest request;

  const BookingSummaryCard({super.key, required this.request});

  String get _scheduleLabel {
    final committed = request.scheduledTimeLabel?.trim();
    // The admin's committed window beats the patient's stated preference —
    // it's the one that will actually happen.
    if (committed != null && committed.isNotEmpty) return committed;
    final preferred = request.scheduledAt;
    if (preferred == null) return 'As soon as possible';
    return DateFormat('EEE d MMM · h:mm a').format(preferred);
  }

  String get _serviceLabel {
    final hours = request.durationHours;
    if (hours != null) {
      return '${request.serviceTitleEn} · $hours hr${hours == 1 ? '' : 's'}';
    }
    return request.serviceTitleEn;
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final rows = <(String, String)>[
      ('Service', _serviceLabel),
      ('Location', request.locationLabel),
      ('Schedule', _scheduleLabel),
      if (request.offer != null) ('Your offer', money(request.offer ?? 0)),
      if (request.displayProviderName != null)
        ('Provider', request.displayProviderName ?? '—'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SUMMARY',
                style: MtTextStyles.sectionLabel.copyWith(
                  color: hd.muted,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: hd.border),
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      rows[i].$1,
                      style: MtTextStyles.bodyMd.copyWith(color: hd.muted),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: MtTextStyles.labelMd.copyWith(color: hd.title),
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1)
              Divider(height: 1, color: hd.border, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

/// Low-emphasis secondary action — chat admin, cancel request. Deliberately
/// outlined so it never competes with the payment CTA inside the timeline.
class OutlinedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const OutlinedActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final color = destructive ? hd.danger : hd.title;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: hd.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: destructive
                  ? hd.danger.withValues(alpha: 0.5)
                  : hd.border,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
