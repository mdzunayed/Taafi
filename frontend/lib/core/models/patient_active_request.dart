import 'package:equatable/equatable.dart';

import 'assigned_doctor.dart';
import 'assigned_nurse.dart';
import 'assigned_provider.dart';
import 'booking_milestone.dart';
import 'deposit_status.dart';
import 'patient_request_status.dart';
import 'platform_pricing.dart' show resolveDepositRequired;
import 'provider_type.dart';

/// The patient's currently-open service request. Drives both the Home active
/// card and the Under Review / Service Status tabs.
///
/// Optional fields (`requestedAt`, `acceptedAt`, `offer`, `durationHours`,
/// `reviewEtaMinutes`) are populated on submit and as the backend updates the
/// request lifecycle. They're optional so older payloads keep parsing.
class PatientActiveRequest extends Equatable {
  final String id;
  final String serviceTitleEn;
  final String serviceTitleBn;
  final PatientRequestStatus status;
  final String? providerName;
  final String? providerInitials;
  final String? providerAvatarUrl;
  final String? providerSpecialization;

  /// Populated doctor profile attached by the backend once the admin
  /// completes the assignment. `null` while the request is still pending.
  /// Drives the assigned-provider card on the Service Status tab and
  /// the read-only `view_assigned_doctor_screen.dart`.
  final AssignedDoctor? assignedDoctor;

  /// Populated nurse profile attached by the backend when the admin
  /// adds a nursing-care provider to the visit. `null` for doctor-only
  /// visits. Surfaces a second row on YOUR CARE TIMELINE and a
  /// separate avatar in the patient's active-care card.
  final AssignedNurse? assignedNurse;

  /// When the patient submitted the request.
  final DateTime? requestedAt;

  /// When the admin matched the doctor (or `null` if still pending).
  final DateTime? acceptedAt;

  /// When the visit is scheduled for (or `null` for ASAP).
  final DateTime? scheduledAt;

  final String locationLabel;
  final int? etaMinutes;
  final int? reviewEtaMinutes;
  final int? durationHours;
  final int? offer;

  /// Raw `care_requests.status` wire string (e.g. `awaiting_deposit`,
  /// `deposit_paid_admin_reviewing`, `amount_assigned_awaiting_final_payment`).
  /// Kept alongside the coarse [status] enum (which collapses the two-phase
  /// booking states into `pendingReview`) so the two-phase booking surface
  /// can branch precisely. Empty for legacy payloads.
  final String rawStatus;

  /// Whether the confirmation deposit has actually been settled.
  /// Server-derived; the ONLY thing that may unlock "deposit confirmed" copy.
  final DepositStatus depositStatus;

  /// Two-phase confirmation deposit + dynamic-invoice fields. Populated once
  /// the deposit is paid / the admin prices the booking; null/0 before then.
  final double depositAmount;

  /// THE deposit figure to display for this booking, in any state: what was
  /// paid if it is paid, what the admin set if it is not — and `null` when no
  /// deposit has been set at all, which is the whole of Phase 1.
  ///
  /// Distinct from [depositAmount], which is 0 until the gateway settles — so
  /// every "Pay ৳X" / "Deposit ৳X pending" string must read *this*. Also
  /// distinct from the platform's default deposit: the amount is a per-case
  /// decision made on the review call, so the server resolves it per booking
  /// and the client never recomputes or substitutes it.
  final double? depositRequiredAmount;

  /// The total service fee the admin committed on the review call, or null
  /// before it. Spec name: `total_service_fee`.
  final double? finalServiceFee;
  final double? adjustedDiscount;

  /// Phase 4 verification state of the remaining balance:
  /// `PENDING` / `PENDING_ADMIN_VERIFICATION` / `VERIFIED`. Says whether a
  /// human has confirmed the money, which [balanceSettled] does not.
  final String remainingPaymentStatus;

  /// Whether this visit's prescription has been released — the server-held
  /// latch that flips only alongside a VERIFIED balance.
  final bool prescriptionUnlocked;

  /// The patient's upfront choice of how they'll settle the outstanding
  /// balance: `'CASH_ON_SERVICE'` (pay the provider in cash at the door) or
  /// `'DIGITAL'`. `null` until the patient picks one on the Tracking screen.
  final String? paymentPreference;

  /// Whether the outstanding balance itself has been settled — server-derived
  /// (`payment_status`), so it is true whether the money arrived through the
  /// gateway or as cash the provider confirmed.
  ///
  /// Distinct from [paymentPreference], which is only an intention. This is
  /// what the ledger's "Fully Settled" state branches on: a patient who
  /// pre-committed to cash and then paid online must see the green banner,
  /// not a cash-at-the-door instruction.
  final bool balanceSettled;

  /// Patient's phone (surfaced so the admin review portal can call/text).
  final String? patientPhone;

  // --- Milestone tracker (Foodpanda-style ONGOING CARE card) ---------------
  // All server-derived from the canonical status; see
  // `backend/src/utils/bookingMilestones.js`.

  /// Current patient-facing step of the six-step lifecycle.
  final BookingMilestone milestone;

  /// Server-rendered headline for [milestone] — folds the scheduled time into
  /// the SCHEDULED step ("Provider Assigned — Scheduled for Today, 04:00 PM").
  final String milestoneLabel;

  /// The appointment window the ADMIN committed to. Distinct from
  /// [scheduledAt] (`preferred_time`), which is what the patient asked for.
  final DateTime? scheduledTime;

  /// Server-formatted, Dhaka-local rendering of [scheduledTime] — e.g.
  /// "Today, 04:00 PM". Null until an admin sets a time.
  final String? scheduledTimeLabel;

  /// Display name of the attending provider, when the admin set one.
  final String? assignedProviderName;

  /// Who is attending this booking. Server-resolved (the dispatched
  /// provider's own role wins over the booked service's), and the source of
  /// every role-dependent string on the tracker: the four middle timeline
  /// steps, the provider card's badge and registration label, and the
  /// pre-arrival preparation tip.
  final ProviderType providerType;

  /// The provider's contact card, once one is dispatched. Null before
  /// assignment — and the reason the tracking screen can offer a direct call /
  /// WhatsApp without the patient going through the support desk.
  final AssignedProvider? assignedProvider;

  /// The six-step timeline with per-step timestamps, for the tracking screen.
  final List<MilestoneTimelineEntry> timeline;

  final DateTime updatedAt;

  const PatientActiveRequest({
    required this.id,
    required this.serviceTitleEn,
    required this.serviceTitleBn,
    required this.status,
    required this.locationLabel,
    required this.updatedAt,
    this.providerName,
    this.providerInitials,
    this.providerAvatarUrl,
    this.providerSpecialization,
    this.assignedDoctor,
    this.assignedNurse,
    this.requestedAt,
    this.acceptedAt,
    this.scheduledAt,
    this.etaMinutes,
    this.reviewEtaMinutes,
    this.durationHours,
    this.offer,
    this.rawStatus = '',
    this.depositStatus = DepositStatus.notRequired,
    this.depositAmount = 0,
    this.depositRequiredAmount,
    this.finalServiceFee,
    this.adjustedDiscount,
    this.paymentPreference,
    this.balanceSettled = false,
    this.remainingPaymentStatus = 'PENDING',
    this.prescriptionUnlocked = false,
    this.patientPhone,
    this.milestone = BookingMilestone.requested,
    this.milestoneLabel = '',
    this.scheduledTime,
    this.scheduledTimeLabel,
    this.assignedProviderName,
    this.providerType = ProviderTypeX.fallback,
    this.assignedProvider,
    this.timeline = const [],
  });

  /// Headline for the tracker card — the server label when present, else the
  /// milestone's own role-aware copy so the card is never blank and never
  /// falls back to generic "Provider" wording.
  String get milestoneHeadline => milestoneLabel.isNotEmpty
      ? milestoneLabel
      : milestone.labelFor(providerType);

  /// The six-step timeline, falling back to a locally-derived one if the
  /// backend didn't ship `milestone_timeline`.
  List<MilestoneTimelineEntry> get resolvedTimeline => timeline.isNotEmpty
      ? timeline
      : MilestoneTimelineEntry.derive(milestone, providerType: providerType);

  /// How to name the attending provider in the app's own copy — "Call Nurse",
  /// "Your Doctor". Follows whoever is actually dispatched.
  String get providerRoleLabel =>
      (assignedProvider?.type ?? providerType).roleLabel;

  /// True while a dispatched provider is either on their way or already
  /// working — the window where the provider contact card and the pre-arrival
  /// preparation tip are both relevant.
  bool get isProviderActive =>
      milestone == BookingMilestone.scheduled ||
      milestone == BookingMilestone.enRoute ||
      milestone == BookingMilestone.inService;

  /// The pre-arrival guidance to show, or null outside the window where the
  /// patient can still act on it (EN_ROUTE / IN_SERVICE).
  String? get preparationTip {
    if (milestone != BookingMilestone.enRoute &&
        milestone != BookingMilestone.inService) {
      return null;
    }
    return (assignedProvider?.type ?? providerType).preparationTip;
  }

  /// Best available provider name for the card: the admin's explicit override
  /// first, then the assigned doctor/nurse records.
  String? get displayProviderName {
    final explicit = assignedProviderName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final legacy = providerName?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return assignedNurse?.fullName;
  }

  /// True once the patient has committed to paying in cash at the door AND
  /// that is still how the money will arrive. A settled balance overrides the
  /// stated preference — nothing is left to hand over.
  bool get isCashChosen =>
      paymentPreference == 'CASH_ON_SERVICE' && !balanceSettled;

  /// PHASE 1 — placed free, waiting on the care team's review call. Nothing is
  /// owed; no payment CTA may render.
  bool get isAwaitingReviewCall => depositStatus.isAwaitingReview;

  /// PHASE 2 — the admin set an amount and the patient owes it. Gates the
  /// "Pay ৳X Deposit to Confirm Booking" card.
  bool get needsDeposit => depositStatus.isOutstanding;

  /// The deposit to name in copy, or 0 when none has been set. Gate on
  /// [needsDeposit] before rendering it as a price.
  double get depositDue => depositRequiredAmount ?? 0;

  /// PHASE 4, CHANNEL B — paid online, not yet reconciled by an admin. Why a
  /// paid-for prescription can still be locked.
  bool get isAwaitingPaymentVerification =>
      remainingPaymentStatus == 'PENDING_ADMIN_VERIFICATION';

  /// Outstanding balance the patient still owes after the admin prices the
  /// booking: base fee − deposit − discount. Never negative, and always 0 once
  /// the balance has been settled through either channel.
  double get outstandingBalance {
    if (balanceSettled) return 0;
    final fee = finalServiceFee ?? 0;
    final discount = adjustedDiscount ?? 0;
    final owed = fee - depositAmount - discount;
    return owed < 0 ? 0 : owed;
  }

  /// Everything is priced and paid — the spec's STATE C. What the clinician
  /// sees as "৳0 to collect".
  bool get isFullySettled => balanceSettled && (finalServiceFee ?? 0) > 0;

  /// Total the patient has paid once fully settled, for the receipt line.
  double get totalPaid => (finalServiceFee ?? 0) - (adjustedDiscount ?? 0);

  PatientActiveRequest copyWith({
    PatientRequestStatus? status,
    DateTime? updatedAt,
    DateTime? acceptedAt,
    int? etaMinutes,
    int? reviewEtaMinutes,
    AssignedDoctor? assignedDoctor,
    AssignedNurse? assignedNurse,
    String? paymentPreference,
    bool? balanceSettled,
    String? remainingPaymentStatus,
    bool? prescriptionUnlocked,
    BookingMilestone? milestone,
    String? milestoneLabel,
    DateTime? scheduledTime,
    String? scheduledTimeLabel,
    String? assignedProviderName,
    ProviderType? providerType,
    AssignedProvider? assignedProvider,
    List<MilestoneTimelineEntry>? timeline,
  }) {
    return PatientActiveRequest(
      id: id,
      serviceTitleEn: serviceTitleEn,
      serviceTitleBn: serviceTitleBn,
      status: status ?? this.status,
      locationLabel: locationLabel,
      updatedAt: updatedAt ?? this.updatedAt,
      providerName: providerName,
      providerInitials: providerInitials,
      providerAvatarUrl: providerAvatarUrl,
      providerSpecialization: providerSpecialization,
      assignedDoctor: assignedDoctor ?? this.assignedDoctor,
      assignedNurse: assignedNurse ?? this.assignedNurse,
      requestedAt: requestedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      scheduledAt: scheduledAt,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      reviewEtaMinutes: reviewEtaMinutes ?? this.reviewEtaMinutes,
      durationHours: durationHours,
      offer: offer,
      rawStatus: rawStatus,
      depositStatus: depositStatus,
      depositAmount: depositAmount,
      depositRequiredAmount: depositRequiredAmount,
      finalServiceFee: finalServiceFee,
      adjustedDiscount: adjustedDiscount,
      paymentPreference: paymentPreference ?? this.paymentPreference,
      balanceSettled: balanceSettled ?? this.balanceSettled,
      remainingPaymentStatus:
          remainingPaymentStatus ?? this.remainingPaymentStatus,
      prescriptionUnlocked: prescriptionUnlocked ?? this.prescriptionUnlocked,
      patientPhone: patientPhone,
      milestone: milestone ?? this.milestone,
      milestoneLabel: milestoneLabel ?? this.milestoneLabel,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      scheduledTimeLabel: scheduledTimeLabel ?? this.scheduledTimeLabel,
      assignedProviderName: assignedProviderName ?? this.assignedProviderName,
      providerType: providerType ?? this.providerType,
      assignedProvider: assignedProvider ?? this.assignedProvider,
      timeline: timeline ?? this.timeline,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serviceTitleEn,
        serviceTitleBn,
        status,
        providerName,
        providerInitials,
        providerAvatarUrl,
        providerSpecialization,
        assignedDoctor,
        assignedNurse,
        requestedAt,
        acceptedAt,
        scheduledAt,
        locationLabel,
        etaMinutes,
        reviewEtaMinutes,
        durationHours,
        offer,
        rawStatus,
        depositStatus,
        depositAmount,
        depositRequiredAmount,
        finalServiceFee,
        adjustedDiscount,
        paymentPreference,
        balanceSettled,
        remainingPaymentStatus,
        prescriptionUnlocked,
        patientPhone,
        milestone,
        milestoneLabel,
        scheduledTime,
        scheduledTimeLabel,
        assignedProviderName,
        providerType,
        assignedProvider,
        timeline,
        updatedAt,
      ];

  factory PatientActiveRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptional(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    final providerType =
        ProviderTypeX.fromWire(json['providerType']?.toString());

    return PatientActiveRequest(
      id: json['id']?.toString() ?? '',
      serviceTitleEn: json['serviceTitleEn']?.toString() ?? '',
      serviceTitleBn: json['serviceTitleBn']?.toString() ?? '',
      status: PatientRequestStatusX.fromWire(json['status']?.toString()),
      providerName: json['providerName']?.toString(),
      providerInitials: json['providerInitials']?.toString(),
      providerAvatarUrl: json['providerAvatarUrl']?.toString(),
      providerSpecialization: json['providerSpecialization']?.toString(),
      requestedAt: parseOptional(json['requestedAt']),
      acceptedAt: parseOptional(json['acceptedAt']),
      scheduledAt: parseOptional(json['scheduledAt']),
      locationLabel: json['locationLabel']?.toString() ?? '',
      etaMinutes: (json['etaMinutes'] as num?)?.toInt(),
      reviewEtaMinutes: (json['reviewEtaMinutes'] as num?)?.toInt(),
      durationHours: (json['durationHours'] as num?)?.toInt(),
      offer: (json['offer'] as num?)?.toInt(),
      rawStatus: json['rawStatus']?.toString() ?? '',
      depositStatus: DepositStatusX.fromWire(
        json['depositStatus']?.toString(),
        // Pre-`depositStatus` payload: infer from the money. A paid amount is
        // CONFIRMED; an amount that was set but not paid is PENDING; nothing
        // set at all is NOT_REQUIRED, which keeps the payment CTA off a
        // free Phase-1 request.
        fallback: ((json['depositAmount'] as num?)?.toDouble() ?? 0) > 0
            ? DepositStatus.confirmed
            : (((json['requiredDeposit'] ?? json['depositRequiredAmount'])
                            as num?)
                        ?.toDouble() ??
                    0) >
                    0
                ? DepositStatus.pending
                : DepositStatus.notRequired,
      ),
      depositAmount: (json['depositAmount'] as num?)?.toDouble() ?? 0,
      // Null when no deposit has been set — never substituted with a platform
      // default, which would put a price on a free request.
      depositRequiredAmount: resolveDepositRequired(
        json['requiredDeposit'] ?? json['depositRequiredAmount'],
        json['depositAmount'],
      ),
      finalServiceFee: (json['totalServiceFee'] as num?)?.toDouble() ??
          (json['finalServiceFee'] as num?)?.toDouble(),
      adjustedDiscount: (json['adjustedDiscount'] as num?)?.toDouble(),
      paymentPreference: json['paymentPreference']?.toString(),
      remainingPaymentStatus:
          json['remainingPaymentStatus']?.toString() ?? 'PENDING',
      prescriptionUnlocked: json['prescriptionUnlocked'] == true,
      // Server-derived posture first; fall back to the settlement stamps for
      // payloads that predate it, so a cached row degrades to "still owed"
      // rather than falsely claiming the booking is paid.
      balanceSettled: json['balanceSettled'] == true ||
          json['paymentStatus']?.toString().toUpperCase() == 'PAID' ||
          json['finalPaidAt'] != null,
      patientPhone: json['patientPhone']?.toString(),
      milestone: BookingMilestoneX.fromWire(json['milestone']?.toString()),
      milestoneLabel: json['milestoneLabel']?.toString() ?? '',
      scheduledTime: parseOptional(json['scheduledTime']),
      scheduledTimeLabel: json['scheduledTimeLabel']?.toString(),
      assignedProviderName: json['assignedProviderName']?.toString(),
      providerType: providerType,
      assignedProvider: AssignedProvider.fromJson(
        json['assignedProvider'],
        fallbackType: providerType,
      ),
      timeline: MilestoneTimelineEntry.listFrom(
        json['timeline'],
        current: BookingMilestoneX.fromWire(json['milestone']?.toString()),
        providerType: providerType,
      ),
      updatedAt: parseOptional(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serviceTitleEn': serviceTitleEn,
        'serviceTitleBn': serviceTitleBn,
        'status': status.toWire(),
        'providerName': providerName,
        'providerInitials': providerInitials,
        'providerAvatarUrl': providerAvatarUrl,
        'providerSpecialization': providerSpecialization,
        'requestedAt': requestedAt?.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'locationLabel': locationLabel,
        'etaMinutes': etaMinutes,
        'reviewEtaMinutes': reviewEtaMinutes,
        'durationHours': durationHours,
        'offer': offer,
        'rawStatus': rawStatus,
        'depositStatus': depositStatus.toWire(),
        'depositAmount': depositAmount,
        'depositRequiredAmount': depositRequiredAmount,
        'finalServiceFee': finalServiceFee,
        'adjustedDiscount': adjustedDiscount,
        'paymentPreference': paymentPreference,
        'balanceSettled': balanceSettled,
        'remainingPaymentStatus': remainingPaymentStatus,
        'prescriptionUnlocked': prescriptionUnlocked,
        'patientPhone': patientPhone,
        'milestone': milestone.toWire(),
        'milestoneLabel': milestoneLabel,
        'scheduledTime': scheduledTime?.toIso8601String(),
        'scheduledTimeLabel': scheduledTimeLabel,
        'assignedProviderName': assignedProviderName,
        'providerType': providerType.toWire(),
        'assignedProvider': assignedProvider?.toJson(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
