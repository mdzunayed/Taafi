import 'package:equatable/equatable.dart';

/// Operating-hours window for the platform. `days` uses 0=Sunday … 6=Saturday.
class OperationalHours extends Equatable {
  final String open;
  final String close;
  final List<int> days;

  const OperationalHours({
    this.open = '08:00',
    this.close = '22:00',
    this.days = const [0, 1, 2, 3, 4, 5, 6],
  });

  OperationalHours copyWith({String? open, String? close, List<int>? days}) {
    return OperationalHours(
      open: open ?? this.open,
      close: close ?? this.close,
      days: days ?? this.days,
    );
  }

  factory OperationalHours.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    return OperationalHours(
      open: (json['open'] ?? '08:00').toString(),
      close: (json['close'] ?? '22:00').toString(),
      days: rawDays is List
          ? rawDays.map((e) => (e as num).toInt()).toList()
          : const [0, 1, 2, 3, 4, 5, 6],
    );
  }

  Map<String, dynamic> toJson() => {'open': open, 'close': close, 'days': days};

  @override
  List<Object?> get props => [open, close, days];
}

/// The single global platform-configuration document, mirroring the backend
/// `Settings` model. Backs the admin Settings screen.
class AdminSettings extends Equatable {
  final bool allowAutoAssignment;
  final bool requireVerifiedDoctors;
  final bool maintenanceMode;
  final bool betaCharts;
  final OperationalHours operationalHours;
  final String systemNotification;

  const AdminSettings({
    this.allowAutoAssignment = false,
    this.requireVerifiedDoctors = true,
    this.maintenanceMode = false,
    this.betaCharts = false,
    this.operationalHours = const OperationalHours(),
    this.systemNotification = '',
  });

  static const empty = AdminSettings();

  AdminSettings copyWith({
    bool? allowAutoAssignment,
    bool? requireVerifiedDoctors,
    bool? maintenanceMode,
    bool? betaCharts,
    OperationalHours? operationalHours,
    String? systemNotification,
  }) {
    return AdminSettings(
      allowAutoAssignment: allowAutoAssignment ?? this.allowAutoAssignment,
      requireVerifiedDoctors:
          requireVerifiedDoctors ?? this.requireVerifiedDoctors,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      betaCharts: betaCharts ?? this.betaCharts,
      operationalHours: operationalHours ?? this.operationalHours,
      systemNotification: systemNotification ?? this.systemNotification,
    );
  }

  factory AdminSettings.fromJson(Map<String, dynamic> json) {
    final hoursRaw = json['operational_hours'];
    return AdminSettings(
      allowAutoAssignment: (json['allow_auto_assignment'] as bool?) ?? false,
      requireVerifiedDoctors:
          (json['require_verified_doctors'] as bool?) ?? true,
      maintenanceMode: (json['maintenance_mode'] as bool?) ?? false,
      betaCharts: (json['beta_charts'] as bool?) ?? false,
      operationalHours: hoursRaw is Map
          ? OperationalHours.fromJson(Map<String, dynamic>.from(hoursRaw))
          : const OperationalHours(),
      systemNotification: (json['system_notification'] ?? '').toString(),
    );
  }

  /// Snake_case payload for `PUT /api/admin/settings`.
  Map<String, dynamic> toUpdateJson() => {
        'allow_auto_assignment': allowAutoAssignment,
        'require_verified_doctors': requireVerifiedDoctors,
        'maintenance_mode': maintenanceMode,
        'beta_charts': betaCharts,
        'operational_hours': operationalHours.toJson(),
        'system_notification': systemNotification,
      };

  @override
  List<Object?> get props => [
        allowAutoAssignment,
        requireVerifiedDoctors,
        maintenanceMode,
        betaCharts,
        operationalHours,
        systemNotification,
      ];
}
