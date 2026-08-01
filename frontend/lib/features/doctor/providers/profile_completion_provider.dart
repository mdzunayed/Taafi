import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/doctor_profile_status.dart';
import '../../auth/auth_provider.dart';
import '../doctor_providers.dart';

/// AsyncNotifier backing the "Complete your profile" sheet. Reads the
/// signed-in doctor's id from [currentUserProvider], fetches the live
/// status via `DioClient.getProfileStatus`, and exposes save methods
/// for the work-experience and payout-details forms. Every successful
/// save also invalidates [doctorDashboardProvider] so the percentage
/// banner on the dashboard re-renders without a manual refresh.
class ProfileCompletionNotifier
    extends AutoDisposeAsyncNotifier<ProfileCompletionStatus> {
  @override
  Future<ProfileCompletionStatus> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      // Signed-out edge case: the sheet shouldn't be reachable anyway,
      // but return an empty status so the .when handler renders the
      // empty state instead of crashing.
      return ProfileCompletionStatus.empty;
    }
    return ref.read(dioClientProvider).getProfileStatus(user.id);
  }

  /// Re-fetches the status from the server. Used after non-notifier
  /// saves (avatar upload, BMDC / specialty edits through the existing
  /// `updateProfessionalDetails` path) to pull the fresh percentage.
  Future<void> refresh() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dioClientProvider).getProfileStatus(user.id),
    );
    // The dashboard banner mirrors `profile_completeness` — keep them
    // in lockstep so the page behind the sheet animates in step.
    ref.invalidate(doctorDashboardProvider);
  }

  /// Saves the full experience list (UI sends the post-edit array).
  /// On success the backend returns the fresh status which we drop
  /// straight into state — no second round trip needed.
  Future<bool> saveExperience(List<DoctorExperience> entries) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    state = const AsyncLoading();
    try {
      final fresh = await ref
          .read(dioClientProvider)
          .updateWorkExperience(user.id, entries);
      state = AsyncData(fresh);
      ref.invalidate(doctorDashboardProvider);
      return true;
    } catch (e, st) {
      assert(() {
        debugPrint('[profile-completion] saveExperience failed: $e');
        return true;
      }());
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Saves the bKash / Bank payout sub-doc. [accountNumber] is sent
  /// plaintext; the backend stores then masks on subsequent reads.
  Future<bool> savePayout({
    required String method,
    required String accountNumber,
    String? accountName,
    String? bankName,
    String? branch,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    state = const AsyncLoading();
    try {
      final fresh = await ref.read(dioClientProvider).updatePayoutDetails(
            doctorId: user.id,
            method: method,
            accountNumber: accountNumber,
            accountName: accountName,
            bankName: bankName,
            branch: branch,
          );
      state = AsyncData(fresh);
      ref.invalidate(doctorDashboardProvider);
      return true;
    } catch (e, st) {
      assert(() {
        debugPrint('[profile-completion] savePayout failed: $e');
        return true;
      }());
      state = AsyncError(e, st);
      return false;
    }
  }
}

final profileCompletionProvider = AsyncNotifierProvider.autoDispose<
    ProfileCompletionNotifier, ProfileCompletionStatus>(
  ProfileCompletionNotifier.new,
);
