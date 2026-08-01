import 'package:equatable/equatable.dart';
import 'service.dart';

// ─── KPI Dashboard ───────────────────────────────────────────────────────────

class AdminKpi extends Equatable {
  final int activeServices;
  final int pendingApprovals;
  final int emergencyAlerts;
  final double dailyRevenue;
  final double revenueDelta; // percentage change
  final int totalDoctorsOnDuty;
  final int doctorsInService;

  const AdminKpi({
    required this.activeServices,
    required this.pendingApprovals,
    required this.emergencyAlerts,
    required this.dailyRevenue,
    this.revenueDelta = 0,
    this.totalDoctorsOnDuty = 0,
    this.doctorsInService = 0,
  });

  @override
  List<Object?> get props => [
        activeServices,
        pendingApprovals,
        emergencyAlerts,
        dailyRevenue,
        revenueDelta,
        totalDoctorsOnDuty,
        doctorsInService,
      ];

  factory AdminKpi.fromJson(Map<String, dynamic> json) {
    // Accepts both wire shapes:
    //   • snake_case from `/admin/stats` (Mongo-backed) — `active_services`
    //   • camelCase from the legacy mock layer — `activeServices`
    // Falling back through both keeps offline/mock dev loops working
    // without forcing callers to know which mode is active.
    num? n(String snake, String camel) =>
        (json[snake] as num?) ?? (json[camel] as num?);
    return AdminKpi(
      activeServices: n('active_services', 'activeServices')?.toInt() ?? 0,
      pendingApprovals: n('pending_approvals', 'pendingApprovals')?.toInt() ?? 0,
      emergencyAlerts: n('emergency_alerts', 'emergencyAlerts')?.toInt() ?? 0,
      dailyRevenue: (n('daily_revenue', 'dailyRevenue') ?? 0).toDouble(),
      revenueDelta: (n('revenue_delta', 'revenueDelta') ?? 0).toDouble(),
      totalDoctorsOnDuty:
          n('total_doctors_on_duty', 'totalDoctorsOnDuty')?.toInt() ?? 0,
      doctorsInService:
          n('doctors_in_service', 'doctorsInService')?.toInt() ?? 0,
    );
  }
}

// ─── Activity Feed ───────────────────────────────────────────────────────────

enum ActivityEventType { assignment, arrival, completion, emergency, system }

class ActivityEvent extends Equatable {
  final String id;
  final String message;
  final DateTime timestamp;
  final ActivityEventType eventType;
  final String? requestId;

  const ActivityEvent({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.eventType,
    this.requestId,
  });

  @override
  List<Object?> get props => [id, message, timestamp, eventType, requestId];

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      id: json['id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      eventType: _parseEventType(json['eventType']),
      requestId: json['requestId']?.toString(),
    );
  }

  static ActivityEventType _parseEventType(String? type) {
    switch (type?.toLowerCase()) {
      case 'assignment':
        return ActivityEventType.assignment;
      case 'arrival':
        return ActivityEventType.arrival;
      case 'completion':
        return ActivityEventType.completion;
      case 'emergency':
        return ActivityEventType.emergency;
      default:
        return ActivityEventType.system;
    }
  }
}

// ─── Urgency Level ───────────────────────────────────────────────────────────

enum UrgencyLevel { low, medium, high, critical }

// ─── Enriched Admin Care Request ─────────────────────────────────────────────

class AdminCareRequest extends Equatable {
  final String id;
  final String patientId;
  final String patientName;
  final int patientAge;
  final String? patientGender;
  final ServiceType serviceType;
  final String serviceName;
  final String location;
  final String area;
  final double? latitude;
  final double? longitude;
  final int durationHours;
  final bool asap;
  final DateTime? scheduledTime;
  final String status; // pending, approved, rejected, in_service
  final DateTime createdAt;
  final UrgencyLevel urgencyLevel;
  final String? surgeryDetails;
  final String? patientHistory;
  final String? assignedDoctorId;
  final String? assignedDoctorName;
  final String? assignedHelperId;
  final String? assignedHelperName;
  final double patientOffer;
  final double? adjustedPrice;
  final double? marketPriceMin;
  final double? marketPriceMax;
  final String? notes;
  final String? phone;

  /// Internal note the admin attaches during triage / assignment. Maps to
  /// the Mongo `care_requests.admin_note` field; distinct from [notes]
  /// which carries the patient's `condition_note`.
  final String? adminNote;

  const AdminCareRequest({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.patientAge,
    this.patientGender,
    required this.serviceType,
    required this.serviceName,
    required this.location,
    required this.area,
    this.latitude,
    this.longitude,
    required this.durationHours,
    this.asap = true,
    this.scheduledTime,
    this.status = 'pending',
    required this.createdAt,
    this.urgencyLevel = UrgencyLevel.medium,
    this.surgeryDetails,
    this.patientHistory,
    this.assignedDoctorId,
    this.assignedDoctorName,
    this.assignedHelperId,
    this.assignedHelperName,
    required this.patientOffer,
    this.adjustedPrice,
    this.marketPriceMin,
    this.marketPriceMax,
    this.notes,
    this.phone,
    this.adminNote,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isUrgent =>
      urgencyLevel == UrgencyLevel.high ||
      urgencyLevel == UrgencyLevel.critical;

  AdminCareRequest copyWith({
    String? status,
    String? assignedDoctorId,
    String? assignedDoctorName,
    String? assignedHelperId,
    String? assignedHelperName,
    double? adjustedPrice,
    UrgencyLevel? urgencyLevel,
    String? adminNote,
  }) {
    return AdminCareRequest(
      id: id,
      patientId: patientId,
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      serviceType: serviceType,
      serviceName: serviceName,
      location: location,
      area: area,
      latitude: latitude,
      longitude: longitude,
      durationHours: durationHours,
      asap: asap,
      scheduledTime: scheduledTime,
      status: status ?? this.status,
      createdAt: createdAt,
      urgencyLevel: urgencyLevel ?? this.urgencyLevel,
      surgeryDetails: surgeryDetails,
      patientHistory: patientHistory,
      assignedDoctorId: assignedDoctorId ?? this.assignedDoctorId,
      assignedDoctorName: assignedDoctorName ?? this.assignedDoctorName,
      assignedHelperId: assignedHelperId ?? this.assignedHelperId,
      assignedHelperName: assignedHelperName ?? this.assignedHelperName,
      patientOffer: patientOffer,
      adjustedPrice: adjustedPrice ?? this.adjustedPrice,
      marketPriceMin: marketPriceMin,
      marketPriceMax: marketPriceMax,
      notes: notes,
      phone: phone,
      adminNote: adminNote ?? this.adminNote,
    );
  }

  @override
  List<Object?> get props => [
        id,
        patientId,
        patientName,
        patientAge,
        patientGender,
        serviceType,
        serviceName,
        location,
        area,
        latitude,
        longitude,
        durationHours,
        asap,
        scheduledTime,
        status,
        createdAt,
        urgencyLevel,
        surgeryDetails,
        patientHistory,
        assignedDoctorId,
        assignedDoctorName,
        assignedHelperId,
        assignedHelperName,
        patientOffer,
        adjustedPrice,
        marketPriceMin,
        marketPriceMax,
        notes,
        phone,
        adminNote,
      ];

  factory AdminCareRequest.fromJson(Map<String, dynamic> json) {
    return AdminCareRequest(
      id: json['id']?.toString() ?? '',
      patientId: json['patientId']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      patientAge: (json['patientAge'] as int?) ?? 0,
      patientGender: json['patientGender']?.toString(),
      serviceType: _parseServiceType(json['serviceType']),
      serviceName: json['serviceName']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      area: json['area']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      durationHours: (json['durationHours'] as int?) ?? 1,
      asap: (json['asap'] as bool?) ?? true,
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.tryParse(json['scheduledTime'].toString())
          : null,
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      urgencyLevel: _parseUrgency(json['urgencyLevel']),
      surgeryDetails: json['surgeryDetails']?.toString(),
      patientHistory: json['patientHistory']?.toString(),
      assignedDoctorId: json['assignedDoctorId']?.toString(),
      assignedDoctorName: json['assignedDoctorName']?.toString(),
      assignedHelperId: json['assignedHelperId']?.toString(),
      assignedHelperName: json['assignedHelperName']?.toString(),
      patientOffer: ((json['patientOffer'] as num?) ?? 0).toDouble(),
      adjustedPrice: (json['adjustedPrice'] as num?)?.toDouble(),
      marketPriceMin: (json['marketPriceMin'] as num?)?.toDouble(),
      marketPriceMax: (json['marketPriceMax'] as num?)?.toDouble(),
      notes: json['notes']?.toString(),
      phone: json['phone']?.toString(),
      adminNote: json['adminNote']?.toString(),
    );
  }

  static ServiceType _parseServiceType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'wounddressing':
        return ServiceType.woundDressing;
      case 'vitalscheck':
        return ServiceType.vitalsCheck;
      case 'elderlycare':
        return ServiceType.elderlyCare;
      default:
        return ServiceType.postSurgery;
    }
  }

  static UrgencyLevel _parseUrgency(String? level) {
    switch (level?.toLowerCase()) {
      case 'low':
        return UrgencyLevel.low;
      case 'high':
        return UrgencyLevel.high;
      case 'critical':
        return UrgencyLevel.critical;
      default:
        return UrgencyLevel.medium;
    }
  }
}

// ─── Available Doctor (for assignment) ───────────────────────────────────────

class TimeSlot extends Equatable {
  final DateTime start;
  final DateTime end;
  final String? label;

  const TimeSlot({required this.start, required this.end, this.label});

  bool overlapsWith(DateTime requestStart, DateTime requestEnd) {
    return start.isBefore(requestEnd) && end.isAfter(requestStart);
  }

  @override
  List<Object?> get props => [start, end, label];
}

/// Live duty categorisation of a provider for the admin Dispatch console,
/// mirrors the backend `dispatch_status` wire value.
///
///   - [available]: online with no overlapping booking at the visit time.
///   - [onService]: online but executing / holding a conflicting visit.
///   - [offline]: off duty (no live socket + availability_status offline).
enum DispatchStatus { available, onService, offline }

/// Parse the backend `dispatch_status` string. When absent (older payloads
/// / helper rosters) fall back to the legacy `isAvailable` boolean.
DispatchStatus dispatchStatusFromWire(String? raw, {bool fallbackOnline = false}) {
  switch ((raw ?? '').toUpperCase()) {
    case 'AVAILABLE':
      return DispatchStatus.available;
    case 'ON_SERVICE':
      return DispatchStatus.onService;
    case 'OFFLINE':
      return DispatchStatus.offline;
    default:
      return fallbackOnline ? DispatchStatus.available : DispatchStatus.offline;
  }
}

class AvailableDoctor extends Equatable {
  final String id;
  final String name;
  final String specialization;
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final double distanceKm;
  final double fee;
  final bool isAvailable;
  final List<TimeSlot> upcomingAppointments;
  // ── Dispatch console metadata (from GET /admin/requests/:id/{doctors,team-pool}) ──
  final DispatchStatus dispatchStatus;
  final int activeJobCount;
  final DateTime? onServiceUntil;

  const AvailableDoctor({
    required this.id,
    required this.name,
    required this.specialization,
    required this.yearsExperience,
    required this.rating,
    this.reviewCount = 0,
    required this.distanceKm,
    required this.fee,
    this.isAvailable = true,
    this.upcomingAppointments = const [],
    this.dispatchStatus = DispatchStatus.available,
    this.activeJobCount = 0,
    this.onServiceUntil,
  });

  /// Check if this doctor has an appointment that conflicts with the given time range.
  TimeSlot? conflictWith(DateTime? requestStart, int durationHours) {
    if (requestStart == null) return null;
    final requestEnd = requestStart.add(Duration(hours: durationHours));
    for (final slot in upcomingAppointments) {
      if (slot.overlapsWith(requestStart, requestEnd)) {
        return slot;
      }
    }
    return null;
  }

  String get initials {
    final parts = name.replaceAll('Dr. ', '').trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        name,
        specialization,
        yearsExperience,
        rating,
        reviewCount,
        distanceKm,
        fee,
        isAvailable,
        upcomingAppointments,
        dispatchStatus,
        activeJobCount,
        onServiceUntil,
      ];
}

// ─── Team Pool ───────────────────────────────────────────────────────────────

/// Response shape of `GET /admin/requests/:id/team-pool`. Holds the
/// segregated doctor / nurse rosters the dual-list Assign Team screen
/// renders side-by-side.
class TeamPool extends Equatable {
  final List<AvailableDoctor> doctors;
  final List<AvailableNurse> nurses;

  const TeamPool({
    this.doctors = const [],
    this.nurses = const [],
  });

  @override
  List<Object?> get props => [doctors, nurses];

  static const TeamPool empty = TeamPool();
}

// ─── Available Nurse ─────────────────────────────────────────────────────────

/// Nurse-side equivalent of [AvailableDoctor]. Same shape (so the
/// Assign Team tile can render both lists with a shared widget) but
/// carries the nurse-specific `nursingSpecialty` semantics — e.g.
/// "ICU Care", "Post-Op Wound Care", "Palliative Care".
class AvailableNurse extends Equatable {
  final String id;
  final String name;
  final String nursingSpecialty;
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final double distanceKm;
  final double fee;
  final bool isAvailable;
  // ── Dispatch console metadata (from GET /admin/requests/:id/{nurses,team-pool}) ──
  final DispatchStatus dispatchStatus;
  final int activeJobCount;
  final DateTime? onServiceUntil;

  const AvailableNurse({
    required this.id,
    required this.name,
    required this.nursingSpecialty,
    required this.yearsExperience,
    required this.rating,
    this.reviewCount = 0,
    required this.distanceKm,
    required this.fee,
    this.isAvailable = true,
    this.dispatchStatus = DispatchStatus.available,
    this.activeJobCount = 0,
    this.onServiceUntil,
  });

  String get initials {
    final cleaned = name.replaceAll(RegExp(r'^[Dd]r\.?\s+'), '').trim();
    if (cleaned.isEmpty) return 'NR';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final p = parts.first;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        name,
        nursingSpecialty,
        yearsExperience,
        rating,
        reviewCount,
        distanceKm,
        fee,
        isAvailable,
        dispatchStatus,
        activeJobCount,
        onServiceUntil,
      ];
}

// ─── Available Helper ────────────────────────────────────────────────────────

class AvailableHelper extends Equatable {
  final String id;
  final String name;
  final String specialty;
  final int yearsExperience;
  final double fee;
  final bool isAvailable;

  const AvailableHelper({
    required this.id,
    required this.name,
    required this.specialty,
    required this.yearsExperience,
    required this.fee,
    this.isAvailable = true,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  @override
  List<Object?> get props =>
      [id, name, specialty, yearsExperience, fee, isAvailable];
}

// ─── Request Filter ──────────────────────────────────────────────────────────

class RequestFilter extends Equatable {
  final String? statusFilter; // null = all
  final ServiceType? serviceTypeFilter;
  final String? areaFilter;
  final String searchQuery;
  final bool urgencyOnly;

  /// Multi-select urgency filter applied by the "More Filters" sheet. Empty
  /// means the urgency dimension is not narrowed (the simpler `urgencyOnly`
  /// flag — driven by the Overview hot-toggle and Review Queue "Urgent" chip —
  /// is still honoured for high/critical and stays independent of this set).
  final Set<UrgencyLevel> urgencyLevels;

  const RequestFilter({
    this.statusFilter,
    this.serviceTypeFilter,
    this.areaFilter,
    this.searchQuery = '',
    this.urgencyOnly = false,
    this.urgencyLevels = const {},
  });

  RequestFilter copyWith({
    String? Function()? statusFilter,
    ServiceType? Function()? serviceTypeFilter,
    String? Function()? areaFilter,
    String? searchQuery,
    bool? urgencyOnly,
    Set<UrgencyLevel>? urgencyLevels,
  }) {
    return RequestFilter(
      statusFilter:
          statusFilter != null ? statusFilter() : this.statusFilter,
      serviceTypeFilter: serviceTypeFilter != null
          ? serviceTypeFilter()
          : this.serviceTypeFilter,
      areaFilter: areaFilter != null ? areaFilter() : this.areaFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      urgencyOnly: urgencyOnly ?? this.urgencyOnly,
      urgencyLevels: urgencyLevels ?? this.urgencyLevels,
    );
  }

  /// Are any advanced (non-search) filters active? Used by the Review Queue
  /// to decide whether to render the active-filter chip strip.
  bool get hasAdvancedFilters =>
      serviceTypeFilter != null ||
      areaFilter != null ||
      urgencyLevels.isNotEmpty;

  @override
  List<Object?> get props => [
        statusFilter,
        serviceTypeFilter,
        areaFilter,
        searchQuery,
        urgencyOnly,
        urgencyLevels,
      ];
}

// ─── Live Service Update (Live Monitor tab) ──────────────────────────────────

enum LiveServiceStatus { onTheWay, arrived, inService }

class LiveServiceUpdate extends Equatable {
  /// Same id as the originating [AdminCareRequest] so the map can link to it.
  final String id;
  final String patientName;
  final String doctorName;
  final String area;
  final LiveServiceStatus status;

  /// Visual progress 0..1 — drives the in-row bar and could feed map animation.
  final double progressPercent;

  /// Minutes elapsed since the visit started (or since dispatch for onTheWay).
  final int elapsedMinutes;

  /// Total minutes scheduled. Combined with `elapsedMinutes` to produce the
  /// "0:45 / 0:15" remaining-time label.
  final int totalMinutes;

  /// Optional coordinates so the live-map painter can plot real positions
  /// when the data warrants it.
  final double? latitude;
  final double? longitude;

  const LiveServiceUpdate({
    required this.id,
    required this.patientName,
    required this.doctorName,
    required this.area,
    required this.status,
    required this.progressPercent,
    required this.elapsedMinutes,
    required this.totalMinutes,
    this.latitude,
    this.longitude,
  });

  String get doctorWithArea => '$doctorName · $area';

  /// Formatted "elapsed / remaining" label like "0:45 / 0:15". Remaining can
  /// be negative when the visit has run over schedule.
  String get timeLabel {
    String fmt(int minutes) {
      final sign = minutes < 0 ? '-' : '';
      final abs = minutes.abs();
      final h = abs ~/ 60;
      final m = (abs % 60).toString().padLeft(2, '0');
      return '$sign$h:$m';
    }

    final remaining = totalMinutes - elapsedMinutes;
    return '${fmt(elapsedMinutes)} / ${fmt(remaining)}';
  }

  LiveServiceUpdate copyWith({
    int? elapsedMinutes,
    double? progressPercent,
    LiveServiceStatus? status,
  }) {
    return LiveServiceUpdate(
      id: id,
      patientName: patientName,
      doctorName: doctorName,
      area: area,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      elapsedMinutes: elapsedMinutes ?? this.elapsedMinutes,
      totalMinutes: totalMinutes,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  List<Object?> get props => [
        id,
        patientName,
        doctorName,
        area,
        status,
        progressPercent,
        elapsedMinutes,
        totalMinutes,
        latitude,
        longitude,
      ];
}

// ─── Assign Team State ───────────────────────────────────────────────────────

enum AssignTeamStage { idle, validating, locking, assigning, notifying, done, error }

class AssignTeamState extends Equatable {
  final AssignTeamStage stage;
  final String? errorMessage;

  const AssignTeamState({
    this.stage = AssignTeamStage.idle,
    this.errorMessage,
  });

  bool get isLoading =>
      stage == AssignTeamStage.validating ||
      stage == AssignTeamStage.locking ||
      stage == AssignTeamStage.assigning ||
      stage == AssignTeamStage.notifying;

  bool get isDone => stage == AssignTeamStage.done;
  bool get isError => stage == AssignTeamStage.error;

  String get stageLabel {
    switch (stage) {
      case AssignTeamStage.idle:
        return '';
      case AssignTeamStage.validating:
        return 'Validating assignment...';
      case AssignTeamStage.locking:
        return 'Locking schedule...';
      case AssignTeamStage.assigning:
        return 'Assigning team...';
      case AssignTeamStage.notifying:
        return 'Sending notifications...';
      case AssignTeamStage.done:
        return 'Team assigned successfully!';
      case AssignTeamStage.error:
        return errorMessage ?? 'Assignment failed';
    }
  }

  AssignTeamState copyWith({AssignTeamStage? stage, String? errorMessage}) {
    return AssignTeamState(
      stage: stage ?? this.stage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [stage, errorMessage];
}
