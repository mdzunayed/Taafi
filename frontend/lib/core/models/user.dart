import 'package:equatable/equatable.dart';

enum UserRole { patient, doctor, nurse, admin }

class User extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String? avatar;
  final String? specialization; // for doctors
  final double? rating; // for doctors
  final int? reviewCount; // for doctors

  /// `accounts.status` — "active" / "inactive". Parsed for completeness;
  /// defaults to "active". Not yet surfaced in the UI.
  final String accountStatus;

  /// Mirrors `accounts.is_verified`. Patient sign-ups land here as
  /// `false` until they complete the OTP step; admin/doctor demos seed
  /// it as `true`. The Welcome Back screen reads this to know whether
  /// to bounce a failed-login back to the OTP screen.
  final bool isVerified;

  /// Captured during sign-up Step 1. Rendered in the patient profile.
  /// Defaults empty for legacy seeds that pre-date the field.
  final String address;

  /// Mirrors `accounts.requires_password_reset` — true only for
  /// doctor / nurse rows that an admin just provisioned with a
  /// temporary credential. The auth flow uses this to detour the
  /// session into the ForcedPasswordResetScreen on first login.
  final bool requiresPasswordReset;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.avatar,
    this.specialization,
    this.rating,
    this.reviewCount,
    this.accountStatus = 'active',
    this.isVerified = false,
    this.address = '',
    this.requiresPasswordReset = false,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    email,
    phone,
    role,
    avatar,
    specialization,
    rating,
    reviewCount,
    accountStatus,
    isVerified,
    address,
    requiresPasswordReset,
  ];

  factory User.fromJson(Map<String, dynamic> json) {
    // Accept both the Mongo `accounts` shape (`_id`, `full_name`) and the
    // legacy mock shape (`id`, `name`) so the same model parses either.
    return User(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['full_name'] ?? json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      role: _parseRole(json['role']?.toString()),
      avatar: json['avatar']?.toString(),
      specialization: json['specialization']?.toString(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['reviewCount'] as num?)?.toInt(),
      accountStatus: (json['status'] ?? 'active').toString(),
      isVerified: (json['is_verified'] as bool?) ??
          (json['isVerified'] as bool?) ??
          false,
      address: (json['address'] ?? '').toString(),
      requiresPasswordReset:
          (json['requires_password_reset'] as bool?) ??
              (json['requiresPasswordReset'] as bool?) ??
              false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role.toString().split('.').last,
    'avatar': avatar,
    'specialization': specialization,
    'rating': rating,
    'reviewCount': reviewCount,
    'status': accountStatus,
    'is_verified': isVerified,
    'address': address,
    'requires_password_reset': requiresPasswordReset,
  };

  /// Maps the `accounts.role` vocabulary to the app's three-way [UserRole].
  /// `support_member` is a back-office role that uses the admin console;
  /// `user` is the patient-facing role.
  static UserRole _parseRole(String? roleStr) {
    switch (roleStr?.toLowerCase()) {
      case 'doctor':
        return UserRole.doctor;
      case 'nurse':
        return UserRole.nurse;
      case 'admin':
      case 'support_member':
        return UserRole.admin;
      case 'user':
      case 'patient':
      default:
        return UserRole.patient;
    }
  }
}

class AuthToken extends Equatable {
  final String token;
  final String refreshToken;
  final User user;

  /// Server-issued latch. `true` when the signed-in account was
  /// admin-provisioned and is still carrying a temporary password —
  /// the router detours these sessions into the
  /// `ForcedPasswordResetScreen` instead of the dashboard.
  final bool requiresReset;

  const AuthToken({
    required this.token,
    required this.refreshToken,
    required this.user,
    this.requiresReset = false,
  });

  @override
  List<Object?> get props => [token, refreshToken, user, requiresReset];

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final embeddedUser = User.fromJson(json['user'] ?? {});
    // The server may surface the latch at the top level OR inside the
    // embedded user object — accept either so the client stays
    // truthful even if one path forgets to mirror it.
    final topLevelRequiresReset =
        (json['requiresReset'] as bool?) ?? (json['requires_reset'] as bool?);
    return AuthToken(
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      user: embeddedUser,
      requiresReset:
          topLevelRequiresReset ?? embeddedUser.requiresPasswordReset,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'user': user.toJson(),
    'requiresReset': requiresReset,
  };
}
