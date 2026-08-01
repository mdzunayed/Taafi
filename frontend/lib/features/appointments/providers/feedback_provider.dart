import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/appointment.dart';
import '../../auth/auth_provider.dart';

/// Whitelisted feedback tags. Must match the backend's
/// `ALLOWED_FEEDBACK_TAGS` set in `routes/appointments.js` — a tag
/// typed differently here would be 400'd on submit.
const kFeedbackTagOptions = <String>[
  'Professional',
  'On time',
  'Careful',
  'Friendly',
  'Explained well',
  'Clean tools',
];

/// Display label for each rating step. Index aligns with the
/// `selectedRating` value — 0 (unset) is intentionally empty so the
/// caption disappears when the user hasn't tapped a star yet.
const kRatingLabels = <String>['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class FeedbackState extends Equatable {
  /// 0 means "not picked yet" — the Submit button gates on `rating >= 1`.
  final int selectedRating;

  /// Tags the user has tapped. `Set<String>` semantics: each tag is
  /// either selected or not, no ordering implied.
  final Set<String> selectedTags;

  /// Async lifecycle of the most recent submit:
  ///   data(null)  → idle (default)
  ///   loading()   → POST in flight
  ///   data(appt)  → success, server returned the updated row
  ///   error()     → backend rejected (with a message we surface)
  final AsyncValue<Appointment?> status;

  const FeedbackState({
    this.selectedRating = 0,
    this.selectedTags = const {},
    this.status = const AsyncData(null),
  });

  bool get isLoading => status.isLoading;
  bool get isReady => selectedRating >= 1;

  FeedbackState copyWith({
    int? selectedRating,
    Set<String>? selectedTags,
    AsyncValue<Appointment?>? status,
  }) {
    return FeedbackState(
      selectedRating: selectedRating ?? this.selectedRating,
      selectedTags: selectedTags ?? this.selectedTags,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [selectedRating, selectedTags, status];
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// One [FeedbackNotifier] per appointment id. `.family` keeps each
/// appointment's draft independent (so opening a different visit
/// doesn't reset the in-progress rating on the current one).
class FeedbackNotifier
    extends AutoDisposeFamilyNotifier<FeedbackState, String> {
  @override
  FeedbackState build(String appointmentId) => const FeedbackState();

  /// Stars-tap handler. Clamps to [0, 5] so an out-of-range value from a
  /// future caller can't poison state.
  void updateRating(int rating) {
    final clamped = rating.clamp(0, 5);
    state = state.copyWith(selectedRating: clamped);
  }

  /// Toggles `tag` in/out of the selected set. Adding a tag not on the
  /// allow-list is silently allowed in state (the backend is the source
  /// of truth on validation), but the Rating screen only renders the
  /// tags from [kFeedbackTagOptions], so practically the set stays
  /// well-formed.
  void toggleTag(String tag) {
    final next = Set<String>.from(state.selectedTags);
    if (!next.add(tag)) next.remove(tag);
    state = state.copyWith(selectedTags: next);
  }

  /// Convenience reset used by the Rating screen when the user backs
  /// out without submitting.
  void reset() => state = const FeedbackState();

  /// POSTs the current rating + tags to
  /// `/api/appointments/:id/feedback`. Resolves with `true` on
  /// success, `false` otherwise (the error message lands in
  /// `state.status` for the screen to surface in a SnackBar).
  Future<bool> submitFeedback() async {
    if (state.selectedRating < 1) {
      state = state.copyWith(
        status: AsyncError(
          Exception('Tap a star to rate the visit first.'),
          StackTrace.current,
        ),
      );
      return false;
    }
    state = state.copyWith(status: const AsyncLoading());
    final dio = ref.read(dioClientProvider);
    final accountId = ref.read(currentUserProvider)?.id;
    try {
      final appt = await dio.submitAppointmentFeedback(
        appointmentId: arg,
        rating: state.selectedRating,
        tags: state.selectedTags.toList(),
        accountId: accountId,
      );
      state = state.copyWith(status: AsyncData(appt));
      return true;
    } catch (e, st) {
      assert(() {
        debugPrint('[feedback] submit failed: $e');
        return true;
      }());
      state = state.copyWith(status: AsyncError(e, st));
      return false;
    }
  }
}

final feedbackProvider = NotifierProvider.autoDispose
    .family<FeedbackNotifier, FeedbackState, String>(FeedbackNotifier.new);

// ---------------------------------------------------------------------------
// Latest-completed-appointment provider — the entry point that backs
// the Rating tab. Auto-disposed so a fresh visit fires a fresh fetch.
// ---------------------------------------------------------------------------

final latestCompletedAppointmentProvider =
    FutureProvider.autoDispose<Appointment?>((ref) async {
  final accountId = ref.watch(currentUserProvider)?.id;
  return ref
      .read(dioClientProvider)
      .getLatestCompletedAppointment(accountId: accountId);
});
