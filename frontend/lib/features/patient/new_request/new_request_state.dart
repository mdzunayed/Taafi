import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dependent.dart';
import '../../../core/models/service_catalog_item.dart';

/// Whether the patient wants the visit dispatched immediately or scheduled.
enum RequestTiming { asSoonAsPossible, scheduled }

/// Patient delivery address. Kept distinct from the user profile so the
/// patient can override per request without mutating their saved address.
@immutable
class RequestAddress extends Equatable {
  final String line1;
  final String areaCityZip;
  final String label;
  final String? landmark;

  /// Raw GPS coordinates captured by the address manager (geolocator). Null
  /// until the patient pins a precise location; serialized into the
  /// CareRequest payload so admin + clinician can route with zero ambiguity.
  final double? latitude;
  final double? longitude;

  const RequestAddress({
    required this.line1,
    required this.areaCityZip,
    this.label = 'Home',
    this.landmark,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// No real address chosen yet — both the street line and the unit/area line
  /// are blank. Drives the "Add your address" prompt + blocks submission.
  bool get isEmpty => line1.trim().isEmpty && areaCityZip.trim().isEmpty;

  RequestAddress copyWith({
    String? line1,
    String? areaCityZip,
    String? label,
    Object? landmark = _sentinel,
    Object? latitude = _sentinel,
    Object? longitude = _sentinel,
  }) {
    return RequestAddress(
      line1: line1 ?? this.line1,
      areaCityZip: areaCityZip ?? this.areaCityZip,
      label: label ?? this.label,
      landmark: identical(landmark, _sentinel)
          ? this.landmark
          : landmark as String?,
      latitude: identical(latitude, _sentinel)
          ? this.latitude
          : latitude as double?,
      longitude: identical(longitude, _sentinel)
          ? this.longitude
          : longitude as double?,
    );
  }

  String get fullLabel {
    final base = '$line1, $areaCityZip';
    if (landmark != null && landmark!.trim().isNotEmpty) {
      return '$base · ${landmark!.trim()}';
    }
    return base;
  }

  @override
  List<Object?> get props =>
      [line1, areaCityZip, label, landmark, latitude, longitude];
}

const _sentinel = Object();

/// Attachment payload metadata. Wrapped so we can show a "filled" chip in the
/// UI and so the notifier can swap mock values for real file paths later
/// without touching the form layer.
@immutable
class RequestAttachments extends Equatable {
  /// Path or filename of the discharge summary file.
  final String? discharge;
  /// Free-form summary line, e.g. "BP 120/80 · HR 78 · Temp 98.6°F".
  final String? vitals;
  /// Filename + duration label, e.g. "voice_note_0023s.m4a".
  final String? voiceNote;

  const RequestAttachments({
    this.discharge,
    this.vitals,
    this.voiceNote,
  });

  static const empty = RequestAttachments();

  RequestAttachments copyWith({
    Object? discharge = _sentinel,
    Object? vitals = _sentinel,
    Object? voiceNote = _sentinel,
  }) {
    return RequestAttachments(
      discharge: identical(discharge, _sentinel)
          ? this.discharge
          : discharge as String?,
      vitals:
          identical(vitals, _sentinel) ? this.vitals : vitals as String?,
      voiceNote: identical(voiceNote, _sentinel)
          ? this.voiceNote
          : voiceNote as String?,
    );
  }

  @override
  List<Object?> get props => [discharge, vitals, voiceNote];
}

/// Who the booked visit is for. `null` on [NewRequestState.careRecipient]
/// means the booking patient themselves ("Myself"); otherwise this is a saved
/// dependent's snapshot, sent to the backend as `care_recipient` so the
/// responding clinician sees the recipient + their critical history.
@immutable
class CareRecipient extends Equatable {
  final String dependentId;
  final String name;
  final String relationship;
  final String gender;
  final String dateOfBirth;
  final String bloodGroup;
  final List<String> medicalConditions;
  final String medicalNotes;

  const CareRecipient({
    required this.dependentId,
    required this.name,
    this.relationship = '',
    this.gender = '',
    this.dateOfBirth = '',
    this.bloodGroup = '',
    this.medicalConditions = const [],
    this.medicalNotes = '',
  });

  /// Build the booking snapshot from a saved [Dependent].
  factory CareRecipient.fromDependent(Dependent d) => CareRecipient(
        dependentId: d.id,
        name: d.fullName,
        relationship: d.relationshipTag,
        gender: d.gender,
        dateOfBirth: d.dateOfBirth,
        bloodGroup: d.bloodGroup,
        medicalConditions: d.knownMedicalConditions,
        medicalNotes: d.criticalAllergiesMedicalHistory,
      );

  Map<String, dynamic> toPayload() => {
        'dependent_id': dependentId,
        'name': name,
        'relationship': relationship,
        'gender': gender,
        'date_of_birth': dateOfBirth,
        'blood_group': bloodGroup,
        'medical_conditions': medicalConditions,
        'medical_notes': medicalNotes,
      };

  @override
  List<Object?> get props => [
        dependentId,
        name,
        relationship,
        gender,
        dateOfBirth,
        bloodGroup,
        medicalConditions,
        medicalNotes,
      ];
}

/// Single source of truth for the New Request form. Immutable — every mutation
/// flows through [copyWith] from the notifier so the UI rebuild graph is
/// predictable and easy to test.
@immutable
class NewRequestState extends Equatable {
  /// The chosen service from the catalog. `null` while the catalog is still
  /// loading or before the user selects one. Submission is blocked until set.
  final ServiceCatalogItem? selectedService;

  /// True when [selectedService] arrived from an explicit link the patient
  /// tapped — a home-section card wired to a service in the admin CMS, a promo
  /// banner, or a catalog card — rather than being picked on this form. The
  /// service step then renders as a collapsed summary (with "Change") and the
  /// form scrolls to the next question, so the patient resumes at the step
  /// they'd otherwise have to re-answer. Cleared by `expandServiceSelection`.
  final bool servicePrefilled;

  final RequestTiming timing;
  final DateTime? scheduledAt;

  final RequestAddress address;

  final String notes;
  final RequestAttachments attachments;

  /// Who the session is for. `null` = the booking patient ("Myself").
  final CareRecipient? careRecipient;

  /// Carried in from a [BannerActionType.promoCode] promo-banner tap (see
  /// `banner_action_dispatcher.dart`). Purely informational: sent to the
  /// backend as `promo_code` on the request so the admin sees it during
  /// pricing — there is no automated coupon-validation engine.
  final String? promoCode;

  /// Last validation failure message, surfaced as inline helper text + snack.
  final String? validationError;

  /// Submission lifecycle. `AsyncData(null)` is the idle state. `AsyncLoading`
  /// while we hit the API, `AsyncError` on failure, `AsyncData(id)` on success.
  final AsyncValue<String?> submission;

  /// True when the most recent submit attempt failed at the network layer and
  /// the form contents are being held in memory for a manual retry. Drives
  /// the friendly "Network error. Your submission is cached locally" snackbar.
  final bool cachedLocally;

  const NewRequestState({
    this.selectedService,
    this.servicePrefilled = false,
    this.timing = RequestTiming.asSoonAsPossible,
    this.scheduledAt,
    required this.address,
    this.notes = '',
    this.attachments = RequestAttachments.empty,
    this.careRecipient,
    this.promoCode,
    this.validationError,
    this.submission = const AsyncData(null),
    this.cachedLocally = false,
  });

  /// Default starting state — an empty address. The real default address is
  /// hydrated from the user's saved-address book once it loads (see
  /// `new_request_tab.dart`); until then the location card shows an
  /// "Add your address" prompt and submission is blocked.
  factory NewRequestState.initial() {
    return const NewRequestState(
      address: RequestAddress(line1: '', areaCityZip: '', label: ''),
    );
  }

  bool get isSubmitting => submission.isLoading;

  NewRequestState copyWith({
    Object? selectedService = _sentinel,
    bool? servicePrefilled,
    RequestTiming? timing,
    Object? scheduledAt = _sentinel,
    RequestAddress? address,
    String? notes,
    RequestAttachments? attachments,
    Object? careRecipient = _sentinel,
    Object? promoCode = _sentinel,
    Object? validationError = _sentinel,
    AsyncValue<String?>? submission,
    bool? cachedLocally,
  }) {
    return NewRequestState(
      selectedService: identical(selectedService, _sentinel)
          ? this.selectedService
          : selectedService as ServiceCatalogItem?,
      servicePrefilled: servicePrefilled ?? this.servicePrefilled,
      timing: timing ?? this.timing,
      scheduledAt: identical(scheduledAt, _sentinel)
          ? this.scheduledAt
          : scheduledAt as DateTime?,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      careRecipient: identical(careRecipient, _sentinel)
          ? this.careRecipient
          : careRecipient as CareRecipient?,
      promoCode: identical(promoCode, _sentinel)
          ? this.promoCode
          : promoCode as String?,
      validationError: identical(validationError, _sentinel)
          ? this.validationError
          : validationError as String?,
      submission: submission ?? this.submission,
      cachedLocally: cachedLocally ?? this.cachedLocally,
    );
  }

  @override
  List<Object?> get props => [
        selectedService,
        servicePrefilled,
        timing,
        scheduledAt,
        address,
        notes,
        attachments,
        careRecipient,
        promoCode,
        validationError,
        submission,
        cachedLocally,
      ];
}
