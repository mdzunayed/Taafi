import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/patient_home_repository.dart';
import '../../../../core/models/patient_active_request.dart';
import '../../../../core/models/patient_request_status.dart';
import '../../../../core/theme/app_colors_ext.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../navigation/patient_nav_provider.dart';

/// Client-side half of the one-active-booking rule enforced by
/// `POST /patient/requests` (409 when the patient already holds a
/// non-terminal booking).
///
/// Rendered above any "Book" affordance while [patientActiveRequestProvider]
/// is non-null, so the patient is told *why* the button is dead before they
/// press it — and is handed a one-tap route to the booking that's blocking
/// them. The backend stays the authority; this only removes the dead end.
class ActiveBookingBanner extends ConsumerWidget {
  /// Invoked before the tab switch — used by pushed full-screen routes
  /// (e.g. service details) to pop themselves off first, so the shell's
  /// Activities tab is actually visible once we land on it.
  final VoidCallback? onBeforeNavigate;

  const ActiveBookingBanner({super.key, this.onBeforeNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(patientActiveRequestProvider);
    if (active == null) return const SizedBox.shrink();

    final c = context.appColors;
    return Semantics(
      button: true,
      label: 'You have an active booking in progress. View its status.',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          onBeforeNavigate?.call();
          ref.goToActivities(sub: _tabFor(active));
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.infoBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.info.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.pending_actions_outlined, size: 20, color: c.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You have an active booking in progress. '
                  'Tap here to view status.',
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: c.info),
            ],
          ),
        ),
      ),
    );
  }

  /// Land on the sub-tab that can actually show this booking. A request the
  /// admin hasn't dispatched yet has no tracker to render, so it routes to
  /// "Under Review" — same mapping the notification deep-links use.
  static PatientActivitiesTab _tabFor(PatientActiveRequest request) {
    switch (request.status.homeRouteTarget) {
      case HomeRouteTarget.tracking:
        return PatientActivitiesTab.tracking;
      case HomeRouteTarget.underReview:
      case HomeRouteTarget.none:
        return PatientActivitiesTab.underReview;
    }
  }
}
