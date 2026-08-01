import 'package:equatable/equatable.dart';

/// Earnings + visit rollup returned by `GET /doctor/:id/stats`. Lives
/// separately from [DoctorDashboard] so the Doctor's "TODAY / WEEK"
/// tiles can refresh independently of the upcoming-visits feed —
/// crucially, the Active Service screen's "Complete Visit" handler can
/// invalidate just this provider after a successful PATCH and the money
/// tile updates without re-fetching the full dashboard payload.
class DoctorStats extends Equatable {
  final num todayEarnings;
  final int todayVisits;
  final num weekEarnings;
  final int weekVisits;

  /// Mirrored from the `providers` document so the RATING tile next to
  /// the money tiles stays in lockstep when the admin moderates a review.
  final double rating;
  final int reviewCount;

  const DoctorStats({
    required this.todayEarnings,
    required this.todayVisits,
    required this.weekEarnings,
    required this.weekVisits,
    this.rating = 0,
    this.reviewCount = 0,
  });

  @override
  List<Object?> get props => [
        todayEarnings,
        todayVisits,
        weekEarnings,
        weekVisits,
        rating,
        reviewCount,
      ];

  factory DoctorStats.fromJson(Map<String, dynamic> json) {
    return DoctorStats(
      todayEarnings: (json['today_earnings'] as num?) ?? 0,
      todayVisits: (json['today_visits'] as num?)?.toInt() ?? 0,
      weekEarnings: (json['week_earnings'] as num?) ?? 0,
      weekVisits: (json['week_visits'] as num?)?.toInt() ?? 0,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = DoctorStats(
    todayEarnings: 0,
    todayVisits: 0,
    weekEarnings: 0,
    weekVisits: 0,
  );
}
