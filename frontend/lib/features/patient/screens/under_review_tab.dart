import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/booking_transaction.dart';
import '../../../core/network/socket_manager.dart';
import '../../appointments/providers/feedback_provider.dart';
import '../../prescriptions/prescriptions_provider.dart';
import '../../../core/models/patient_active_request.dart';
import '../../../core/models/patient_request_status.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/whatsapp_support.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../../core/widgets/status_badge.dart';
import '../navigation/patient_nav_provider.dart';
import 'booking_flow_pages.dart';
import 'widgets/patient_home_palette.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

/// Patient-facing "Under Review" tab. Subscribes to the active request and
/// renders one of four states:
///
///  - **loading**  — initial fetch, no cached data yet.
///  - **empty**    — no active request; offer a path back to the booking form.
///  - **review**   — request is `pendingReview` or `accepted`; show timeline.
///  - **terminal** — request is `completed`/`rejected`/`cancelled`; show
///                   summary + return-to-home CTA. (Tracking-grade statuses
///                   auto-jump to the Tracking tab so the patient sees the
///                   live map without an extra tap.)
class UnderReviewTab extends ConsumerStatefulWidget {
  const UnderReviewTab({super.key});

  @override
  ConsumerState<UnderReviewTab> createState() => _UnderReviewTabState();
}

class _UnderReviewTabState extends ConsumerState<UnderReviewTab> {
  StreamSubscription<Map<String, dynamic>>? _cashSub;
  StreamSubscription<Map<String, dynamic>>? _careLogSub;
  StreamSubscription<Map<String, dynamic>>? _prefSub;

  @override
  void initState() {
    super.initState();
    // Live cash settlement: when the provider confirms receiving the
    // balance in cash on THEIR device, the backend emits
    // `payment_settled_cash` to this patient's user room. Refresh the
    // booking feed (the invoice card flips to settled) and the
    // prescription surfaces (the gate advances to admin review) without
    // a hard reload.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final socket = ref.read(socketManagerProvider);
      _cashSub = socket?.onCashSettled.listen((_) {
        if (!mounted) return;
        // ignore: unused_result
        ref.read(patientHomeFeedProvider.notifier).refresh();
        ref.invalidate(patientPrescriptionsProvider);
        ref.invalidate(medicationsHubProvider);
      });
      // Live nursing report: the assigned nurse just filed the care log and
      // closed the visit (`nurse_care_log_submitted`). Refresh the feed (the
      // card flips to the completed / payment-due state) and the
      // latest-completed appointment so the Rating tab's nursing report
      // renders immediately.
      _careLogSub = socket?.onNurseCareLog.listen((_) {
        if (!mounted) return;
        // ignore: unused_result
        ref.read(patientHomeFeedProvider.notifier).refresh();
        ref.invalidate(latestCompletedAppointmentProvider);
      });
      // Live payment-preference change (e.g. the patient set it on another
      // device, or a provider reverted it): refresh so the invoice card's
      // cash-arranged state stays in sync.
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

  Future<void> _refresh() {
    return ref.read(patientHomeFeedProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final feedAsync = ref.watch(patientHomeFeedProvider);
    final activeRequest = ref.watch(patientActiveRequestProvider);

    // Auto-advance to the Tracking tab when the request moves past review.
    // We listen instead of mutating during build so we don't fight the
    // animation framework.
    ref.listen<PatientActiveRequest?>(patientActiveRequestProvider,
        (prev, next) {
      if (next == null) return;
      if (next.status.homeRouteTarget == HomeRouteTarget.tracking) {
        // Defer to the next frame to avoid `setState during build` and to let
        // the user briefly see the "Doctor confirmed" state before we move.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Hop into the Tracking sub-tab inside the Activities
          // bottom-nav destination via the unified shell helper.
          ref.goToActivities(sub: PatientActivitiesTab.tracking);
        });
      }
    });

    return RefreshIndicator(
      color: hd.violet,
      onRefresh: _refresh,
      child: feedAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: _refresh,
        ),
        data: (_) {
          if (activeRequest == null) {
            return const _EmptyView();
          }
          // Two-phase booking gate. While the request is in a confirmation
          // state (awaiting deposit / under review / awaiting final payment)
          // we render the dedicated midnight booking surface instead of the
          // legacy provider-dispatch timeline.
          final bookingStatus =
              BookingStatusX.fromWire(activeRequest.rawStatus);
          if (_isBookingPhase(bookingStatus)) {
            return _BookingPhaseView(request: activeRequest);
          }
          final status = activeRequest.status;
          if (!status.isActive) {
            return _TerminalView(request: activeRequest);
          }
          // pendingReview & accepted (and the brief moment before
          // auto-advance to tracking) render here.
          return _ReviewView(request: activeRequest);
        },
      ),
    );
  }
}

/// Whether the request should render the booking/invoice surface: the
/// two-phase confirmation gate (deposit / review / legacy awaiting final
/// payment) AND the post-service payment-due state, where the invoice
/// card resurfaces with the Pay Balance CTA.
bool _isBookingPhase(BookingStatus s) {
  switch (s) {
    case BookingStatus.awaitingDeposit:
    case BookingStatus.depositPaidAdminReviewing:
    case BookingStatus.amountAssignedAwaitingFinalPayment:
    case BookingStatus.serviceCompletedAwaitingFinalPayment:
      return true;
    case BookingStatus.completed:
    case BookingStatus.cancelled:
      return false;
  }
}

// ============================================================================
// Two-phase booking surface (midnight theme)
// ============================================================================

/// Full-bleed midnight surface that renders the current booking phase: the
/// ৳100 deposit prompt, the "under review" invoice placeholder, or the live
/// dynamic invoice with the outstanding balance + Pay CTA.
/// Patient self-cancel, shared by the review timeline and the awaiting-deposit
/// surface (both states the backend's `PATIENT_CANCELLABLE` guard accepts).
Future<void> _confirmCancel(
  BuildContext context,
  WidgetRef ref,
  String requestId,
) async {
  final hd = HomeDark.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final reason = await showDialog<_CancelDialogResult>(
    context: context,
    builder: (dialogContext) => const _CancelConfirmDialog(),
  );
  if (reason == null || !reason.confirmed) return;

  try {
    await ref
        .read(patientHomeFeedProvider.notifier)
        .cancelActiveRequest(reason: reason.reason);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Request $requestId cancelled'),
        backgroundColor: hd.positive,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not cancel request: $e'),
        backgroundColor: hd.danger,
      ),
    );
  }
}

class _BookingPhaseView extends ConsumerWidget {
  final PatientActiveRequest request;

  const _BookingPhaseView({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final booking = BookingTransaction.fromActiveRequest(request);
    return Container(
      color: hd.canvas,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          Text(
            'REQUEST #${request.id}',
            style: TextStyle(
              color: hd.muted,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (booking.status == BookingStatus.awaitingDeposit) ...[
            _DepositPrompt(
              booking: booking,
              onPay: () => showConfirmAppointmentRequestSheet(
                context,
                bookingId: booking.bookingId,
                serviceName: booking.serviceName,
              ),
            ),
            const SizedBox(height: 12),
            // A patient who decides not to pay the deposit needs a way out:
            // this booking counts as "active", so until it's cancelled the
            // one-active-booking rule blocks every new request. Nothing has
            // been paid in this state, so cancelling costs nothing.
            _OutlinedAction(
              icon: Icons.close,
              label: "Cancel — I don't want to book",
              destructive: true,
              onTap: () => _confirmCancel(context, ref, request.id),
            ),
          ] else
            DynamicInvoiceCard(booking: booking),
          const SizedBox(height: 18),
          _MidnightAdminLink(requestId: request.id),
        ],
      ),
    );
  }
}

class _DepositPrompt extends StatelessWidget {
  final BookingTransaction booking;
  final VoidCallback onPay;

  const _DepositPrompt({required this.booking, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hd.surface, hd.canvas],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hd.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                booking.serviceName.isEmpty
                    ? 'Care service'
                    : booking.serviceName,
                style: TextStyle(
                  color: hd.title,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              BookingStatusPill(status: booking.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your request is saved but not confirmed yet. Pay the ৳100 '
            'confirmation deposit to lock your slot and connect with our '
            'care management team. It is deducted from your final bill.',
            style: TextStyle(color: hd.body, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [hd.violet2, hd.violet],
                ),
                boxShadow: [BoxShadow(color: hd.glow, blurRadius: 20)],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPay,
                  borderRadius: BorderRadius.circular(16),
                  child: const Center(
                    child: Text(
                      'Complete ৳100 deposit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MidnightAdminLink extends StatelessWidget {
  final String requestId;
  const _MidnightAdminLink({required this.requestId});

  Future<void> _chatAdmin(BuildContext context) async {
    await launchWhatsAppSupport(
      context,
      message: 'Hi Taafi admin, I have a question about booking $requestId.',
      fallbackMessage:
          'Reach admin at ${SupportConfig.whatsappNumberDisplay}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Center(
      child: TextButton.icon(
        onPressed: () => _chatAdmin(context),
        icon: Icon(Icons.chat_bubble_outline,
            size: 16, color: hd.violetBright),
        label: Text(
          'Chat care management',
          style: TextStyle(color: hd.violetBright, fontSize: 13),
        ),
      ),
    );
  }
}

// ============================================================================
// State-specific views
// ============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const SizedBox(height: 12),
        Center(child: MtSkeleton.circle(size: 104)),
        const SizedBox(height: 20),
        Center(child: MtSkeleton.line(width: 220, height: 22)),
        const SizedBox(height: 10),
        Center(child: MtSkeleton.line(width: 260, height: 12)),
        const SizedBox(height: 28),
        MtSkeleton.box(height: 220, radius: 12),
        const SizedBox(height: 16),
        MtSkeleton.box(height: 180, radius: 12),
        const SizedBox(height: 16),
        MtSkeleton.box(height: 56, radius: 12),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        MtEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your request',
          subtitle: message,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      ],
    );
  }
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        MtEmptyState(
          icon: Icons.assignment_outlined,
          title: 'No request under review',
          bnTitle: 'কোনো আবেদন নেই',
          subtitle:
              'Once you submit a request, you can track its review status here.',
          bnSubtitle: 'একটি আবেদন জমা দিন।',
          actionLabel: 'Start a new request',
          onAction: ref.goToNewRequest,
        ),
      ],
    );
  }
}

class _TerminalView extends ConsumerWidget {
  final PatientActiveRequest request;

  const _TerminalView({required this.request});

  String get _title {
    switch (request.status) {
      case PatientRequestStatus.completed:
        return 'Visit completed';
      case PatientRequestStatus.cancelled:
        return 'Request cancelled';
      case PatientRequestStatus.rejected:
        return 'Request not approved';
      default:
        return request.status.labelEn;
    }
  }

  String get _subtitle {
    switch (request.status) {
      case PatientRequestStatus.completed:
        return 'Please rate your provider so we can keep improving the panel.';
      case PatientRequestStatus.cancelled:
        return 'Your cancellation is on file. Any escrowed payment is refunded within 24 hrs.';
      case PatientRequestStatus.rejected:
        return 'Our admin team could not match this request. You can adjust the details and resubmit.';
      default:
        return '';
    }
  }

  IconData get _icon {
    switch (request.status) {
      case PatientRequestStatus.completed:
        return Icons.check_circle_outline;
      case PatientRequestStatus.cancelled:
        return Icons.cancel_outlined;
      case PatientRequestStatus.rejected:
        return Icons.report_gmailerrorred_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final isCompleted = request.status == PatientRequestStatus.completed;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: [
        Icon(_icon, color: hd.violet, size: 56),
        const SizedBox(height: 12),
        Text(
          _title,
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: hd.title),
        ),
        const SizedBox(height: 6),
        Text(
          _subtitle,
          textAlign: TextAlign.center,
          style: MtTextStyles.bodyMd.copyWith(color: hd.body),
        ),
        const SizedBox(height: 24),
        _SummaryCard(request: request),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => isCompleted
                ? ref.goToActivities(sub: PatientActivitiesTab.history)
                : ref.goToNewRequest(),
            style: ElevatedButton.styleFrom(
              backgroundColor: hd.violet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              isCompleted ? 'Rate your provider' : 'Start a new request',
              style: MtTextStyles.labelLg.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewView extends ConsumerWidget {
  final PatientActiveRequest request;

  const _ReviewView({required this.request});

  Future<void> _chatAdmin(BuildContext context) async {
    await launchWhatsAppSupport(
      context,
      message: 'Hi Taafi admin, I have a question about request ${request.id}.',
      fallbackMessage: 'Could not open WhatsApp. Reach admin at '
          '${SupportConfig.whatsappNumberDisplay}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _HeroSection(status: request.status),
        const SizedBox(height: 20),
        _StatusCard(request: request),
        const SizedBox(height: 16),
        _SummaryCard(request: request),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _OutlinedAction(
                icon: Icons.chat_bubble_outline,
                label: 'Chat admin',
                onTap: () => _chatAdmin(context),
              ),
            ),
            // Self-cancel is only offered BEFORE a coordinator claims the
            // dispatch — i.e. while the request is still `submitted`/`approved`
            // (the same states the backend `POST /patient/requests/:id/cancel`
            // guard permits). Once it moves into active processing (`assigned`
            // and beyond) only an admin can cancel, so the button disappears.
            if (_patientCancellable) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _OutlinedAction(
                  icon: Icons.close,
                  label: 'Cancel request',
                  onTap: () => _confirmCancel(context, ref, request.id),
                  destructive: true,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// True only for the pre-assignment states the patient may still cancel.
  /// Uses the exact backend wire status ([PatientActiveRequest.rawStatus]) so
  /// the UI matches the server-side guard precisely. (`awaiting_deposit` is
  /// also cancellable, but it never renders here — it gets the dedicated
  /// deposit surface in [_BookingPhaseView], which carries its own button.)
  bool get _patientCancellable =>
      const {'submitted', 'approved'}.contains(request.rawStatus);
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _HeroSection extends StatelessWidget {
  final PatientRequestStatus status;

  const _HeroSection({required this.status});

  ({String en, String bn, String hint, IconData icon}) _copyFor(
      PatientRequestStatus s) {
    switch (s) {
      case PatientRequestStatus.accepted:
        return (
          en: 'Doctor assigned',
          bn: 'ডাক্তার নির্ধারিত হয়েছে',
          hint:
              'A qualified doctor has accepted your request. Waiting for the doctor to confirm.',
          icon: Icons.verified_user_outlined,
        );
      case PatientRequestStatus.pendingReview:
      default:
        return (
          en: 'Request under review',
          bn: 'আপনার আবেদন পর্যালোচনায় রয়েছে',
          hint:
              'Our medical admin is reviewing your request\nand matching you with a qualified doctor.',
          icon: Icons.schedule,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final copy = _copyFor(status);
    return Column(
      children: [
        SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: hd.surfaceHi,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: hd.violet.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: hd.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: hd.violet, width: 1.5),
                ),
                child: Icon(copy.icon, color: hd.violet, size: 24),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          copy.en,
          style: MtTextStyles.h2.copyWith(color: hd.title),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          copy.hint,
          style: MtTextStyles.bodyMd.copyWith(color: hd.body),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          copy.bn,
          style: MtTextStyles.bodySm.copyWith(
            color: hd.violet,
            fontFamily: 'Kalpurush',
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final PatientActiveRequest request;

  const _StatusCard({required this.request});

  /// Computes the lifecycle steps and their per-status state given the
  /// request's current `PatientRequestStatus`. Timestamps come from the
  /// request fields when available, otherwise we fall back to the status
  /// labels ("Waiting", "Now"). Pure function — easy to test in isolation.
  List<_TimelineStep> _stepsFor(PatientActiveRequest r) {
    final now = DateTime.now();
    final timeFmt = DateFormat('h:mm a');

    final reachedAccepted = r.status.index >= PatientRequestStatus.accepted.index;
    final reachedEnRoute = r.status.index >= PatientRequestStatus.enRoute.index;
    final reachedArrived = r.status.index >= PatientRequestStatus.arrived.index;
    // PatientRequestStatus enum ordinals: pendingReview=0, accepted=1,
    // enRoute=2, arrived=3, inService=4. Indices are stable because the
    // enum order is the lifecycle order.

    _StepState submittedState = _StepState.done;
    _StepState reviewState;
    if (r.status == PatientRequestStatus.pendingReview) {
      reviewState = _StepState.active;
    } else if (reachedAccepted) {
      reviewState = _StepState.done;
    } else {
      reviewState = _StepState.pending;
    }

    _StepState assignedState;
    if (r.status == PatientRequestStatus.accepted) {
      assignedState = _StepState.active;
    } else if (reachedEnRoute) {
      assignedState = _StepState.done;
    } else {
      assignedState = _StepState.pending;
    }

    _StepState confirmState;
    if (r.status == PatientRequestStatus.enRoute) {
      confirmState = _StepState.active;
    } else if (reachedArrived) {
      confirmState = _StepState.done;
    } else {
      confirmState = _StepState.pending;
    }

    final onTheWayState =
        reachedEnRoute ? _StepState.done : _StepState.pending;

    String reviewSubtitle;
    if (reviewState == _StepState.active) {
      reviewSubtitle = r.reviewEtaMinutes != null
          ? 'Now · ~${r.reviewEtaMinutes} min ETA'
          : 'Now';
    } else if (reviewState == _StepState.done) {
      reviewSubtitle = r.acceptedAt != null
          ? timeFmt.format(r.acceptedAt ?? now)
          : 'Completed';
    } else {
      reviewSubtitle = 'Waiting';
    }

    String assignedSubtitle;
    if (assignedState == _StepState.active && r.providerName != null) {
      assignedSubtitle = r.providerName ?? 'Doctor matched';
    } else if (assignedState == _StepState.active) {
      assignedSubtitle = 'Matching doctors…';
    } else if (assignedState == _StepState.done) {
      assignedSubtitle = r.providerName ?? 'Doctor matched';
    } else {
      assignedSubtitle = 'Waiting';
    }

    return [
      _TimelineStep(
        label: 'Request submitted',
        subtitle: r.requestedAt != null
            ? timeFmt.format(r.requestedAt ?? now)
            : 'Submitted',
        state: submittedState,
      ),
      _TimelineStep(
        label: 'Admin reviewing',
        subtitle: reviewSubtitle,
        state: reviewState,
      ),
      _TimelineStep(
        label: 'Doctor assigned',
        subtitle: assignedSubtitle,
        state: assignedState,
      ),
      _TimelineStep(
        label: 'Doctor confirms',
        subtitle: confirmState == _StepState.active
            ? 'Confirming visit details'
            : confirmState == _StepState.done
                ? 'Confirmed'
                : 'Waiting',
        state: confirmState,
      ),
      _TimelineStep(
        label: 'On the way',
        subtitle:
            onTheWayState == _StepState.done ? 'En route' : 'Waiting',
        state: onTheWayState,
      ),
    ];
  }

  ServiceStatus _badgeStatus(PatientRequestStatus s) {
    switch (s) {
      case PatientRequestStatus.pendingReview:
        return ServiceStatus.pendingReview;
      case PatientRequestStatus.accepted:
      case PatientRequestStatus.enRoute:
        return ServiceStatus.enroute;
      case PatientRequestStatus.arrived:
        return ServiceStatus.arrived;
      case PatientRequestStatus.inService:
        return ServiceStatus.inService;
      case PatientRequestStatus.completed:
        return ServiceStatus.completed;
      case PatientRequestStatus.rejected:
      case PatientRequestStatus.cancelled:
        return ServiceStatus.pendingReview;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final steps = _stepsFor(request);
    return Container(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hd.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'REQUEST #${request.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.sectionLabel.copyWith(
                      color: hd.muted,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  status: _badgeStatus(request.status),
                  label: request.status.labelEn.toUpperCase(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: hd.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                for (int i = 0; i < steps.length; i++)
                  _StepRow(
                    step: steps[i],
                    isLast: i == steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, active, pending }

class _TimelineStep {
  final String label;
  final String subtitle;
  final _StepState state;
  const _TimelineStep({
    required this.label,
    required this.subtitle,
    required this.state,
  });
}

class _StepRow extends StatelessWidget {
  final _TimelineStep step;
  final bool isLast;

  const _StepRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final isDone = step.state == _StepState.done;
    final isActive = step.state == _StepState.active;
    final isPending = step.state == _StepState.pending;
    final filled = isDone || isActive;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? hd.violet : Colors.transparent,
                  border: filled
                      ? null
                      : Border.all(color: hd.muted, width: 1.5),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : isActive
                        ? const _PulseDot()
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? hd.violet : hd.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: MtTextStyles.labelLg.copyWith(
                      color: isPending ? hd.muted : hd.title,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.subtitle,
                    style: MtTextStyles.bodySm.copyWith(
                      color: isActive ? hd.violet : hd.muted,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny pulsing dot rendered inside the "active" timeline ring so the patient
/// sees a sign of life even when nothing else has changed yet.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PatientActiveRequest request;

  const _SummaryCard({required this.request});

  String _scheduleLabel() {
    final scheduledAt = request.scheduledAt;
    if (scheduledAt == null) return 'As soon as possible';
    return DateFormat('EEE d MMM · h:mm a').format(scheduledAt);
  }

  String _serviceLabel() {
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
      ('Service', _serviceLabel()),
      ('Location', request.locationLabel),
      ('Schedule', _scheduleLabel()),
      if (request.offer != null) ('Your offer', _money(request.offer ?? 0)),
      if (request.providerName != null)
        ('Provider', request.providerName ?? '—'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      rows[i].$1,
                      style: MtTextStyles.bodyMd.copyWith(
                        color: hd.muted,
                      ),
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
              Divider(
                  height: 1,
                  color: hd.border,
                  indent: 16,
                  endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _OutlinedAction({
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
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Dialogs
// ============================================================================

class _CancelDialogResult {
  final bool confirmed;
  final String? reason;
  const _CancelDialogResult({required this.confirmed, this.reason});
}

/// Confirmation dialog with an optional cancellation reason. Pre-fills a few
/// common reasons as quick-select chips while still allowing free-text.
class _CancelConfirmDialog extends StatefulWidget {
  const _CancelConfirmDialog();

  @override
  State<_CancelConfirmDialog> createState() => _CancelConfirmDialogState();
}

class _CancelConfirmDialogState extends State<_CancelConfirmDialog> {
  static const _quickReasons = [
    'Booked by mistake',
    'Patient feels better',
    'Found care elsewhere',
    'Schedule conflict',
  ];

  String? _selected;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  String? _finalReason() {
    if (_otherCtrl.text.trim().isNotEmpty) return _otherCtrl.text.trim();
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Cancel request?', style: MtTextStyles.h3),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You'll lose your place in the queue. Any escrowed payment is refunded within 24 hrs.",
              style: MtTextStyles.bodyMd.copyWith(color: hd.body),
            ),
            const SizedBox(height: 14),
            Text(
              'WHY ARE YOU CANCELLING?',
              style: MtTextStyles.sectionLabel.copyWith(
                color: hd.muted,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in _quickReasons)
                  ChoiceChip(
                    label: Text(reason, style: MtTextStyles.labelSm),
                    selected: _selected == reason,
                    onSelected: (_) {
                      setState(() {
                        _selected = _selected == reason ? null : reason;
                      });
                    },
                    selectedColor: hd.violet.withValues(alpha: 0.14),
                    labelStyle: MtTextStyles.labelSm.copyWith(
                      color: _selected == reason
                          ? hd.violetDeep
                          : hd.body,
                    ),
                    side: BorderSide(
                      color: _selected == reason
                          ? hd.violet
                          : hd.border,
                    ),
                    backgroundColor: hd.surface,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otherCtrl,
              maxLines: 2,
              style: MtTextStyles.bodyMd,
              decoration: InputDecoration(
                hintText: 'Other (optional)',
                hintStyle:
                    MtTextStyles.bodySm.copyWith(color: hd.muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: hd.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: hd.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: hd.violet, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const _CancelDialogResult(confirmed: false),
          ),
          style: TextButton.styleFrom(foregroundColor: hd.body),
          child: Text('Keep request', style: MtTextStyles.labelMd),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _CancelDialogResult(
              confirmed: true,
              reason: _finalReason(),
            ),
          ),
          style: TextButton.styleFrom(foregroundColor: hd.danger),
          child: Text('Cancel request', style: MtTextStyles.labelMd),
        ),
      ],
    );
  }
}
