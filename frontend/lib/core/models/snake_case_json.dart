// Snake-case JSON translation layer for live MongoDB documents.
//
// MongoDB's `care_requests`, `providers`, and `accounts` collections use
// snake_case keys (`patient_id`, `care_type`, `duration_hours`,
// `offered_budget`, `location_text`, `status: "submitted"`). The Dart
// model classes were built for the original mock contract which uses
// camelCase. Rather than rewrite every `fromJson` factory (and risk
// breaking the still-shipping mock branches), this file is the additive
// translation layer: every real-backend read goes through one of the
// converters here.
//
// Design rules enforced throughout:
//   - Zero `!` operators. Every nullable read uses `?.toString()`,
//     `?? default`, `tryParse`, or `as Type?`.
//   - Accept BOTH `_id` (Mongo native) and `id` (flattened) as the id field.
//   - Snake-case input → camelCase Dart enums via the small helpers below.
//   - Pure functions, no IO, no Riverpod dependency — trivially testable.

import 'admin_models.dart';
import 'assigned_doctor.dart';
import 'assigned_nurse.dart';
import 'assigned_provider.dart';
import 'booking_milestone.dart';
import 'doctor_dashboard.dart';
import 'doctor_review.dart';
import 'patient_active_request.dart';
import 'patient_home_feed.dart';
import 'patient_request_status.dart';
import 'provider_type.dart';
import 'recent_provider.dart';
import 'service.dart';
import 'user.dart';

// ============================================================================
// Status / enum wire mappers
// ============================================================================

/// Maps MongoDB `care_requests.status` strings to the app's
/// [PatientRequestStatus] enum. The observed lifecycle is:
/// submitted → approved → assigned → enroute → arrived → in_service →
/// completed.
PatientRequestStatus parseRequestStatus(String? wire) {
  switch (wire?.toLowerCase()) {
    case 'submitted':
    case 'pending':
    case 'pending_review':
      return PatientRequestStatus.pendingReview;
    case 'approved':
    case 'assigned':
    case 'matched':
    case 'accepted':
      return PatientRequestStatus.accepted;
    case 'enroute':
    case 'en_route':
    case 'on_the_way':
      return PatientRequestStatus.enRoute;
    case 'arrived':
      return PatientRequestStatus.arrived;
    case 'in_service':
    case 'inservice':
    case 'in_progress':
      return PatientRequestStatus.inService;
    case 'completed':
      return PatientRequestStatus.completed;
    case 'rejected':
      return PatientRequestStatus.rejected;
    case 'cancelled':
    case 'canceled':
      return PatientRequestStatus.cancelled;
    default:
      return PatientRequestStatus.pendingReview;
  }
}

/// Maps Mongo wire status to the app's existing AdminCareRequest.status
/// vocabulary (`pending` / `approved` / `rejected` / etc.) without
/// touching the three call sites that hardcode `r.status == 'pending'`.
///
/// `"submitted"` is the friction point: Mongo writes it, but every
/// existing admin filter / count provider keys off `"pending"`. `assigned`
/// is a post-approval state, so it collapses into the admin "Approved"
/// bucket. Everything else passes through verbatim.
String normalizeAdminStatus(String wire) {
  switch (wire.toLowerCase()) {
    case 'submitted':
    case 'pending_review':
      return 'pending';
    case 'approved':
    case 'assigned':
    case 'matched':
      return 'approved';
    default:
      return wire;
  }
}

/// `care_type` is free-text in Mongo (e.g. "Post-surgery home care",
/// "Wound dressing follow-up"), not an enum token — so we match on
/// substrings rather than exact equality.
ServiceType parseServiceType(String? wire) {
  final t = (wire ?? '').toLowerCase();
  if (t.contains('wound') || t.contains('dressing')) {
    return ServiceType.woundDressing;
  }
  if (t.contains('vital') || t.contains('check')) {
    return ServiceType.vitalsCheck;
  }
  if (t.contains('elder') || t.contains('senior')) {
    return ServiceType.elderlyCare;
  }
  return ServiceType.postSurgery; // "Post-surgery home care" + default
}

UrgencyLevel parseUrgency(String? wire) {
  switch (wire?.toLowerCase()) {
    case 'low':
      return UrgencyLevel.low;
    case 'high':
      return UrgencyLevel.high;
    case 'critical':
      return UrgencyLevel.critical;
    case 'medium':
    default:
      return UrgencyLevel.medium;
  }
}

// ============================================================================
// Document → model converters
// ============================================================================

// Local helpers — kept as plain top-level functions so each converter
// reads as a flat list of field assignments. No reflection, no codegen.

String? _str(dynamic v) => v?.toString();
int? _int(dynamic v) => (v as num?)?.toInt();
double? _dbl(dynamic v) => (v as num?)?.toDouble();

/// Parse a date that may arrive as an ISO string OR as MongoDB canonical
/// extended JSON `{"$date": "..."}`. Returns null on absent/garbage input.
DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Map) {
    final inner = v[r'$date'];
    return inner == null ? null : DateTime.tryParse(inner.toString());
  }
  return DateTime.tryParse(v.toString());
}

/// Securely parse a monetary value that may arrive as a `num` (3500) OR a
/// `String` ("3500", "3,500", "৳3,500"). Strips any non-numeric/decimal
/// characters before parsing. Returns null on empty/garbage input.
double? _money(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final cleaned = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
  return cleaned.isEmpty ? null : double.tryParse(cleaned);
}

/// Derives a coarse "area" from a free-text `location_text` by taking the
/// last comma-separated segment (e.g. "House 42, Dhanmondi" → "Dhanmondi").
String _areaFromLocation(String location) {
  if (location.trim().isEmpty) return '';
  final parts = location.split(',');
  return parts.last.trim();
}

/// Resolve a document id from either a flattened `id`/`_id` string or
/// MongoDB canonical extended JSON `{"$oid": "507f…"}`. Falls back to ''.
String _idOf(Map<String, dynamic> j) {
  final raw = j['_id'] ?? j['id'];
  if (raw is Map) return (raw[r'$oid'] ?? '').toString();
  return raw?.toString() ?? '';
}

/// `care_requests` document → [AdminCareRequest].
///
/// Real Compass schema:
///   _id, patient_name, patient_account_id, patient_phone, care_type,
///   offered_budget (String|double), preferred_time, duration_hours,
///   condition_note, location_text, status, final_price, admin_note.
/// Fields absent from the observed schema (age/gender/lat/lng/area/
/// surgery_details/patient_history) default gracefully; `area` is derived
/// from `location_text` so the area filter still works.
AdminCareRequest adminCareRequestFromMongo(Map<String, dynamic> j) {
  final location = _str(j['location_text']) ?? '';
  return AdminCareRequest(
    id: _idOf(j),
    patientId: _str(j['patient_account_id']) ?? '',
    patientName: _str(j['patient_name']) ?? '',
    patientAge: _int(j['patient_age']) ?? 0,
    patientGender: _str(j['patient_gender']),
    serviceType: parseServiceType(_str(j['care_type'])),
    serviceName: _str(j['care_type']) ?? '', // free-text, display-ready
    location: location,
    area: _str(j['area']) ?? _areaFromLocation(location),
    latitude: _dbl(j['latitude']),
    longitude: _dbl(j['longitude']),
    durationHours: _int(j['duration_hours']) ?? 1,
    asap: j['preferred_time'] == null,
    scheduledTime: _date(j['preferred_time']),
    status: normalizeAdminStatus(_str(j['status']) ?? 'submitted'),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    urgencyLevel: parseUrgency(_str(j['urgency_level'])),
    surgeryDetails: _str(j['surgery_details']),
    patientHistory: _str(j['patient_history']),
    assignedDoctorId: _str(j['assigned_doctor_id']),
    assignedDoctorName: _str(j['assigned_doctor_name']),
    assignedHelperId: _str(j['assigned_helper_id']),
    assignedHelperName: _str(j['assigned_helper_name']),
    patientOffer: _money(j['offered_budget']) ?? 0,
    adjustedPrice: _money(j['final_price']), // final_price → adjustedPrice
    marketPriceMin: _money(j['market_price_min']),
    marketPriceMax: _money(j['market_price_max']),
    notes: _str(j['condition_note']), // patient's condition note
    phone: _str(j['patient_phone']),
    adminNote: _str(j['admin_note']),
  );
}

/// Canonical `care_requests.status` → patient-facing [BookingMilestone].
///
/// Mirrors `MILESTONE_BY_STATUS` in backend/src/utils/bookingMilestones.js.
/// Only used as a fallback: when the server ships an explicit `milestone` we
/// take it verbatim. Keeping the map here means a client talking to an older
/// backend still renders a correct step instead of pinning to step 1.
BookingMilestone _milestoneFromStatus(String? wire) {
  switch (wire?.toLowerCase()) {
    case 'awaiting_deposit':
    case 'submitted':
    case 'pending':
    case 'pending_review':
    case 'deposit_paid_admin_reviewing':
      return BookingMilestone.requested;
    case 'approved':
    case 'amount_assigned_awaiting_final_payment':
      return BookingMilestone.confirmed;
    case 'assigned':
    case 'matched':
    case 'accepted':
      return BookingMilestone.scheduled;
    case 'enroute':
    case 'en_route':
    case 'on_the_way':
    case 'arrived':
      return BookingMilestone.enRoute;
    case 'in_service':
    case 'inservice':
    case 'in_progress':
    case 'nurse_completed':
      return BookingMilestone.inService;
    case 'service_completed_awaiting_final_payment':
    case 'completed':
      return BookingMilestone.completed;
    case 'cancelled':
    case 'canceled':
    case 'rejected':
      return BookingMilestone.cancelled;
    default:
      return BookingMilestone.requested;
  }
}

/// Single `care_requests` document → [PatientActiveRequest] (patient's
/// own active card view).
///
/// The backend attaches a populated `doctor` block once the admin
/// completes the Assign Team step — we lift it into `assignedDoctor`
/// here so the UI doesn't need to know about the wire shape. Falls back
/// to the flat `assigned_doctor_name` legacy fields for older clients
/// that haven't redeployed yet.
PatientActiveRequest patientActiveFromMongo(Map<String, dynamic> j) {
  AssignedDoctor? doctor;
  final rawDoctor = j['doctor'];
  if (rawDoctor is Map) {
    final asMap = Map<String, dynamic>.from(rawDoctor);
    // Only build the object if the populate actually returned a real
    // record — an empty `{}` from a busted lookup shouldn't trick the
    // UI into showing the assigned-doctor card.
    final id = asMap['id']?.toString() ?? asMap['_id']?.toString() ?? '';
    final name =
        (asMap['full_name'] ?? asMap['fullName'] ?? '').toString();
    if (id.isNotEmpty || name.isNotEmpty) {
      doctor = AssignedDoctor.fromJson(asMap);
    }
  }

  AssignedNurse? nurse;
  final rawNurse = j['nurse'];
  if (rawNurse is Map) {
    final asMap = Map<String, dynamic>.from(rawNurse);
    final id = asMap['id']?.toString() ?? asMap['_id']?.toString() ?? '';
    final name = (asMap['full_name'] ?? asMap['fullName'] ?? '').toString();
    if (id.isNotEmpty || name.isNotEmpty) {
      nurse = AssignedNurse.fromJson(asMap);
    }
  }

  // Prefer the server's milestone; fall back to deriving one from the
  // canonical status so a backend that predates the tracker still yields a
  // correct step (rather than defaulting everything to step 1).
  final rawMilestone = _str(j['milestone']);
  final milestone = rawMilestone != null
      ? BookingMilestoneX.fromWire(rawMilestone)
      : _milestoneFromStatus(_str(j['status']));

  // Who is attending, as resolved by the server (`resolved_provider_type`
  // accounts for a booking whose dispatched provider outranks the booked
  // service's role). `provider_type` is the raw stored column, read as the
  // fallback for an API that predates the resolver; the doctor/nurse populate
  // blocks settle it for a legacy payload that carries neither.
  final providerType = ProviderTypeX.tryFromWire(_str(j['resolved_provider_type'])) ??
      ProviderTypeX.tryFromWire(_str(j['provider_type'])) ??
      (doctor != null
          ? ProviderType.doctor
          : nurse != null
              ? ProviderType.nurse
              : ProviderTypeX.fallback);

  return PatientActiveRequest(
    id: _idOf(j),
    serviceTitleEn: _str(j['care_type']) ?? '',
    serviceTitleBn: _str(j['service_title_bn']) ?? '',
    status: parseRequestStatus(_str(j['status'])),
    providerName: _str(j['assigned_doctor_name']) ?? doctor?.fullName,
    providerSpecialization:
        _str(j['assigned_doctor_specialization']) ?? doctor?.specialty,
    providerInitials: _str(j['assigned_doctor_initials']) ?? doctor?.initials,
    providerAvatarUrl:
        _str(j['assigned_doctor_avatar_url']) ?? doctor?.profilePicture,
    assignedDoctor: doctor,
    assignedNurse: nurse,
    locationLabel: _str(j['location_text']) ?? '',
    requestedAt: _date(j['created_at']),
    acceptedAt: _date(j['accepted_at']),
    scheduledAt: _date(j['preferred_time']),
    etaMinutes: _int(j['eta_minutes']),
    reviewEtaMinutes: _int(j['review_eta_minutes']),
    durationHours: _int(j['duration_hours']),
    offer: _money(j['offered_budget'])?.round(),
    rawStatus: _str(j['status']) ?? '',
    depositAmount: _money(j['deposit_amount']) ?? 0,
    finalServiceFee: _money(j['final_price']),
    adjustedDiscount: _money(j['adjusted_discount']),
    paymentPreference: _str(j['payment_preference']),
    patientPhone: _str(j['patient_phone']),
    // Milestone tracker block, derived server-side from `status` (see
    // backend/src/utils/bookingMilestones.js). Older backends omit these —
    // `fromWire` and `listFrom` both degrade to a locally-derived lifecycle
    // so the tracker still renders.
    milestone: milestone,
    milestoneLabel: _str(j['milestone_label']) ?? '',
    scheduledTime: _date(j['scheduled_time']) ?? _date(j['preferred_time']),
    scheduledTimeLabel: _str(j['scheduled_time_label']),
    assignedProviderName: _str(j['assigned_provider_name']),
    providerType: providerType,
    // The dispatch-time contact card. Null until an admin assigns someone —
    // and null for a booking whose provider record carries no name at all,
    // which the tracking screen reads as "nobody to show yet".
    assignedProvider: AssignedProvider.fromJson(
      j['assigned_provider'],
      fallbackType: providerType,
    ),
    timeline: MilestoneTimelineEntry.listFrom(
      j['milestone_timeline'],
      current: milestone,
      providerType: providerType,
    ),
    updatedAt: _date(j['updated_at']) ?? DateTime.now(),
  );
}

/// Doctor `upcoming_today[]` item. Fee prefers the admin's `final_price`,
/// falling back to the patient's `offered_budget`, then a generic `fee`.
UpcomingAppointment upcomingAppointmentFromMongo(Map<String, dynamic> j) {
  return UpcomingAppointment(
    id: _idOf(j),
    startTime:
        _date(j['preferred_time']) ?? _date(j['start_time']) ?? DateTime.now(),
    patientName: _str(j['patient_name']) ?? '',
    serviceName: _str(j['care_type']) ?? _str(j['service_name']) ?? '',
    fee: _money(j['final_price']) ??
        _money(j['offered_budget']) ??
        _money(j['fee']) ??
        0,
    distanceKm: _money(j['distance_km']),
    address: _str(j['location_text']),
    status: _str(j['status']) ?? '',
    patientPhone: _str(j['patient_phone']),
    patientAccountId: _str(j['patient_account_id']),
    paymentPreference: _str(j['payment_preference']),
    careRecipient: CareRecipientInfo.fromJson(
      j['care_recipient'],
      ageSex: _str(j['patient_age_sex']) ?? '',
    ),
  );
}

/// `providers` document → [AvailableDoctor] for the admin Assign Team list.
///
/// The `providers` collection carries identity + status (`full_name`,
/// `verification_status`, `availability_status`); per-request match
/// metadata (`rating`, `fee`, `distance_km`, `specialization`,
/// `years_experience`) is enriched server-side by the
/// `/admin/requests/:id/doctors` endpoint and defaults to 0/'' when absent.
AvailableDoctor providerToDoctorFromMongo(Map<String, dynamic> j) {
  final online = (_str(j['availability_status']) ?? 'offline') == 'online';
  return AvailableDoctor(
    id: _idOf(j),
    name: _str(j['full_name']) ?? _str(j['name']) ?? '',
    specialization: _str(j['specialization']) ?? '',
    yearsExperience: _int(j['years_experience']) ?? 0,
    rating: _money(j['rating']) ?? 0,
    reviewCount: _int(j['review_count']) ?? 0,
    distanceKm: _money(j['distance_km']) ?? 0,
    fee: _money(j['fee']) ?? 0,
    isAvailable: online,
    dispatchStatus:
        dispatchStatusFromWire(_str(j['dispatch_status']), fallbackOnline: online),
    activeJobCount: _int(j['active_job_count']) ?? 0,
    onServiceUntil: _date(j['on_service_until']),
  );
}

/// `providers` document (role: nurse) → [AvailableNurse]. Falls back to
/// the doctor-style `specialization` field when the nurse-side
/// `specialty` is blank so freshly-provisioned nurses still surface
/// useful metadata.
AvailableNurse providerToNurseFromMongo(Map<String, dynamic> j) {
  final online = (_str(j['availability_status']) ?? 'offline') == 'online';
  return AvailableNurse(
    id: _idOf(j),
    name: _str(j['full_name']) ?? _str(j['name']) ?? '',
    nursingSpecialty:
        _str(j['specialty']) ?? _str(j['specialization']) ?? '',
    yearsExperience: _int(j['years_experience']) ?? 0,
    rating: _money(j['rating']) ?? 0,
    reviewCount: _int(j['review_count']) ?? 0,
    distanceKm: _money(j['distance_km']) ?? 0,
    fee: _money(j['fee']) ?? 0,
    isAvailable: online,
    dispatchStatus:
        dispatchStatusFromWire(_str(j['dispatch_status']), fallbackOnline: online),
    activeJobCount: _int(j['active_job_count']) ?? 0,
    onServiceUntil: _date(j['on_service_until']),
  );
}

/// `providers` document (role: helper) → [AvailableHelper].
AvailableHelper providerToHelperFromMongo(Map<String, dynamic> j) {
  return AvailableHelper(
    id: _idOf(j),
    name: _str(j['full_name']) ?? _str(j['name']) ?? '',
    specialty: _str(j['specialty']) ?? _str(j['specialization']) ?? '',
    yearsExperience: _int(j['years_experience']) ?? 0,
    fee: _money(j['fee']) ?? 0,
    isAvailable: (_str(j['availability_status']) ?? 'offline') == 'online',
  );
}

/// `recent_providers[]` item → [RecentProvider].
RecentProvider recentProviderFromMongo(Map<String, dynamic> j) {
  return RecentProvider(
    id: _idOf(j),
    name: _str(j['full_name']) ?? _str(j['name']) ?? '',
    specialization: _str(j['specialization']) ?? '',
    yearsExperience: _int(j['years_experience']) ?? 0,
    rating: _money(j['rating']) ?? 0,
    reviewCount: _int(j['review_count']),
    avatarUrl: _str(j['avatar_url']),
    lastVisitAt: _date(j['last_visit_at']),
    role: (_str(j['role']) ?? '').toLowerCase() == 'nurse'
        ? UserRole.nurse
        : UserRole.doctor,
  );
}

/// `/patient/home` response → [PatientHomeFeed]. Snake_case keys
/// (`active_request`, `recent_providers`, `unread_notification_count`).
/// `active_request` may be null when the patient has no open request.
PatientHomeFeed patientHomeFeedFromMongo(Map<String, dynamic> j) {
  final activeRaw = j['active_request'];
  PatientActiveRequest? active;
  if (activeRaw is Map) {
    active = patientActiveFromMongo(Map<String, dynamic>.from(activeRaw));
  }

  final providersRaw = j['recent_providers'] as List? ?? const [];
  final providers = <RecentProvider>[];
  for (final e in providersRaw) {
    try {
      providers.add(recentProviderFromMongo(Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      // skip a malformed provider row, keep the rest
    }
  }

  return PatientHomeFeed(
    activeRequest: active,
    recentProviders: providers,
    unreadNotificationCount: _int(j['unread_notification_count']) ?? 0,
    fetchedAt: _date(j['fetched_at']) ?? DateTime.now(),
  );
}

PendingAssignment pendingAssignmentFromMongo(Map<String, dynamic> j) {
  return PendingAssignment(
    id: _idOf(j),
    serviceNameEn:
        _str(j['service_name_en']) ?? _str(j['care_type']) ?? '',
    serviceNameBn: _str(j['service_name_bn']) ?? '',
    fee: (j['fee'] as num?) ?? (j['offered_budget'] as num?) ?? 0,
    duration: _str(j['duration']) ??
        '${_int(j['duration_hours']) ?? 0} hr',
    patientName: _str(j['patient_name']) ?? '',
    patientAgeSex: _str(j['patient_age_sex']) ?? '',
    patientCondition: _str(j['patient_condition']) ?? '',
    address: _str(j['location_text']) ?? '',
    distanceKm: _dbl(j['distance_km']),
    driveMinutes: _int(j['drive_minutes']),
    expiresAt: _date(j['expires_at']) ??
        DateTime.now().add(const Duration(seconds: 60)),
    tags: (j['tags'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
  );
}

DoctorReview doctorReviewFromMongo(Map<String, dynamic> j) {
  return DoctorReview(
    id: _idOf(j),
    rating: _int(j['rating']) ?? 5,
    text: _str(j['text']) ?? '',
    patientName: _str(j['patient_name']) ?? '',
    createdAt: _date(j['created_at']),
    serviceTag: _str(j['service_tag']),
  );
}

LatestReview? _latestReviewFromMongo(Map<String, dynamic>? j) {
  if (j == null) return null;
  return LatestReview(
    rating: _int(j['rating']) ?? 5,
    text: _str(j['text']) ?? '',
    patientName: _str(j['patient_name']) ?? '',
  );
}

/// `/doctor/dashboard` response → [DoctorDashboard].
DoctorDashboard doctorDashboardFromMongo(Map<String, dynamic> j) {
  final upcomingRaw = j['upcoming_today'] as List? ?? const [];
  // Per-row isolation: a single malformed appointment must not blank the
  // whole Upcoming Today list.
  final upcoming = <UpcomingAppointment>[];
  for (final e in upcomingRaw) {
    try {
      upcoming.add(
          upcomingAppointmentFromMongo(Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      // skip the bad row, keep the rest
    }
  }
  upcoming.sort((a, b) => a.startTime.compareTo(b.startTime));

  final pendingRaw = j['pending_assignment'];
  final pending = pendingRaw is Map<String, dynamic>
      ? pendingAssignmentFromMongo(pendingRaw)
      : (pendingRaw is Map
          ? pendingAssignmentFromMongo(
              Map<String, dynamic>.from(pendingRaw))
          : null);

  final latestRaw = j['latest_review'];
  final latest = latestRaw is Map<String, dynamic>
      ? _latestReviewFromMongo(latestRaw)
      : (latestRaw is Map
          ? _latestReviewFromMongo(Map<String, dynamic>.from(latestRaw))
          : null);

  final reviewsRaw = j['reviews'] as List? ?? const [];
  final reviews = reviewsRaw
      .map((e) => doctorReviewFromMongo(Map<String, dynamic>.from(e as Map)))
      .toList(growable: false);

  return DoctorDashboard(
    todayEarnings: (j['today_earnings'] as num?) ?? 0,
    todayVisits: _int(j['today_visits']) ?? 0,
    weekEarnings: (j['week_earnings'] as num?) ?? 0,
    weekVisits: _int(j['week_visits']) ?? 0,
    rating: ((j['rating'] as num?) ?? 0).toDouble(),
    reviewCount: _int(j['review_count']) ?? 0,
    unreadCount: _int(j['unread_count']) ?? 0,
    profileCompleteness: _int(j['profile_completeness']) ?? 100,
    availability: (j['availability'] as bool?) ?? true,
    latestReview: latest,
    reviews: reviews,
    pendingAssignment: pending,
    upcomingToday: upcoming,
  );
}
