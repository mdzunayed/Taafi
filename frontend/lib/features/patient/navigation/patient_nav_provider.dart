import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../new_request/new_request_notifier.dart';

class PatientNavIndex {
  PatientNavIndex._();

  static const int home = 0;
  static const int newRequest = 1;
  static const int activities = 2;
  static const int account = 3;

  static int clamp(int i) {
    if (i < 0) return 0;
    if (i > 3) return 3;
    return i;
  }
}

/// Sub-tabs of the Activities destination.
///
/// "Under Review" and "Service Status" used to be two of these. They were one
/// booking split across two screens with two independently-derived timelines,
/// plus a status→tab mapping that had to be kept in sync everywhere a
/// deep-link landed. They are now the single [PatientActivitiesTab.activeCare]
/// destination; the retired names live on as aliases in
/// `dynamic_route_dispatcher.dart` so server-issued routes and old
/// notification payloads still resolve.
enum PatientActivitiesTab { activeCare, history, medications }

extension PatientActivitiesTabX on PatientActivitiesTab {
  int get index {
    switch (this) {
      case PatientActivitiesTab.activeCare:
        return 0;
      case PatientActivitiesTab.history:
        return 1;
      case PatientActivitiesTab.medications:
        return 2;
    }
  }
}

class PatientNavController extends Notifier<int> {
  @override
  int build() => PatientNavIndex.home;

  void changeTab(int index) {
    final next = PatientNavIndex.clamp(index);
    if (state == next) return;

    // Leaving the New Request destination abandons the booking flow, so the
    // in-progress form goes with it. This is the shell's stand-in for a
    // `PopScope` reset on a pushed route: the tab is never popped, it's a
    // permanent child of the IndexedStack, so nothing else would ever clear it.
    //
    // Only the *leaving* edge is handled here. Resetting on arrival would race
    // the six entry points that prefill a service and then call
    // `goToNewRequest()` (catalog card, service detail, home section, promo
    // banner, dynamic route, "book again") — their prefill would be wiped by
    // the navigation that is supposed to reveal it.
    if (state == PatientNavIndex.newRequest) {
      ref.read(newRequestProvider.notifier).resetBookingForm();
    }

    HapticFeedback.lightImpact();
    state = next;
  }
}

class PatientActivitiesController extends Notifier<PatientActivitiesTab> {
  @override
  PatientActivitiesTab build() => PatientActivitiesTab.activeCare;

  void setTab(PatientActivitiesTab tab) {
    if (state != tab) {
      HapticFeedback.lightImpact();
      state = tab;
    }
  }
}

final patientNavProvider = NotifierProvider<PatientNavController, int>(
  PatientNavController.new,
);

final patientActivitiesTabProvider =
    NotifierProvider<PatientActivitiesController, PatientActivitiesTab>(
      PatientActivitiesController.new,
    );

extension PatientShellNavExt on WidgetRef {
  void goToHome() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.home);

  void goToNewRequest() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.newRequest);

  void goToAccount() =>
      read(patientNavProvider.notifier).changeTab(PatientNavIndex.account);

  /// Jumps into Activities, optionally pre-selecting the sub-tab.
  /// Defaults to "Active Care" — the booking in flight is what a patient
  /// opening this destination is nearly always here for.
  void goToActivities({
    PatientActivitiesTab sub = PatientActivitiesTab.activeCare,
  }) {
    read(patientActivitiesTabProvider.notifier).setTab(sub);
    read(patientNavProvider.notifier).changeTab(PatientNavIndex.activities);
  }
}
