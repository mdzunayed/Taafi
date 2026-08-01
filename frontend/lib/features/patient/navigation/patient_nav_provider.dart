import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

enum PatientActivitiesTab { underReview, tracking, history, medications }

extension PatientActivitiesTabX on PatientActivitiesTab {
  int get index {
    switch (this) {
      case PatientActivitiesTab.underReview:
        return 0;
      case PatientActivitiesTab.tracking:
        return 1;
      case PatientActivitiesTab.history:
        return 2;
      case PatientActivitiesTab.medications:
        return 3;
    }
  }
}

class PatientNavController extends Notifier<int> {
  @override
  int build() => PatientNavIndex.home;

  void changeTab(int index) {
    final next = PatientNavIndex.clamp(index);
    if (state != next) {
      HapticFeedback.lightImpact();
      state = next;
    }
  }
}

class PatientActivitiesController extends Notifier<PatientActivitiesTab> {
  @override
  PatientActivitiesTab build() => PatientActivitiesTab.underReview;

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
  /// Defaults to "Under Review" — same landing the old chip nav had.
  void goToActivities({
    PatientActivitiesTab sub = PatientActivitiesTab.underReview,
  }) {
    read(patientActivitiesTabProvider.notifier).setTab(sub);
    read(patientNavProvider.notifier).changeTab(PatientNavIndex.activities);
  }
}
