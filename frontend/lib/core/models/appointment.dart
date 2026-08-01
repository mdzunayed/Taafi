import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import 'assigned_doctor.dart';
import 'assigned_nurse.dart';

/// A completed (or in-flight) appointment as returned by
/// `GET /api/appointments/:id` or `GET /api/appointments/latest-completed`.
/// Maps directly to a row in the `care_requests` collection — the backend
/// uses "appointment" as the wire vocab but the storage is shared.
class Appointment extends Equatable {
  final String id;
  final String careType;
  final String status;
  final String? assignedDoctorName;
  final String? assignedHelperName;
  final String locationText;

  /// The patient's account id this visit belongs to. Needed by the
  /// doctor's prescription form so the issued script links back to
  /// the right patient. Empty for legacy payloads that predate the
  /// field being surfaced on this wire shape.
  final String patientAccountId;

  final DateTime createdAt;
  final DateTime updatedAt;

  final AppointmentVitals? vitals;
  final AppointmentPayment? payment;
  final AppointmentFeedback feedback;

  /// Structured procedures the nurse performed on-site (from
  /// `CareRequest.procedures`). Drives the "Procedures completed" chips on
  /// the patient's nursing report. Empty for doctor-only / legacy visits.
  final List<String> procedures;

  /// Free-text clinical wrap-up the provider recorded at completion
  /// (`completion_summary`). Surfaced as read-only "Nurse remarks".
  final String completionSummary;

  /// Populated provider profile lifted off the wire's `doctor` block.
  /// Present when the backend reads the appointment through
  /// `attachDoctorToRequest` (history list, active card, `:id` fetch).
  /// `null` for legacy payloads — the History card falls back to
  /// `assignedDoctorName` only in that case.
  final AssignedDoctor? doctor;

  /// Populated nurse profile lifted off the wire's `nurse` block (same
  /// `attachDoctorToRequest` path). Drives nurse attribution + the assigned
  /// nurse card. `null` when no nurse was assigned.
  final AssignedNurse? nurse;

  const Appointment({
    required this.id,
    required this.careType,
    required this.status,
    required this.locationText,
    required this.createdAt,
    required this.updatedAt,
    this.assignedDoctorName,
    this.assignedHelperName,
    this.patientAccountId = '',
    this.vitals,
    this.payment,
    this.feedback = AppointmentFeedback.empty,
    this.procedures = const [],
    this.completionSummary = '',
    this.doctor,
    this.nurse,
  });

  bool get isReviewed => feedback.isReviewed;

  /// The report was captured by a nurse when a nurse is assigned to the
  /// visit — home nursing visits record vitals/procedures on-site.
  bool get isNurseRecorded => nurse != null;

  /// `Apr 18 · 2:44 PM → 4:48 PM` — the caption under the Care Completed
  /// hero. Falls back to a single timestamp when we only know one bound.
  String get sessionCaption {
    final dateFmt = DateFormat('MMM d');
    final timeFmt = DateFormat('h:mm a');
    if (status == 'completed') {
      return '${dateFmt.format(createdAt)} · '
          '${timeFmt.format(createdAt)} → ${timeFmt.format(updatedAt)}';
    }
    return '${dateFmt.format(createdAt)} · ${timeFmt.format(createdAt)}';
  }

  @override
  List<Object?> get props => [
        id,
        careType,
        status,
        assignedDoctorName,
        assignedHelperName,
        patientAccountId,
        locationText,
        createdAt,
        updatedAt,
        vitals,
        payment,
        feedback,
        procedures,
        completionSummary,
        doctor,
        nurse,
      ];

  factory Appointment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v, DateTime fallback) {
      if (v == null) return fallback;
      return DateTime.tryParse(v.toString()) ?? fallback;
    }
    final created = parseDate(json['created_at'], DateTime.now());
    return Appointment(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      careType: (json['care_type'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      assignedDoctorName: json['assigned_doctor_name']?.toString(),
      assignedHelperName: json['assigned_helper_name']?.toString(),
      patientAccountId: (json['patient_account_id'] ?? '').toString(),
      locationText: (json['location_text'] ?? '').toString(),
      createdAt: created,
      updatedAt: parseDate(json['updated_at'], created),
      vitals: json['vitals'] is Map
          ? AppointmentVitals.fromJson(
              Map<String, dynamic>.from(json['vitals'] as Map))
          : null,
      payment: json['payment'] is Map
          ? AppointmentPayment.fromJson(
              Map<String, dynamic>.from(json['payment'] as Map))
          : null,
      feedback: json['feedback'] is Map
          ? AppointmentFeedback.fromJson(
              Map<String, dynamic>.from(json['feedback'] as Map))
          : AppointmentFeedback.empty,
      procedures: (json['procedures'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          const [],
      completionSummary: (json['completion_summary'] ?? '').toString(),
      doctor: _parseDoctor(json['doctor']),
      nurse: _parseNurse(json['nurse']),
    );
  }

  /// Lift the populated `doctor` sub-doc into an [AssignedDoctor].
  /// Returns null on a missing / busted block so the History card
  /// degrades to the flat `assigned_doctor_name` string gracefully.
  static AssignedDoctor? _parseDoctor(dynamic raw) {
    if (raw is! Map) return null;
    final asMap = Map<String, dynamic>.from(raw);
    final id = asMap['id']?.toString() ?? asMap['_id']?.toString() ?? '';
    final name = (asMap['full_name'] ?? asMap['fullName'] ?? '').toString();
    if (id.isEmpty && name.isEmpty) return null;
    try {
      return AssignedDoctor.fromJson(asMap);
    } catch (_) {
      return null;
    }
  }

  /// Lift the populated `nurse` sub-doc into an [AssignedNurse]. Null-safe
  /// twin of [_parseDoctor].
  static AssignedNurse? _parseNurse(dynamic raw) {
    if (raw is! Map) return null;
    final asMap = Map<String, dynamic>.from(raw);
    final id = asMap['id']?.toString() ?? asMap['_id']?.toString() ?? '';
    final name = (asMap['full_name'] ?? asMap['fullName'] ?? '').toString();
    if (id.isEmpty && name.isEmpty) return null;
    try {
      return AssignedNurse.fromJson(asMap);
    } catch (_) {
      return null;
    }
  }
}

/// Vitals captured at completion. Every field is a string because the
/// doctor app may write a numeric ("128/82") or qualitative ("Clean")
/// value depending on the metric — see backend `vitals` sub-doc.
class AppointmentVitals extends Equatable {
  final String? bloodPressure;
  final String bloodPressureUnit;
  final String? temperature;
  final String temperatureUnit;
  final String? spo2;
  final String spo2Unit;
  final String? pulse;
  final String pulseUnit;
  final String? bloodSugar;
  final String bloodSugarUnit;
  final String? painScore;
  final String? woundStatus;
  final String? recordedBy;
  final DateTime? recordedAt;

  const AppointmentVitals({
    this.bloodPressure,
    this.bloodPressureUnit = 'mmHg',
    this.temperature,
    this.temperatureUnit = '°F',
    this.spo2,
    this.spo2Unit = '%',
    this.pulse,
    this.pulseUnit = 'bpm',
    this.bloodSugar,
    this.bloodSugarUnit = 'mmol/L',
    this.painScore,
    this.woundStatus,
    this.recordedBy,
    this.recordedAt,
  });

  /// True when no metric has been filled in — the Rating screen hides
  /// the vitals card in that case rather than rendering six empty tiles.
  bool get isEmpty =>
      bloodPressure == null &&
      temperature == null &&
      spo2 == null &&
      pulse == null &&
      bloodSugar == null &&
      painScore == null &&
      woundStatus == null;

  @override
  List<Object?> get props => [
        bloodPressure,
        bloodPressureUnit,
        temperature,
        temperatureUnit,
        spo2,
        spo2Unit,
        pulse,
        pulseUnit,
        bloodSugar,
        bloodSugarUnit,
        painScore,
        woundStatus,
        recordedBy,
        recordedAt,
      ];

  factory AppointmentVitals.fromJson(Map<String, dynamic> json) {
    String? s(dynamic v) => v?.toString();
    return AppointmentVitals(
      bloodPressure: s(json['blood_pressure']),
      bloodPressureUnit:
          (json['blood_pressure_unit'] ?? 'mmHg').toString(),
      temperature: s(json['temperature']),
      temperatureUnit: (json['temperature_unit'] ?? '°F').toString(),
      spo2: s(json['spo2']),
      spo2Unit: (json['spo2_unit'] ?? '%').toString(),
      pulse: s(json['pulse']),
      pulseUnit: (json['pulse_unit'] ?? 'bpm').toString(),
      bloodSugar: s(json['blood_sugar']),
      bloodSugarUnit: (json['blood_sugar_unit'] ?? 'mmol/L').toString(),
      painScore: s(json['pain_score']),
      woundStatus: s(json['wound_status']),
      recordedBy: s(json['recorded_by']),
      recordedAt: DateTime.tryParse(json['recorded_at']?.toString() ?? ''),
    );
  }
}

class AppointmentPayment extends Equatable {
  final num doctorFee;
  final num helperFee;
  final num platformFee;
  final num total;
  final String currency;
  final DateTime? releasedAt;

  const AppointmentPayment({
    this.doctorFee = 0,
    this.helperFee = 0,
    this.platformFee = 0,
    this.total = 0,
    this.currency = 'BDT',
    this.releasedAt,
  });

  bool get isReleased => releasedAt != null;
  bool get isEmpty =>
      doctorFee == 0 && helperFee == 0 && platformFee == 0 && total == 0;

  @override
  List<Object?> get props =>
      [doctorFee, helperFee, platformFee, total, currency, releasedAt];

  factory AppointmentPayment.fromJson(Map<String, dynamic> json) {
    num n(dynamic v) => (v as num?) ?? 0;
    return AppointmentPayment(
      doctorFee: n(json['doctor_fee']),
      helperFee: n(json['helper_fee']),
      platformFee: n(json['platform_fee']),
      total: n(json['total']),
      currency: (json['currency'] ?? 'BDT').toString(),
      releasedAt: DateTime.tryParse(json['released_at']?.toString() ?? ''),
    );
  }
}

class AppointmentFeedback extends Equatable {
  final int? rating;
  final List<String> tags;
  final String comment;
  final bool isReviewed;
  final DateTime? submittedAt;

  const AppointmentFeedback({
    this.rating,
    this.tags = const [],
    this.comment = '',
    this.isReviewed = false,
    this.submittedAt,
  });

  static const empty = AppointmentFeedback();

  @override
  List<Object?> get props => [rating, tags, comment, isReviewed, submittedAt];

  factory AppointmentFeedback.fromJson(Map<String, dynamic> json) {
    return AppointmentFeedback(
      rating: (json['rating'] as num?)?.toInt(),
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      comment: (json['comment'] ?? '').toString(),
      isReviewed: (json['is_reviewed'] as bool?) ?? false,
      submittedAt: DateTime.tryParse(json['submitted_at']?.toString() ?? ''),
    );
  }
}
