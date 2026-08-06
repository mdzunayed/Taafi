import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin_nav.dart';
import '../../admin_providers.dart';
import '../tabs/admin_booking_review.dart';
import '../tabs/assign_team_tab.dart';
import '../tabs/prescription_approval_tab.dart';
import '../tabs/review_queue_tab.dart';
import 'hub_scaffold.dart';

/// Unified bookings workspace — the whole booking lifecycle behind one
/// sidebar link and four in-place tabs.
///
/// This replaces six former destinations: Booking pipeline, Live monitor,
/// Review queue, Booking review, Assign team, and Rx approvals. Switching
/// tabs filters in place instead of swapping the whole screen, so the
/// admin keeps their scroll position in the sidebar and the search box in
/// the top bar stays live across the whole lifecycle.
///
/// Every tab reads the same providers the old standalone screens did, so
/// the consolidated view can never drift from the underlying queues.
class BookingsHub extends ConsumerWidget {
  const BookingsHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(bookingsTabProvider);
    final counts = ref.watch(requestCountsProvider);
    final pricingCount = ref.watch(bookingReviewCountProvider);
    final assignmentCount = ref.watch(needsAssignmentQueueProvider).length;
    final rxCount = ref.watch(adminPrescriptionQueueProvider).maybeWhen(
          data: (scripts) => scripts.length,
          orElse: () => 0,
        );

    return HubScaffold<BookingsTab>(
      selected: selected,
      onSelect: (tab) =>
          ref.read(bookingsTabProvider.notifier).state = tab,
      tabs: [
        HubTab(
          value: BookingsTab.all,
          label: BookingsTab.all.label,
          icon: Icons.list_alt,
          count: counts['all'],
        ),
        HubTab(
          value: BookingsTab.pricing,
          label: BookingsTab.pricing.label,
          icon: Icons.request_quote_outlined,
          count: pricingCount,
        ),
        HubTab(
          value: BookingsTab.assignment,
          label: BookingsTab.assignment.label,
          icon: Icons.groups_2_outlined,
          count: assignmentCount,
        ),
        HubTab(
          value: BookingsTab.rxReview,
          label: BookingsTab.rxReview.label,
          icon: Icons.fact_check_outlined,
          count: rxCount,
        ),
      ],
      body: switch (selected) {
        // The full care-request table, carrying the status chips and bulk
        // approve/reject toolbar that used to be the Review queue screen.
        BookingsTab.all => const ReviewQueueTab(),
        BookingsTab.pricing => const AdminBookingReviewPage(),
        BookingsTab.assignment => const AssignTeamTab(),
        BookingsTab.rxReview => const PrescriptionApprovalTab(),
      },
    );
  }
}
