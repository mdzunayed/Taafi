import 'package:equatable/equatable.dart';

/// One row in the Patient's "Past requests" list. Maps directly to a
/// terminal-status `care_requests` document returned by
/// `GET /patient/requests/history?account_id=`.
class PatientHistoryItem extends Equatable {
  final String id;
  final String serviceName;
  final String? doctorName;
  final num offeredBudget;

  /// Set when the admin negotiated a final price. Null on cancelled /
  /// rejected rows where no team ever locked.
  final num? finalPrice;

  /// `completed` | `cancelled` | `rejected`. Drives the chip color
  /// (green for completed, grey for cancelled, red for rejected).
  final String status;

  /// `created_at` from Mongo. Used for the date caption ("Mar 12, 2026").
  final DateTime createdAt;

  /// `updated_at` — falls back to [createdAt] when missing. Used as a
  /// secondary timestamp; the UI shows "Completed Mar 14" using this.
  final DateTime updatedAt;

  final String locationText;

  const PatientHistoryItem({
    required this.id,
    required this.serviceName,
    required this.doctorName,
    required this.offeredBudget,
    required this.finalPrice,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.locationText,
  });

  /// The amount that should be rendered on the card. Prefers
  /// [finalPrice] when present (the negotiated price the patient
  /// actually paid) and falls back to the original offer.
  num get effectivePrice => finalPrice ?? offeredBudget;

  @override
  List<Object?> get props => [
        id,
        serviceName,
        doctorName,
        offeredBudget,
        finalPrice,
        status,
        createdAt,
        updatedAt,
        locationText,
      ];

  factory PatientHistoryItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v, DateTime fallback) {
      if (v == null) return fallback;
      return DateTime.tryParse(v.toString()) ?? fallback;
    }
    final created = parseDate(json['created_at'], DateTime.now());
    return PatientHistoryItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      serviceName: (json['care_type'] ?? '').toString(),
      doctorName: json['assigned_doctor_name']?.toString(),
      offeredBudget: (json['offered_budget'] as num?) ?? 0,
      finalPrice: json['final_price'] as num?,
      status: (json['status'] ?? '').toString(),
      createdAt: created,
      updatedAt: parseDate(json['updated_at'], created),
      locationText: (json['location_text'] ?? '').toString(),
    );
  }
}
