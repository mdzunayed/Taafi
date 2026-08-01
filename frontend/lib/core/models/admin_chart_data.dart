import 'package:equatable/equatable.dart';

/// One bar in the Admin Overview's "Requests — past 7 days" chart.
/// Mirrors the backend `/admin/chart-data` row shape (one entry per
/// calendar day, even when zero rows landed on that day).
class AdminChartPoint extends Equatable {
  /// ISO calendar date (`YYYY-MM-DD`) — kept around for tooltips and
  /// for diff-poll equality.
  final String date;

  /// Short day label rendered under the bar (`Mon`, `Tue`, …).
  final String label;

  /// `approved` + `completed` status rollup. Painted as the brand bar.
  final int approved;

  /// `rejected` + `cancelled` status rollup. Painted as the grey bar.
  final int declined;

  /// Total rows that fell into this bucket (approved + declined + others
  /// like `submitted`). Currently used for the empty-day check.
  final int total;

  const AdminChartPoint({
    required this.date,
    required this.label,
    required this.approved,
    required this.declined,
    required this.total,
  });

  @override
  List<Object?> get props => [date, label, approved, declined, total];

  factory AdminChartPoint.fromJson(Map<String, dynamic> json) {
    return AdminChartPoint(
      date: (json['date'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      approved: (json['approved'] as num?)?.toInt() ?? 0,
      declined: (json['declined'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminChartData extends Equatable {
  final List<AdminChartPoint> series;
  const AdminChartData({required this.series});

  bool get isEmpty => series.every((p) => p.total == 0);

  /// Highest approved-or-declined count in the window. Drives the chart's
  /// Y-axis ceiling so a quiet week still renders proportional bars.
  int get max {
    var m = 0;
    for (final p in series) {
      if (p.approved > m) m = p.approved;
      if (p.declined > m) m = p.declined;
    }
    return m;
  }

  @override
  List<Object?> get props => [series];

  factory AdminChartData.fromJson(Map<String, dynamic> json) {
    final raw = (json['series'] as List?) ?? const [];
    return AdminChartData(
      series: raw
          .map((e) => AdminChartPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  static const empty = AdminChartData(series: []);
}
