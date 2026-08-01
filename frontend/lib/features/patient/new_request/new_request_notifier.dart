import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart' show ActiveBookingConflict;
import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../admin/admin_providers.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/doctor_providers.dart';
import 'new_request_state.dart';

/// Validation outcome — either `null` for "all clear" or a localized message
/// that the UI surfaces inline and in a snackbar.
typedef ValidationResult = String?;

/// Drives every interaction on the New Request form. Auto-disposed so leaving
/// the tab discards in-progress edits — patients shouldn't see stale form
/// state two days later.
class NewRequestNotifier extends AutoDisposeNotifier<NewRequestState> {
  @override
  NewRequestState build() => NewRequestState.initial();

  // ------------------------------------------------------------------ inputs

  /// Pre-select a service chosen elsewhere (home card, catalog, "book again")
  /// and seed the notes with its title/description. Imperative on purpose:
  /// the notifier stays alive while the New Request tab sits in the shell's
  /// IndexedStack, so a provider-read-in-build prefill would only ever apply
  /// once at startup.
  ///
  /// [fromLink] marks prefills that arrived from an explicit admin-configured
  /// link (a home-section card wired to a service, a promo banner, a catalog
  /// card). The form then opens with the service step already resolved —
  /// collapsed to a summary card, scrolled to the next question — instead of
  /// making the patient re-pick what they just tapped. See
  /// `new_request_tab.dart`.
  void applyServicePrefill(ServiceCatalogItem service, {bool fromLink = false}) {
    state = state.copyWith(
      selectedService: service,
      notes: _buildPrefillNotes(service),
      servicePrefilled: fromLink,
      validationError: null,
    );
  }

  void selectService(ServiceCatalogItem service) {
    state = state.copyWith(
      selectedService: service,
      validationError: null,
    );
  }

  /// Re-open the full service list after a link-driven prefill — the "Change"
  /// affordance on the collapsed service summary. Keeps the selection; only
  /// the presentation expands.
  void expandServiceSelection() {
    if (!state.servicePrefilled) return;
    state = state.copyWith(servicePrefilled: false);
  }

  /// Pre-apply a code carried in from a [BannerActionType.promoCode] promo
  /// banner tap (see `banner_action_dispatcher.dart`). Shown as a dismissible
  /// chip on the form and sent along as `promo_code` on submit — the admin
  /// reads it during pricing rather than it being auto-validated.
  void applyPromoCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(promoCode: trimmed);
  }

  void clearPromoCode() {
    state = state.copyWith(promoCode: null);
  }

  void setTiming(RequestTiming timing) {
    state = state.copyWith(
      timing: timing,
      // Clear scheduledAt when switching back to ASAP so stale future dates
      // don't reappear if the patient toggles.
      scheduledAt:
          timing == RequestTiming.asSoonAsPossible ? null : state.scheduledAt,
      validationError: null,
    );
  }

  void setScheduledAt(DateTime when) {
    state = state.copyWith(
      timing: RequestTiming.scheduled,
      scheduledAt: when,
      validationError: null,
    );
  }

  void setNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  void setAddress({
    String? line1,
    String? areaCityZip,
    String? label,
  }) {
    state = state.copyWith(
      address: state.address.copyWith(
        line1: line1,
        areaCityZip: areaCityZip,
        label: label,
      ),
    );
  }

  void setLandmark(String? landmark) {
    state = state.copyWith(
      address: state.address.copyWith(landmark: landmark),
    );
  }

  /// Replace the whole address (used by the full-screen Address Manager,
  /// which also captures GPS coordinates + landmark instructions).
  void applyAddress(RequestAddress address) {
    state = state.copyWith(address: address);
  }

  /// Bind the care recipient — `null` for "Myself", or a saved dependent.
  void setCareRecipient(CareRecipient? recipient) {
    state = state.copyWith(careRecipient: recipient);
  }

  // ------------------------------------------------------------- attachments

  void setDischarge(String? filename) {
    state = state.copyWith(
      attachments: state.attachments.copyWith(discharge: filename),
    );
  }

  void setVitals(String? summary) {
    state = state.copyWith(
      attachments: state.attachments.copyWith(vitals: summary),
    );
  }

  void setVoiceNote(String? label) {
    state = state.copyWith(
      attachments: state.attachments.copyWith(voiceNote: label),
    );
  }

  // -------------------------------------------------------------- submission

  /// Validates the form. Returns `null` on success, a user-facing string on
  /// failure. Pure — does not touch state — so it can be reused in tests.
  ValidationResult validate() {
    if (state.selectedService == null) {
      return 'Please choose a type of care.';
    }
    if (state.address.isEmpty) {
      return 'Please add your address before submitting.';
    }
    if (state.timing == RequestTiming.scheduled) {
      final when = state.scheduledAt;
      if (when == null) {
        return 'Pick a date and time for the scheduled visit.';
      }
      if (when.isBefore(DateTime.now())) {
        return 'Scheduled time must be in the future.';
      }
    }
    return null;
  }

  /// Submits the request. Returns the new request id on success, or `null` on
  /// validation/network failure (the UI listens to `state.submission` for the
  /// AsyncValue lifecycle).
  Future<String?> submit() async {
    if (state.isSubmitting) return null;

    final error = validate();
    if (error != null) {
      state = state.copyWith(validationError: error);
      return null;
    }

    state = state.copyWith(
      validationError: null,
      submission: const AsyncLoading(),
      cachedLocally: false,
    );

    try {
      final dio = ref.read(dioClientProvider);
      final user = ref.read(currentUserProvider);
      final service = state.selectedService;
      if (service == null) {
        // Defensive — already validated, but the type system can't see that.
        throw StateError('Service became null before submission.');
      }

      // Snake_case payload — exact `care_requests` Mongo write schema:
      //   patient_name, patient_account_id, patient_phone, care_type,
      //   preferred_time, condition_note, location_text, status. `care_type`
      //   is the human-readable service title (e.g. "Post-surgery home care").
      //   Pricing (`offered_budget`) and visit length (`duration_hours`) are
      //   no longer collected here — admin negotiates pricing with the patient
      //   after submission, and the backend defaults both fields. The backend
      //   assigns `_id`, `created_at`, `final_price`, `admin_note` and returns
      //   201 + the row.
      final payload = <String, dynamic>{
        'patient_account_id': user?.id,
        'patient_name': user?.name,
        'patient_phone': user?.phone,
        'care_type': service.title,
        // The catalog row behind this booking. `care_type` is free text and
        // can't be joined back, so without this the backend can't read the
        // service's `provider_type` and the tracker falls back to inferring
        // the attending role from the title.
        'service_id': service.id,
        'preferred_time': state.scheduledAt?.toIso8601String(),
        'condition_note': state.notes.trim(),
        // Join only the parts that exist. The address book now captures one
        // consolidated line (so `line1` is routinely empty), and a naive
        // interpolation would ship a leading ", " into the clinician's
        // dispatch address — and into `areaFromLocation()` on the backend.
        'location_text': [
          state.address.line1.trim(),
          state.address.areaCityZip.trim(),
        ].where((p) => p.isNotEmpty).join(', '),
        'latitude': state.address.latitude,
        'longitude': state.address.longitude,
        'care_recipient': state.careRecipient?.toPayload(),
        'promo_code': state.promoCode,
        'status': 'submitted',
      };

      debugPrint('⚙️ [DEBUG-PATIENT]: Sending payload to MongoDB: $payload');

      final response = await dio.createRequest(payload);
      final id = _extractId(response) ?? 'MT-${DateTime.now().millisecondsSinceEpoch}';

      debugPrint('✅ [DEBUG-PATIENT]: Request successfully recorded on backend.');

      // Refresh the patient home feed so the active request card appears on
      // the Home tab without the user having to pull-to-refresh.
      // ignore: unused_result
      await ref.read(patientHomeFeedProvider.notifier).refresh();

      // Cross-role cache flush. Every role-scoped provider that mirrors
      // the `care_requests` collection must re-read after the 201 commit:
      //
      //   adminRequestsProvider  → Review Queue + counts + Overview row
      //   doctorDashboardProvider → in case a doctor's session shares
      //                             this process (multi-role test build)
      //
      // Diff-poll heartbeats also catch this within 10–12 s, but the
      // explicit invalidate makes the cross-role pickup instant when
      // the consumer is already mounted.
      ref.invalidate(adminRequestsProvider);
      ref.invalidate(doctorDashboardProvider);

      state = state.copyWith(
        submission: AsyncData(id),
        cachedLocally: false,
      );
      return id;
    } on ActiveBookingConflict catch (e, st) {
      // One-active-booking rule fired server-side. The client guard normally
      // catches this first, so landing here means our cached feed was stale
      // (or the other booking was created on another device) — refresh it so
      // the submit bar's banner appears and the button seals itself.
      // ignore: unused_result
      await ref.read(patientHomeFeedProvider.notifier).refresh();
      state = state.copyWith(
        submission: AsyncError(e, st),
        validationError: e.message,
        // Not a transport failure: retrying will keep failing until the
        // other booking closes, so nothing is "cached for later".
        cachedLocally: false,
      );
      return null;
    } on DioException catch (e, st) {
      // Network failure path. Preserve the form so the patient can retry
      // and surface a localized, friendly snackbar instead of the raw
      // exception. UI reads `cachedLocally` to pick the message.
      state = state.copyWith(
        submission: AsyncError(e, st),
        validationError: 'Network error. Your submission is cached locally.',
        cachedLocally: true,
      );
      return null;
    } catch (e, st) {
      state = state.copyWith(
        submission: AsyncError(e, st),
        validationError: _readableError(e),
        cachedLocally: false,
      );
      return null;
    }
  }

  /// Resets the submission slot back to idle after a snackbar/success screen
  /// has been shown. Keeps the form data intact so the patient can edit and
  /// resubmit if the operation failed.
  void clearSubmissionStatus() {
    state = state.copyWith(submission: const AsyncData(null));
  }

  // ------------------------------------------------------------------ helpers

  String _buildPrefillNotes(ServiceCatalogItem item) {
    final buf = StringBuffer('Requesting: ${item.title}');
    if (item.duration != null && item.duration!.isNotEmpty) {
      buf.write(' (${item.duration})');
    }
    if (item.description.isNotEmpty) {
      buf.write('\n\n${item.description}');
    }
    return buf.toString();
  }

  String? _extractId(dynamic response) {
    if (response is Map && response['id'] != null) {
      return response['id'].toString();
    }
    if (response is Map && response['requestId'] != null) {
      return response['requestId'].toString();
    }
    return null;
  }

  String _readableError(Object e) {
    final raw = e.toString();
    if (raw.length > 140) return '${raw.substring(0, 140)}…';
    return raw;
  }
}

/// Public provider — auto-disposed so navigating away from the tab clears the
/// in-progress form. Consumers should `watch` the state and `read` the
/// notifier for actions.
final newRequestProvider =
    NotifierProvider.autoDispose<NewRequestNotifier, NewRequestState>(
  NewRequestNotifier.new,
);
