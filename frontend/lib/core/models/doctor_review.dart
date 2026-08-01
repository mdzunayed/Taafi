import 'package:equatable/equatable.dart';

/// A single verified patient testimonial used by the doctor dashboard
/// reviews carousel.
///
/// Mirrors the wire shape returned by `GET /doctor/dashboard.reviews`.
class DoctorReview extends Equatable {
  final String id;
  final int rating;
  final String text;
  final String patientName;

  /// When the review was left. Optional so older payloads keep parsing.
  final DateTime? createdAt;

  /// Optional service tag — e.g. "Wound dressing" — shown as a small chip
  /// under the testimonial so the doctor sees which visit it ties to.
  final String? serviceTag;

  const DoctorReview({
    required this.id,
    required this.rating,
    required this.text,
    required this.patientName,
    this.createdAt,
    this.serviceTag,
  });

  @override
  List<Object?> get props =>
      [id, rating, text, patientName, createdAt, serviceTag];

  factory DoctorReview.fromJson(Map<String, dynamic> json) {
    return DoctorReview(
      id: json['id']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 5,
      text: json['text']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      serviceTag: json['serviceTag']?.toString(),
    );
  }
}
