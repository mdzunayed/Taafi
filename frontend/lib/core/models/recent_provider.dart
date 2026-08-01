import 'package:equatable/equatable.dart';

import 'user.dart';

class RecentProvider extends Equatable {
  final String id;
  final String name;
  final String specialization;
  final int yearsExperience;
  final double rating;
  final int? reviewCount;
  final String? avatarUrl;
  final DateTime? lastVisitAt;

  /// Which provider role this row represents — surfaces a small
  /// "Nurse" tag chip on the patient home Recent Providers list when
  /// `UserRole.nurse`. Defaults to `doctor` so legacy payloads without
  /// the field keep rendering unchanged.
  final UserRole role;

  const RecentProvider({
    required this.id,
    required this.name,
    required this.specialization,
    required this.yearsExperience,
    required this.rating,
    this.reviewCount,
    this.avatarUrl,
    this.lastVisitAt,
    this.role = UserRole.doctor,
  });

  String get subtitle => '$specialization · ${yearsExperience}y';

  @override
  List<Object?> get props => [
        id,
        name,
        specialization,
        yearsExperience,
        rating,
        reviewCount,
        avatarUrl,
        lastVisitAt,
        role,
      ];

  factory RecentProvider.fromJson(Map<String, dynamic> json) {
    return RecentProvider(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      specialization: json['specialization']?.toString() ?? '',
      yearsExperience: (json['yearsExperience'] as num?)?.toInt() ?? 0,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      reviewCount: (json['reviewCount'] as num?)?.toInt(),
      avatarUrl: json['avatarUrl']?.toString(),
      lastVisitAt: DateTime.tryParse(json['lastVisitAt']?.toString() ?? ''),
      role: _parseRole(json['role']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'specialization': specialization,
        'yearsExperience': yearsExperience,
        'rating': rating,
        'reviewCount': reviewCount,
        'avatarUrl': avatarUrl,
        'lastVisitAt': lastVisitAt?.toIso8601String(),
        'role': role.toString().split('.').last,
      };

  static UserRole _parseRole(String? wire) {
    switch (wire?.toLowerCase()) {
      case 'nurse':
        return UserRole.nurse;
      case 'doctor':
      default:
        return UserRole.doctor;
    }
  }
}
