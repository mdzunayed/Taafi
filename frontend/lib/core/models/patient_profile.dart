import 'package:equatable/equatable.dart';

/// Patient (user-role) profile shape returned by `GET /patient/profile`.
/// Maps directly to the `accounts` Mongo collection — `password_hash` is
/// already stripped server-side by the Account model's toJSON transform.
class PatientProfile extends Equatable {
  final String id;
  final String fullName;
  final String email;
  final String phone;

  /// `accounts.status` — "active" / "inactive". Surfaced as a small
  /// pill on the profile header.
  final String status;

  /// Server-side `created_at` — used for the "Member since" caption.
  /// Null when the legacy mock payload didn't carry a timestamp.
  final DateTime? createdAt;

  const PatientProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.status = 'active',
    this.createdAt,
  });

  bool get isActive => status == 'active';

  PatientProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? status,
  }) {
    return PatientProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, fullName, email, phone, status, createdAt];

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      createdAt: DateTime.tryParse(
        (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      ),
    );
  }
}
