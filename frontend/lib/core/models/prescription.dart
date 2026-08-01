import 'package:equatable/equatable.dart';

import 'assigned_doctor.dart';

/// Three canonical timing slots a prescription line item can be
/// scheduled for. Mirrors the backend `FrequencySlotSchema`.
enum DoseSlot { morning, afternoon, night }

extension DoseSlotX on DoseSlot {
  String get wire {
    switch (this) {
      case DoseSlot.morning:
        return 'morning';
      case DoseSlot.afternoon:
        return 'afternoon';
      case DoseSlot.night:
        return 'night';
    }
  }

  String get labelEn {
    switch (this) {
      case DoseSlot.morning:
        return 'Morning';
      case DoseSlot.afternoon:
        return 'Afternoon';
      case DoseSlot.night:
        return 'Night';
    }
  }

  String get labelBn {
    switch (this) {
      case DoseSlot.morning:
        return 'সকাল';
      case DoseSlot.afternoon:
        return 'দুপুর';
      case DoseSlot.night:
        return 'রাত';
    }
  }

  static DoseSlot fromWire(String s) {
    switch (s.toLowerCase()) {
      case 'afternoon':
        return DoseSlot.afternoon;
      case 'night':
        return DoseSlot.night;
      case 'morning':
      default:
        return DoseSlot.morning;
    }
  }
}

/// Dosage form printed before the drug name on the prescription pad
/// ("Tab. Napa 500mg"). Mirrors the backend `form` enum on the
/// prescription item schema. Nullable on the wire — legacy items and
/// drafts that skip the picker simply omit the prefix.
enum MedicationForm { tab, cap, syr, inj, crm, drop }

extension MedicationFormX on MedicationForm {
  String get wire {
    switch (this) {
      case MedicationForm.tab:
        return 'TAB';
      case MedicationForm.cap:
        return 'CAP';
      case MedicationForm.syr:
        return 'SYR';
      case MedicationForm.inj:
        return 'INJ';
      case MedicationForm.crm:
        return 'CRM';
      case MedicationForm.drop:
        return 'DROP';
    }
  }

  /// Classic pad shorthand rendered before the drug name.
  String get label {
    switch (this) {
      case MedicationForm.tab:
        return 'Tab.';
      case MedicationForm.cap:
        return 'Cap.';
      case MedicationForm.syr:
        return 'Syr.';
      case MedicationForm.inj:
        return 'Inj.';
      case MedicationForm.crm:
        return 'Cream';
      case MedicationForm.drop:
        return 'Drops';
    }
  }

  static MedicationForm? fromWire(String? s) {
    switch ((s ?? '').trim().toUpperCase()) {
      case 'TAB':
        return MedicationForm.tab;
      case 'CAP':
        return MedicationForm.cap;
      case 'SYR':
        return MedicationForm.syr;
      case 'INJ':
        return MedicationForm.inj;
      case 'CRM':
        return MedicationForm.crm;
      case 'DROP':
        return MedicationForm.drop;
      default:
        return null;
    }
  }
}

/// Mealtime context — three-state because some scripts say "any
/// time" and forcing before/after would lie to the patient.
enum MealContext { before, after, either }

extension MealContextX on MealContext {
  String get wire {
    switch (this) {
      case MealContext.before:
        return 'before';
      case MealContext.after:
        return 'after';
      case MealContext.either:
        return 'either';
    }
  }

  String get labelEn {
    switch (this) {
      case MealContext.before:
        return 'Before meal';
      case MealContext.after:
        return 'After meal';
      case MealContext.either:
        return 'Either';
    }
  }

  String get labelBn {
    switch (this) {
      case MealContext.before:
        return 'খাবারের আগে';
      case MealContext.after:
        return 'খাবারের পরে';
      case MealContext.either:
        return 'যেকোনো সময়';
    }
  }

  static MealContext fromWire(String s) {
    switch (s.toLowerCase()) {
      case 'before':
        return MealContext.before;
      case 'after':
        return MealContext.after;
      case 'either':
      default:
        return MealContext.either;
    }
  }
}

class PrescriptionItem extends Equatable {
  /// Mongo `_id` of this row inside the parent prescription. Empty
  /// when the row is a freshly-built draft on the client.
  final String id;
  final MedicationForm? form;
  final String drugName;
  final String dosage;
  final Set<DoseSlot> frequency;
  final MealContext mealContext;
  final int durationDays;
  final String notes;

  const PrescriptionItem({
    this.id = '',
    this.form,
    required this.drugName,
    required this.dosage,
    required this.frequency,
    this.mealContext = MealContext.either,
    this.durationDays = 7,
    this.notes = '',
  });

  /// Pad display name — "Tab. Napa 500mg" when a form is set,
  /// otherwise just the drug name.
  String get displayName =>
      form == null ? drugName : '${form!.label} $drugName';

  /// Bangladeshi-pharmacy shorthand for the daily schedule, e.g. a
  /// morning + night script reads `1+0+1`. Order is always
  /// morning + afternoon + night.
  String get frequencyCode {
    String bit(DoseSlot s) => frequency.contains(s) ? '1' : '0';
    return '${bit(DoseSlot.morning)}+'
        '${bit(DoseSlot.afternoon)}+'
        '${bit(DoseSlot.night)}';
  }

  PrescriptionItem copyWith({
    MedicationForm? form,
    String? drugName,
    String? dosage,
    Set<DoseSlot>? frequency,
    MealContext? mealContext,
    int? durationDays,
    String? notes,
  }) =>
      PrescriptionItem(
        id: id,
        form: form ?? this.form,
        drugName: drugName ?? this.drugName,
        dosage: dosage ?? this.dosage,
        frequency: frequency ?? this.frequency,
        mealContext: mealContext ?? this.mealContext,
        durationDays: durationDays ?? this.durationDays,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [
        id,
        form,
        drugName,
        dosage,
        frequency,
        mealContext,
        durationDays,
        notes,
      ];

  Map<String, dynamic> toJson() => {
        if (form != null) 'form': form!.wire,
        'drug_name': drugName,
        'dosage': dosage,
        'frequency': {
          'morning': frequency.contains(DoseSlot.morning),
          'afternoon': frequency.contains(DoseSlot.afternoon),
          'night': frequency.contains(DoseSlot.night),
        },
        'meal_context': mealContext.wire,
        'duration_days': durationDays,
        'notes': notes,
      };

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) {
    final freqMap = (json['frequency'] as Map?) ?? const {};
    final freq = <DoseSlot>{};
    if (freqMap['morning'] == true) freq.add(DoseSlot.morning);
    if (freqMap['afternoon'] == true) freq.add(DoseSlot.afternoon);
    if (freqMap['night'] == true) freq.add(DoseSlot.night);
    return PrescriptionItem(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      form: MedicationFormX.fromWire(json['form']?.toString()),
      drugName: (json['drug_name'] ?? '').toString(),
      dosage: (json['dosage'] ?? '').toString(),
      frequency: freq,
      mealContext: MealContextX.fromWire(
          (json['meal_context'] ?? 'either').toString()),
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 7,
      notes: (json['notes'] ?? '').toString(),
    );
  }
}

/// One row in the prescription's `dose_log[]`. Records a single
/// "Mark as Taken" event for a (item, slot, day_key) triple.
class DoseLogEntry extends Equatable {
  final String id;
  final String prescriptionItemId;
  final DoseSlot slot;
  final String dayKey; // YYYY-MM-DD
  final DateTime takenAt;

  const DoseLogEntry({
    required this.id,
    required this.prescriptionItemId,
    required this.slot,
    required this.dayKey,
    required this.takenAt,
  });

  @override
  List<Object?> get props => [id, prescriptionItemId, slot, dayKey, takenAt];

  factory DoseLogEntry.fromJson(Map<String, dynamic> json) {
    return DoseLogEntry(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      prescriptionItemId: (json['prescription_item_id'] ?? '').toString(),
      slot: DoseSlotX.fromWire((json['slot'] ?? 'morning').toString()),
      dayKey: (json['day_key'] ?? '').toString(),
      takenAt: DateTime.tryParse((json['taken_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Lifecycle bucket derived from `issued_at` + the longest item
/// duration. Mirrors the backend's `my-active` window filter so the
/// Medications hub can badge each card without another round-trip.
enum PrescriptionStatus { active, completed }

/// Server-computed release gate. A newly issued script stays locked
/// (server-side redacted) for the patient until the booking's service
/// balance is paid AND an admin approves it. Mirrors `releaseStatus`
/// on the wire.
enum PrescriptionReleaseStatus {
  paymentRequired,
  pendingAdminReview,
  unlocked,
  rejected,
}

extension PrescriptionReleaseStatusX on PrescriptionReleaseStatus {
  /// Legacy/older servers omit the field — default to unlocked so
  /// nothing regresses.
  static PrescriptionReleaseStatus fromWire(String s) {
    switch (s.toUpperCase()) {
      case 'PAYMENT_REQUIRED':
        return PrescriptionReleaseStatus.paymentRequired;
      case 'PENDING_ADMIN_REVIEW':
        return PrescriptionReleaseStatus.pendingAdminReview;
      case 'REJECTED':
        return PrescriptionReleaseStatus.rejected;
      case 'UNLOCKED':
      default:
        return PrescriptionReleaseStatus.unlocked;
    }
  }

  String get labelEn {
    switch (this) {
      case PrescriptionReleaseStatus.paymentRequired:
        return 'Balance due';
      case PrescriptionReleaseStatus.pendingAdminReview:
        return 'Under review';
      case PrescriptionReleaseStatus.unlocked:
        return 'Unlocked';
      case PrescriptionReleaseStatus.rejected:
        return 'Rejected';
    }
  }

  String get labelBn {
    switch (this) {
      case PrescriptionReleaseStatus.paymentRequired:
        return 'পেমেন্ট প্রয়োজন';
      case PrescriptionReleaseStatus.pendingAdminReview:
        return 'পর্যালোচনাধীন';
      case PrescriptionReleaseStatus.unlocked:
        return 'আনলকড';
      case PrescriptionReleaseStatus.rejected:
        return 'প্রত্যাখ্যাত';
    }
  }
}

/// Doctor credentials frozen server-side at issue time so the pad
/// header keeps rendering the historical truth even after the doctor
/// edits their profile. Null on legacy scripts — the pad falls back to
/// the live [Prescription.doctor] enrichment block.
class DoctorSnapshot extends Equatable {
  final String name;
  final String degrees;
  final String hospitalOrCollege;
  final String email;
  final String registrationNumber;
  final String specialization;

  const DoctorSnapshot({
    this.name = '',
    this.degrees = '',
    this.hospitalOrCollege = '',
    this.email = '',
    this.registrationNumber = '',
    this.specialization = '',
  });

  @override
  List<Object?> get props =>
      [name, degrees, hospitalOrCollege, email, registrationNumber, specialization];

  factory DoctorSnapshot.fromJson(Map<String, dynamic> json) {
    return DoctorSnapshot(
      name: (json['name'] ?? '').toString(),
      degrees: (json['degrees'] ?? '').toString(),
      hospitalOrCollege:
          (json['hospital_or_college'] ?? json['hospitalOrCollege'] ?? '')
              .toString(),
      email: (json['email'] ?? '').toString(),
      registrationNumber: (json['registration_number'] ??
              json['registrationNumber'] ??
              '')
          .toString(),
      specialization: (json['specialization'] ?? '').toString(),
    );
  }
}

/// Patient metrics printed on the pad's vitals bar. Blood pressure is
/// copied from the visit's CareRequest vitals at issue time;
/// weight/height are doctor-entered on the prescribing form. Null on
/// legacy scripts and redacted (null) while the script is locked.
class VitalsSnapshot extends Equatable {
  final double? weightKg;
  final double? heightCm;
  final String bloodPressure;

  const VitalsSnapshot({
    this.weightKg,
    this.heightCm,
    this.bloodPressure = '',
  });

  bool get isEmpty =>
      weightKg == null && heightCm == null && bloodPressure.isEmpty;

  @override
  List<Object?> get props => [weightKg, heightCm, bloodPressure];

  factory VitalsSnapshot.fromJson(Map<String, dynamic> json) {
    return VitalsSnapshot(
      weightKg: (json['weight_kg'] ?? json['weightKg']) is num
          ? ((json['weight_kg'] ?? json['weightKg']) as num).toDouble()
          : null,
      heightCm: (json['height_cm'] ?? json['heightCm']) is num
          ? ((json['height_cm'] ?? json['heightCm']) as num).toDouble()
          : null,
      bloodPressure:
          (json['blood_pressure'] ?? json['bloodPressure'] ?? '').toString(),
    );
  }
}

/// Target-patient identity printed on the pad header. Populated when the
/// visit was booked for a dependent (family member); null on a self-booking
/// (the account holder) and legacy scripts.
class PatientSnapshot extends Equatable {
  final String name;
  final int? age;
  final String gender;
  final String relationship;
  final String bloodGroup;

  const PatientSnapshot({
    this.name = '',
    this.age,
    this.gender = '',
    this.relationship = '',
    this.bloodGroup = '',
  });

  bool get isEmpty => name.isEmpty && age == null && gender.isEmpty;

  /// "62 yrs · Female" style line, dropping whichever parts are unknown.
  String get ageSexLine {
    final parts = <String>[];
    if (age != null) parts.add('$age yrs');
    if (gender.isNotEmpty) {
      parts.add(gender[0].toUpperCase() + gender.substring(1));
    }
    if (bloodGroup.isNotEmpty && bloodGroup.toLowerCase() != 'unknown') {
      parts.add(bloodGroup);
    }
    return parts.join(' · ');
  }

  @override
  List<Object?> get props => [name, age, gender, relationship, bloodGroup];

  factory PatientSnapshot.fromJson(Map<String, dynamic> json) {
    return PatientSnapshot(
      name: (json['name'] ?? '').toString(),
      age: (json['age']) is num ? (json['age'] as num).toInt() : null,
      gender: (json['gender'] ?? '').toString(),
      relationship: (json['relationship'] ?? '').toString(),
      bloodGroup: (json['blood_group'] ?? json['bloodGroup'] ?? '').toString(),
    );
  }
}

class Prescription extends Equatable {
  final String id;
  final String appointmentId;
  final String patientAccountId;
  final String doctorAccountId;
  final String doctorName;
  final String diagnosis;
  final DateTime issuedAt;
  final List<PrescriptionItem> items;
  final List<DoseLogEntry> doseLog;

  /// Issue-time credential freeze for the pad header. Null on legacy
  /// scripts — see the `pad*` getters for the fallback chain.
  final DoctorSnapshot? doctorSnapshot;

  /// Pad vitals bar data. Null on legacy scripts and while locked.
  final VitalsSnapshot? vitalsSnapshot;

  /// Target-patient identity when issued for a dependent; null = the account
  /// holder themselves. Drives the pad header patient block.
  final PatientSnapshot? patientSnapshot;

  /// "Advice Given" free-text footer block. Redacted ('') while locked.
  final String advice;

  /// Next-appointment timeline for the pad footer. Redacted while locked.
  final DateTime? followUpDate;

  /// Full public profile of the issuing doctor (photo, specialization,
  /// hospital affiliation, BMDC licence, verified flag). Populated by
  /// every prescription read endpoint since the doctor-block
  /// enrichment landed server-side; `null` when the provider row could
  /// not be resolved — the UI falls back to [doctorName] + initials.
  final AssignedDoctor? doctor;

  /// Flat convenience mirrors of the credential fields inside
  /// [doctor], kept so older call sites (vault detail card) don't have
  /// to null-chase the nested block.
  final String doctorBmdc;
  final String doctorSpecialization;
  final bool doctorVerified;

  /// The originating visit's reported condition, surfaced as "symptoms" on
  /// the vault detail card. Only present on the detail fetch.
  final String symptoms;

  /// Server-computed release gate state. When [locked] the server has
  /// already redacted [items]/[doseLog]/[diagnosis] — the client only
  /// decides which gate card to render, never what to hide.
  final PrescriptionReleaseStatus releaseStatus;
  final bool locked;

  /// Fixed platform fee (BDT) to unlock this script. Snapshotted at
  /// issue time server-side.
  final double unlockFeeAmount;

  /// Medication line count. On a locked script [items] arrives empty,
  /// so the server sends the count separately for the vault card.
  final int itemCount;

  /// Patient contact block — present only on admin review-queue rows.
  final String patientName;
  final String patientPhone;

  const Prescription({
    required this.id,
    required this.appointmentId,
    required this.patientAccountId,
    required this.doctorName,
    required this.diagnosis,
    required this.issuedAt,
    required this.items,
    this.doctorAccountId = '',
    this.doseLog = const [],
    this.doctorSnapshot,
    this.vitalsSnapshot,
    this.patientSnapshot,
    this.advice = '',
    this.followUpDate,
    this.doctor,
    this.doctorBmdc = '',
    this.doctorSpecialization = '',
    this.doctorVerified = false,
    this.symptoms = '',
    this.releaseStatus = PrescriptionReleaseStatus.unlocked,
    this.locked = false,
    this.unlockFeeAmount = 0,
    this.itemCount = 0,
    this.patientName = '',
    this.patientPhone = '',
  });

  /// Longest calendar window across all line items — the whole script
  /// stays "active" until every course has run out.
  int get maxDurationDays => items.fold(
      0, (m, it) => it.durationDays > m ? it.durationDays : m);

  /// Calendar day the last course lapses.
  DateTime get endsAt => issuedAt.add(Duration(days: maxDurationDays));

  /// Active vs Completed, matching the backend `my-active` window
  /// filter (a zero-duration script is treated as open-ended).
  PrescriptionStatus get status =>
      maxDurationDays <= 0 || !DateTime.now().isAfter(endsAt)
          ? PrescriptionStatus.active
          : PrescriptionStatus.completed;

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        patientAccountId,
        doctorAccountId,
        doctorName,
        diagnosis,
        issuedAt,
        items,
        doseLog,
        doctorSnapshot,
        vitalsSnapshot,
        patientSnapshot,
        advice,
        followUpDate,
        doctor,
        doctorBmdc,
        doctorSpecialization,
        doctorVerified,
        symptoms,
        releaseStatus,
        locked,
        unlockFeeAmount,
        itemCount,
        patientName,
        patientPhone,
      ];

  /// Effective medication count — the redacted server count when
  /// locked, otherwise the parsed list length.
  int get effectiveItemCount => items.isNotEmpty ? items.length : itemCount;

  // ── Pad header fallback chain ──────────────────────────────────────
  // Frozen snapshot first (new scripts), then the live doctor-block
  // enrichment, then the flat legacy fields — so the pad renders the
  // best available credentials without branching on script age.

  String get padDoctorName {
    final s = doctorSnapshot?.name ?? '';
    if (s.isNotEmpty) return s;
    final d = doctor?.fullName ?? '';
    if (d.isNotEmpty) return d;
    return doctorName;
  }

  String get padDegrees {
    final s = doctorSnapshot?.degrees ?? '';
    if (s.isNotEmpty) return s;
    final d = doctor?.degrees ?? '';
    if (d.isNotEmpty) return d;
    return doctorSpecialization;
  }

  String get padHospitalOrCollege {
    final s = doctorSnapshot?.hospitalOrCollege ?? '';
    if (s.isNotEmpty) return s;
    return doctor?.hospitalAffiliation ?? '';
  }

  String get padRegistrationNumber {
    final s = doctorSnapshot?.registrationNumber ?? '';
    if (s.isNotEmpty) return s;
    return doctorBmdc;
  }

  String get padEmail {
    final s = doctorSnapshot?.email ?? '';
    if (s.isNotEmpty) return s;
    return doctor?.email ?? '';
  }

  /// Is the given (item, slot, day) already logged as taken?
  bool isDoseTaken({
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
  }) {
    for (final d in doseLog) {
      if (d.prescriptionItemId == itemId &&
          d.slot == slot &&
          d.dayKey == dayKey) {
        return true;
      }
    }
    return false;
  }

  factory Prescription.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final rawLog = (json['dose_log'] as List?) ?? const [];
    final doctor = json['doctor'] is Map
        ? Map<String, dynamic>.from(json['doctor'] as Map)
        : const <String, dynamic>{};
    final rawDoctorSnapshot =
        json['doctor_snapshot'] ?? json['doctorSnapshot'];
    final rawVitalsSnapshot =
        json['vitals_snapshot'] ?? json['vitalsSnapshot'];
    final rawPatientSnapshot =
        json['patient_snapshot'] ?? json['patientSnapshot'];
    return Prescription(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      appointmentId: (json['appointmentId'] ??
              json['appointment_id'] ??
              '')
          .toString(),
      patientAccountId: (json['patientAccountId'] ??
              json['patient_account_id'] ??
              '')
          .toString(),
      doctorAccountId: (json['doctor_account_id'] ?? '').toString(),
      doctorName: (json['doctor_name'] ?? '').toString(),
      diagnosis: (json['diagnosis'] ?? '').toString(),
      issuedAt: DateTime.tryParse((json['issued_at'] ?? '').toString()) ??
          DateTime.now(),
      items: [
        for (final r in rawItems)
          if (r is Map)
            PrescriptionItem.fromJson(Map<String, dynamic>.from(r)),
      ],
      doseLog: [
        for (final r in rawLog)
          if (r is Map) DoseLogEntry.fromJson(Map<String, dynamic>.from(r)),
      ],
      doctorSnapshot: rawDoctorSnapshot is Map
          ? DoctorSnapshot.fromJson(
              Map<String, dynamic>.from(rawDoctorSnapshot))
          : null,
      vitalsSnapshot: rawVitalsSnapshot is Map
          ? VitalsSnapshot.fromJson(
              Map<String, dynamic>.from(rawVitalsSnapshot))
          : null,
      patientSnapshot: rawPatientSnapshot is Map
          ? PatientSnapshot.fromJson(
              Map<String, dynamic>.from(rawPatientSnapshot))
          : null,
      advice: (json['advice'] ?? '').toString(),
      followUpDate: DateTime.tryParse(
          (json['follow_up_date'] ?? json['followUpDate'] ?? '').toString()),
      doctor: doctor.isEmpty ? null : AssignedDoctor.fromJson(doctor),
      doctorBmdc: (doctor['bmdc_license'] ?? '').toString(),
      doctorSpecialization: (doctor['specialization'] ?? '').toString(),
      doctorVerified: (doctor['is_verified_doctor'] as bool?) ?? false,
      symptoms: (json['symptoms'] ?? '').toString(),
      releaseStatus: PrescriptionReleaseStatusX.fromWire(
          (json['releaseStatus'] ?? 'UNLOCKED').toString()),
      locked: json['locked'] == true,
      unlockFeeAmount: (json['unlockFeeAmount'] as num?)?.toDouble() ?? 0,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? rawItems.length,
      patientName: json['patient'] is Map
          ? ((json['patient'] as Map)['name'] ?? '').toString()
          : '',
      patientPhone: json['patient'] is Map
          ? ((json['patient'] as Map)['phone'] ?? '').toString()
          : '',
    );
  }
}
