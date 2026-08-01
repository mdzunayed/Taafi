import 'package:equatable/equatable.dart';

import 'patient_active_request.dart';
import 'recent_provider.dart';

class PatientHomeFeed extends Equatable {
  final PatientActiveRequest? activeRequest;
  final List<RecentProvider> recentProviders;
  final int unreadNotificationCount;
  final DateTime fetchedAt;

  const PatientHomeFeed({
    required this.activeRequest,
    required this.recentProviders,
    required this.unreadNotificationCount,
    required this.fetchedAt,
  });

  /// Signed-out / no-session placeholder. Rendered whenever the feed
  /// controller has no authenticated user to scope against, so a logged-out
  /// or mid-account-switch state can never surface a prior user's data.
  factory PatientHomeFeed.empty() => PatientHomeFeed(
        activeRequest: null,
        recentProviders: const [],
        unreadNotificationCount: 0,
        fetchedAt: DateTime.now(),
      );

  PatientHomeFeed copyWith({
    PatientActiveRequest? activeRequest,
    bool clearActiveRequest = false,
    List<RecentProvider>? recentProviders,
    int? unreadNotificationCount,
    DateTime? fetchedAt,
  }) {
    return PatientHomeFeed(
      activeRequest:
          clearActiveRequest ? null : (activeRequest ?? this.activeRequest),
      recentProviders: recentProviders ?? this.recentProviders,
      unreadNotificationCount:
          unreadNotificationCount ?? this.unreadNotificationCount,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  @override
  List<Object?> get props => [
        activeRequest,
        recentProviders,
        unreadNotificationCount,
        fetchedAt,
      ];

  factory PatientHomeFeed.fromJson(Map<String, dynamic> json) {
    return PatientHomeFeed(
      activeRequest: json['activeRequest'] == null
          ? null
          : PatientActiveRequest.fromJson(
              json['activeRequest'] as Map<String, dynamic>),
      recentProviders: (json['recentProviders'] as List?)
              ?.map((e) => RecentProvider.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      unreadNotificationCount:
          (json['unreadNotificationCount'] as num?)?.toInt() ?? 0,
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
