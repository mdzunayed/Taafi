import 'booking_milestone.dart';
import 'care_request_status.dart';
import 'patient_active_request.dart';

/// The six steps the patient sees on the unified **Active Care** tracker.
///
/// Deliberately NOT the same list as [BookingMilestone]. The server's six
/// milestones describe the *dispatch* lifecycle and fold the whole two-phase
/// money gate into a single `REQUESTED` step — see
/// `backend/src/utils/bookingMilestones.js`, where `deposit_required` stays on
/// step 1 because nothing is confirmed until the money lands. That is right
/// for dispatch and wrong for the patient: "you placed a free request" and "we
/// called you and set your fee" are two different things that happen to them,
/// and only the second one asks for money.
///
/// So the tracker regroups the same server facts into six legible rows.
/// Progress and timestamps still come from the server — [ActiveCareTimeline]
/// reads [PatientActiveRequest.milestone], [PatientActiveRequest.depositStatus]
/// and [PatientActiveRequest.resolvedTimeline] and only decides which row each
/// fact belongs to. Nothing here advances a step the backend has not reached.
enum ActiveCareStep {
  /// Placed, free of charge. Current through the whole of Phase 1.
  submitted,

  /// The review call happened and the admin committed the fee + deposit. The
  /// one step in the lifecycle that asks the patient for money.
  feeSet,

  /// Deposit cleared; the care team is being matched, then named.
  teamAssigned,

  /// The dispatched provider is travelling to the patient's address.
  enRoute,

  /// The visit itself.
  inService,

  /// Delivered, and the balance reconciled. Only once BOTH are true does the
  /// booking stop being active care and belong to History.
  settled,
}

extension ActiveCareStepX on ActiveCareStep {
  static const int totalSteps = 6;

  /// 1-based position, for "Step 3 of 6".
  int get stepNumber => index + 1;

  /// The server milestone whose `milestone_timeline` entry stamps this row.
  ///
  /// Several rows share the ordering of a milestone but not its identity —
  /// [ActiveCareStep.feeSet] completes when the deposit clears, which the
  /// server records against `CONFIRMED` (`deposit_paid_at`).
  BookingMilestone get stampMilestone {
    switch (this) {
      case ActiveCareStep.submitted:
        return BookingMilestone.requested;
      case ActiveCareStep.feeSet:
        return BookingMilestone.confirmed;
      case ActiveCareStep.teamAssigned:
        return BookingMilestone.scheduled;
      case ActiveCareStep.enRoute:
        return BookingMilestone.enRoute;
      case ActiveCareStep.inService:
        return BookingMilestone.inService;
      case ActiveCareStep.settled:
        return BookingMilestone.completed;
    }
  }
}

/// Pure view model behind the Active Care stepper.
///
/// Every method is a function of the request alone, so the step logic is
/// testable without pumping a widget — which matters because this is where a
/// wrong answer either hides a payment the patient owes or claims a visit is
/// booked when it is waiting on them.
class ActiveCareTimeline {
  final PatientActiveRequest request;

  const ActiveCareTimeline(this.request);

  bool get isCancelled => request.milestone == BookingMilestone.cancelled;

  /// Where the booking sits right now. For a cancelled booking this reports
  /// the furthest row it genuinely reached, so the rail still shows how far
  /// the visit got before it stopped.
  ActiveCareStep get currentStep {
    if (isCancelled) {
      ActiveCareStep reached = ActiveCareStep.submitted;
      for (final step in ActiveCareStep.values) {
        if (stateOf(step) == MilestoneStepState.done) reached = step;
      }
      return reached;
    }
    for (final step in ActiveCareStep.values) {
      if (stateOf(step) == MilestoneStepState.current) return step;
    }
    return ActiveCareStep.settled;
  }

  MilestoneStepState stateOf(ActiveCareStep step) {
    // A cancelled booking has no "current" row: the steps it actually cleared
    // stay done (proved by a server timestamp) and the rest go dim. Inferring
    // progress from the last known milestone would credit the booking with
    // steps it never took.
    if (isCancelled) {
      if (step == ActiveCareStep.submitted) return MilestoneStepState.done;
      return _stampFromServer(step) != null
          ? MilestoneStepState.done
          : MilestoneStepState.upcoming;
    }

    final m = request.milestone;
    final phaseOne = m == BookingMilestone.requested;

    switch (step) {
      case ActiveCareStep.submitted:
        // Current only while the care team still owes the patient the review
        // call — the one stretch where nothing is owed and nothing is due.
        return phaseOne && request.isAwaitingReviewCall
            ? MilestoneStepState.current
            : MilestoneStepState.done;

      case ActiveCareStep.feeSet:
        if (phaseOne && request.isAwaitingReviewCall) {
          return MilestoneStepState.upcoming;
        }
        // Gate on the MONEY, not the lifecycle status: a booking whose status
        // ran ahead of its deposit (admin-advanced row, declined gateway
        // attempt, legacy document) still owes it, and this row is where that
        // is said out loud.
        if (request.needsDeposit) return MilestoneStepState.current;
        return MilestoneStepState.done;

      case ActiveCareStep.teamAssigned:
        if (request.needsDeposit) return MilestoneStepState.upcoming;
        // Spans "deposit cleared, matching" through "provider named": the
        // inline card tells the two apart, and to the patient they are one
        // wait.
        if (phaseOne ||
            m == BookingMilestone.confirmed ||
            m == BookingMilestone.scheduled) {
          return MilestoneStepState.current;
        }
        return MilestoneStepState.done;

      case ActiveCareStep.enRoute:
        if (m == BookingMilestone.enRoute) return MilestoneStepState.current;
        return m.step > BookingMilestone.enRoute.step
            ? MilestoneStepState.done
            : MilestoneStepState.upcoming;

      case ActiveCareStep.inService:
        if (m == BookingMilestone.inService) return MilestoneStepState.current;
        return m.step > BookingMilestone.inService.step
            ? MilestoneStepState.done
            : MilestoneStepState.upcoming;

      case ActiveCareStep.settled:
        if (m != BookingMilestone.completed) return MilestoneStepState.upcoming;
        // The visit being over is not the end of the booking — the balance and
        // the prescription release still hang off it.
        return isSettledClosed
            ? MilestoneStepState.done
            : MilestoneStepState.current;
    }
  }

  /// The server's timestamp for [step], or null when it has not been reached
  /// (or the payload predates milestone history). Never synthesised.
  DateTime? stampOf(ActiveCareStep step) {
    if (stateOf(step) == MilestoneStepState.upcoming) return null;
    return _stampFromServer(step);
  }

  DateTime? _stampFromServer(ActiveCareStep step) {
    for (final e in request.resolvedTimeline) {
      if (e.milestone == step.stampMilestone) return e.timestamp;
    }
    return null;
  }

  /// True once the visit is delivered AND the money is fully reconciled — the
  /// point where the booking stops being active care and belongs to History.
  ///
  /// Completion alone is not enough: `service_completed_awaiting_final_payment`
  /// also reports milestone `COMPLETED`, and that is exactly the state where
  /// the Pay Balance CTA and the prescription gate live. Handing it to History
  /// there would strand the one action the patient still has to take.
  bool get isSettledClosed {
    if (request.milestone != BookingMilestone.completed) return false;
    // The backend saying "payment outstanding" outranks any arithmetic: an
    // unpriced booking has a zero balance without having been paid for.
    if (request.rawStatus ==
        CareRequestStatus.serviceCompletedAwaitingFinalPayment) {
      return false;
    }
    if (request.isAwaitingPaymentVerification) return false;
    return request.outstandingBalance <= 0;
  }

  /// Whether this booking still belongs on the Active Care tab at all.
  /// Cancelled bookings stay (the tab is where the patient learns why);
  /// settled ones hand off to History.
  bool get belongsInActiveCare => !isSettledClosed;
}
