import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/active_care_step.dart';
import '../../../core/models/booking_milestone.dart';
import '../../../core/models/booking_transaction.dart';
import '../../../core/models/care_request_status.dart';
import '../../../core/models/patient_active_request.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/whatsapp_support.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../../core/widgets/whatsapp_support_button.dart';
import '../../appointments/providers/feedback_provider.dart';
import '../../auth/auth_provider.dart';
import '../../prescriptions/prescriptions_provider.dart';
import '../navigation/patient_nav_provider.dart';
import 'booking_flow_pages.dart';
import 'widgets/active_care_timeline_stepper.dart';
import 'widgets/active_status_header_card.dart';
import 'widgets/assigned_provider_card.dart';
import 'widgets/booking_milestone_theme.dart';
import 'widgets/booking_summary_card.dart';
import 'widgets/cancel_request_dialog.dart';
import 'widgets/care_session_progress_card.dart';
import 'widgets/deposit_prompt_card.dart';
import 'widgets/patient_home_palette.dart';
import 'widgets/payment_method_choice_card.dart';
import 'widgets/preparation_tips_banner.dart';
import 'widgets/provider_assignment_cards.dart';

/// The patient's single active-booking surface.
///
/// Replaces the "Under Review" and "Service Status" tabs, which split one
/// booking across two screens with two independently-derived timelines. The
/// same request rendered as "Admin reviewing · step 2 of 5" on one tab and
/// "Under Care Review · step 2 of 6" on the other, and which tab you landed on
/// depended on a status→tab mapping that had to be kept in sync in four
/// places. Worse, the two surfaces owned different halves of the booking: the
/// deposit CTA lived on one and the assigned provider's phone number on the
/// other, so a patient who had just paid had to know to switch tabs to find
/// out who was coming.
///
/// One screen, one timeline ([ActiveCareTimelineStepper]), and every action
/// attached to the step that produced it.
class ActiveCareTab extends ConsumerStatefulWidget {
  const ActiveCareTab({super.key});

  @override
  ConsumerState<ActiveCareTab> createState() => _ActiveCareTabState();
}

class _ActiveCareTabState extends ConsumerState<ActiveCareTab> {
  StreamSubscription<Map<String, dynamic>>? _cashSub;
  StreamSubscription<Map<String, dynamic>>? _careLogSub;
  StreamSubscription<Map<String, dynamic>>? _prefSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final socket = ref.read(socketManagerProvider);
      // Live cash settlement: when the provider confirms receiving the balance
      // in cash on THEIR device, the backend emits `payment_settled_cash` to
      // this patient's user room. Refresh the booking feed (the invoice card
      // flips to settled) and the prescription surfaces (the gate advances to
      // admin review) without a hard reload.
      _cashSub = socket?.onCashSettled.listen((_) {
        if (!mounted) return;
        // ignore: unused_result
        ref.read(patientHomeFeedProvider.notifier).refresh();
        ref.invalidate(patientPrescriptionsProvider);
        ref.invalidate(medicationsHubProvider);
      });
      // Live nursing report: the assigned nurse just filed the care log and
      // closed the visit. Refresh the feed and the latest-completed
      // appointment so the History surfaces render it immediately.
      _careLogSub = socket?.onNurseCareLog.listen((_) {
        if (!mounted) return;
        // ignore: unused_result
        ref.read(patientHomeFeedProvider.notifier).refresh();
        ref.invalidate(latestCompletedAppointmentProvider);
      });
      // Live payment-preference change (set on another device, or reverted by
      // a provider): refresh so the invoice card's cash-arranged state stays
      // in sync.
      _prefSub = socket?.onPaymentPreferenceUpdated.listen((_) {
        if (!mounted) return;
        // ignore: unused_result
        ref.read(patientHomeFeedProvider.notifier).refresh();
      });
    });
  }

  @override
  void dispose() {
    _cashSub?.cancel();
    _careLogSub?.cancel();
    _prefSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(patientHomeFeedProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final feedAsync = ref.watch(patientHomeFeedProvider);
    final activeRequest = ref.watch(patientActiveRequestProvider);

    // Hand the booking to History the moment it is BOTH delivered and fully
    // reconciled. Not a moment sooner: `service_completed_awaiting_final_
    // payment` also reports milestone COMPLETED, and that is exactly where the
    // Pay Balance CTA and the prescription gate live — punting it there would
    // strand the last thing the patient has to do.
    ref.listen<PatientActiveRequest?>(patientActiveRequestProvider,
        (prev, next) {
      if (next == null) return;
      final wasOpen = prev == null || !ActiveCareTimeline(prev).isSettledClosed;
      if (wasOpen && ActiveCareTimeline(next).isSettledClosed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.goToActivities(sub: PatientActivitiesTab.history);
        });
      }
    });

    return Container(
      color: hd.canvas,
      child: RefreshIndicator(
        color: hd.violetBright,
        backgroundColor: hd.surfaceHi,
        onRefresh: _refresh,
        child: feedAsync.when(
          loading: () => const _LoadingView(),
          error: (e, _) => _ErrorView(message: e.toString(), onRetry: _refresh),
          data: (_) {
            if (activeRequest == null) return const _NoActiveCareView();
            final timeline = ActiveCareTimeline(activeRequest);
            if (timeline.isSettledClosed) {
              return const _SettledHandoffView();
            }
            return _ActiveCareView(request: activeRequest);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The active booking
// ---------------------------------------------------------------------------

class _ActiveCareView extends ConsumerWidget {
  final PatientActiveRequest request;

  const _ActiveCareView({required this.request});

  /// Statuses the backend's `PATIENT_CANCELLABLE` guard accepts
  /// (`backend/src/routes/patient.js`). Mirrored exactly so the button never
  /// promises something the server will refuse.
  static const _cancellable = {
    CareRequestStatus.submitted,
    CareRequestStatus.awaitingDeposit,
    CareRequestStatus.depositRequired,
    CareRequestStatus.approved,
  };

  /// True once the visit itself has happened and the outstanding balance is
  /// the only thing left. The deposit prompt must never pre-empt that: the
  /// balance invoice is the actionable surface at that point, and it already
  /// accounts for whatever deposit was (or wasn't) collected.
  bool get _isPostService =>
      request.rawStatus ==
          CareRequestStatus.serviceCompletedAwaitingFinalPayment ||
      request.rawStatus ==
          CareRequestStatus.amountAssignedAwaitingFinalPayment;

  Future<void> _chatAdmin(BuildContext context) {
    return launchWhatsAppSupport(
      context,
      message: 'Hi Taafi admin, I have a question about booking ${request.id}.',
      fallbackMessage:
          'Reach admin at ${SupportConfig.whatsappNumberDisplay}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final timeline = ActiveCareTimeline(request);
    final booking = BookingTransaction.fromActiveRequest(request);
    // The ledger only exists once the money story does. Through Phase 1 there
    // is no amount to show, and rendering an empty invoice would read as a
    // screen that failed to price itself.
    final showInvoice = !request.isAwaitingReviewCall &&
        !(request.needsDeposit && !_isPostService);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        ActiveStatusHeaderCard(request: request),
        const SizedBox(height: 16),
        ActiveCareTimelineStepper(
          request: request,
          stepActions: _stepActions(context, ref, timeline, booking),
        ),

        if (showInvoice) ...[
          const SizedBox(height: 16),
          _SectionLabel('YOUR INVOICE'),
          const SizedBox(height: 10),
          DynamicInvoiceCard(booking: booking),
        ],

        // Remaining-balance pre-commitment: Cash on Service vs Digital.
        if (PaymentMethodChoiceCard.shouldShow(request))
          PaymentMethodChoiceCard(request: request),

        const SizedBox(height: 16),
        BookingSummaryCard(request: request),

        const SizedBox(height: 16),
        if (timeline.isCancelled)
          OutlinedActionButton(
            icon: Icons.add_circle_outline,
            label: 'Start a new request',
            onTap: ref.goToNewRequest,
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat admin',
                  onTap: () => _chatAdmin(context),
                ),
              ),
              // Self-cancel disappears once a coordinator claims the dispatch,
              // matching the server-side guard.
              if (_cancellable.contains(request.rawStatus)) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedActionButton(
                    icon: Icons.close,
                    label: 'Cancel request',
                    destructive: true,
                    onTap: () =>
                        confirmCancelRequest(context, ref, request.id),
                  ),
                ),
              ],
            ],
          ),

        if (request.milestone.isLive) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: WhatsAppSupportButton(
              label: 'WhatsApp Support',
              message: bookingWhatsAppMessage(
                bookingId: request.id,
                serviceTitle: request.serviceTitleEn,
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),
        Text(
          'Booking ID  #${request.id}',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: hd.muted),
        ),
      ],
    );
  }

  /// The contextual block each step carries, keyed by step.
  ///
  /// Only the *current* step gets one. A done step's action has already been
  /// taken and an upcoming one's cannot be, so rendering either would put dead
  /// controls on the rail.
  Map<ActiveCareStep, Widget> _stepActions(
    BuildContext context,
    WidgetRef ref,
    ActiveCareTimeline timeline,
    BookingTransaction booking,
  ) {
    if (timeline.isCancelled) return const {};
    final step = timeline.currentStep;

    switch (step) {
      case ActiveCareStep.submitted:
        return const {ActiveCareStep.submitted: AwaitingReviewCallCard()};

      case ActiveCareStep.feeSet:
        // Gate on the MONEY, not the lifecycle status — and never ahead of the
        // post-service balance, which supersedes it.
        if (!request.needsDeposit || _isPostService) return const {};
        return {
          ActiveCareStep.feeSet: DepositPromptCard(
            booking: booking,
            onPay: () => showConfirmAppointmentRequestSheet(
              context,
              bookingId: booking.bookingId,
              serviceName: booking.serviceName,
              depositAmount: booking.depositDue,
            ),
          ),
        };

      case ActiveCareStep.teamAssigned:
      case ActiveCareStep.enRoute:
      case ActiveCareStep.inService:
        return {step: _CareTeamBlock(request: request, step: step)};

      case ActiveCareStep.settled:
        // The invoice section below owns the balance CTA; duplicating it on
        // the rail would give the patient two Pay buttons for one debt.
        return const {};
    }
  }
}

/// Who is attending, how to reach them, and — while the visit runs — how long
/// it has been going. Rendered inside whichever of the three provider steps is
/// current, so the contact details follow the booking rather than sitting on a
/// step the patient has already scrolled past.
class _CareTeamBlock extends ConsumerWidget {
  final PatientActiveRequest request;
  final ActiveCareStep step;

  const _CareTeamBlock({required this.request, required this.step});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = BookingMilestoneTheme.of(context, request.milestone);
    final provider = request.assignedProvider;
    final patientName = ref.watch(currentUserProvider)?.name ?? '';
    final tip = request.preparationTip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (provider != null && request.isProviderActive)
          AssignedProviderCard(
            provider: provider,
            style: style,
            milestone: request.milestone,
            scheduledLabel: request.scheduledTimeLabel,
            whatsAppMessage: providerWhatsAppMessage(
              patientName: patientName,
              bookingId: request.id,
              serviceTitle: request.serviceTitleEn,
              scheduledLabel: request.scheduledTimeLabel,
            ),
          )
        else if (hasLegacyProvider(request))
          // Older payloads carry the populated doctor/nurse blocks but no
          // `assigned_provider` snapshot. Render those rather than telling a
          // patient with an assigned clinician that nobody is assigned.
          LegacyProviderCard(request: request)
        else
          AwaitingAssignmentCard(roleLabel: request.providerRoleLabel),

        if (step == ActiveCareStep.inService) ...[
          const SizedBox(height: 12),
          CareSessionProgressCard(
            startedAt: ActiveCareTimeline(request)
                .stampOf(ActiveCareStep.inService),
            roleLabel: request.providerRoleLabel,
            style: style,
          ),
        ],

        // Role-specific prep guidance, only while it can still be acted on.
        if (tip != null) ...[
          const SizedBox(height: 12),
          PreparationTipsBanner(
            tip: tip,
            roleLabel: request.providerRoleLabel,
            style: style,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Non-active states
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.sectionLabel.copyWith(
        color: HomeDark.of(context).muted,
        letterSpacing: 1,
      ),
    );
  }
}

/// Shown for the one frame between a booking settling and the tab handing off
/// to History, and again if the patient navigates back here afterwards.
class _SettledHandoffView extends ConsumerWidget {
  const _SettledHandoffView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      children: [
        Icon(Icons.check_circle_outline, color: hd.positive, size: 56),
        const SizedBox(height: 14),
        Text(
          'Visit completed & settled',
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: hd.title),
        ),
        const SizedBox(height: 6),
        Text(
          'Nothing is outstanding. Your invoice and prescription have moved '
          'to your records.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodyMd.copyWith(color: hd.body),
        ),
        const SizedBox(height: 24),
        OutlinedActionButton(
          icon: Icons.history,
          label: 'View in History',
          onTap: () => ref.goToActivities(sub: PatientActivitiesTab.history),
        ),
        const SizedBox(height: 12),
        OutlinedActionButton(
          icon: Icons.add_circle_outline,
          label: 'Book care again',
          onTap: ref.goToNewRequest,
        ),
      ],
    );
  }
}

/// Empty state — the whole tab when the patient has no open booking.
class _NoActiveCareView extends ConsumerWidget {
  const _NoActiveCareView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        MtEmptyState(
          icon: Icons.health_and_safety_outlined,
          title: 'No active care requests right now',
          subtitle: 'Need medical assistance at home? Place a request — it is '
              'free, and our care team will call you to set everything up.',
          actionLabel: 'Book Care Now',
          onAction: ref.goToNewRequest,
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        MtSkeleton.box(height: 150, radius: 16),
        const SizedBox(height: 16),
        MtSkeleton.box(height: 320, radius: 16),
        const SizedBox(height: 16),
        MtSkeleton.box(height: 180, radius: 16),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        MtEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your booking',
          subtitle: message,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      ],
    );
  }
}
