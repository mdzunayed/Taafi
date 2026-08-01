import 'package:equatable/equatable.dart';

/// Doctor (provider-role) profile returned by `GET /doctor/profile`.
/// Maps directly to the `providers` Mongo collection.
///
/// Some fields are admin-controlled and not editable from the Doctor app:
/// [rating], [reviewCount], [verificationStatus]. The profile screen
/// renders them read-only; only the [DoctorProfileNotifier.update] path
/// can mutate the other fields, and the backend `pickDoctorFields`
/// whitelist enforces the same boundary.
class DoctorProfile extends Equatable {
  final String id;
  final String fullName;
  final String email;
  final String phone;

  /// Provider role — `doctor` | `nurse` | `helper`. Drives the role badge
  /// in the admin providers table. Defaults to `doctor` for legacy rows.
  final String role;

  /// Free-text headline specialization (e.g. "Cardiology").
  final String specialization;

  /// Secondary tag (e.g. "Family medicine"). Empty when not set.
  final String specialty;

  final int yearsExperience;

  /// Default per-visit fee (BDT). Stored as a raw number; the UI
  /// renders it via `_money()`.
  final num fee;

  /// Geographic radius (km) the doctor is willing to travel for a
  /// home visit. Used by the admin's match scoring.
  final num serviceRadiusKm;

  final double rating;
  final int reviewCount;

  /// `pending` | `verified`. Drives the green/amber chip on the header.
  final String verificationStatus;

  /// `online` | `offline`. Driven by the prominent Switch on the
  /// profile screen and broadcast through `PATCH /doctor/availability`.
  final String availabilityStatus;

  /// Public URL of the avatar uploaded via
  /// `POST /api/users/:id/upload-avatar`. Empty when the doctor hasn't
  /// uploaded one — the profile screen falls back to the initials.
  final String profilePicture;

  /// Free-form "About me" copy rendered on the profile.
  final String bio;

  /// Hospital / clinic the doctor is currently affiliated with.
  final String hospitalAffiliation;

  /// Academic degrees printed on the prescription pad header,
  /// e.g. "MBBS, FCPS (Medicine)".
  final String degrees;

  /// BMDC (Bangladesh Medical & Dental Council) registration number,
  /// e.g. "A-12345". Frozen onto the prescription pad as the doctor's
  /// registration line; required before the doctor can issue scripts.
  final String bmdcLicense;

  /// BNMC (Bangladesh Nursing & Midwifery Council) registration number for
  /// nurse-role providers. Empty for doctors. Surfaced in the Nurse
  /// Verification Queue for credential review.
  final String nursingLicense;

  /// Drives the small checkmark badge next to the doctor's name on
  /// the Profile header. Distinct from [isVerified] (the admin-
  /// managed enum) so the UI doesn't need to know about that vocab.
  final bool isVerifiedDoctor;

  final DateTime? createdAt;

  const DoctorProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.role = 'doctor',
    this.specialization = '',
    this.specialty = '',
    this.yearsExperience = 0,
    this.fee = 0,
    this.serviceRadiusKm = 5,
    this.rating = 0,
    this.reviewCount = 0,
    this.verificationStatus = 'pending',
    this.availabilityStatus = 'offline',
    this.profilePicture = '',
    this.bio = '',
    this.hospitalAffiliation = '',
    this.degrees = '',
    this.bmdcLicense = '',
    this.nursingLicense = '',
    this.isVerifiedDoctor = false,
    this.createdAt,
  });

  bool get isVerified => verificationStatus == 'verified';
  bool get isOnline => availabilityStatus == 'online';

  DoctorProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? specialization,
    String? specialty,
    int? yearsExperience,
    num? fee,
    num? serviceRadiusKm,
    double? rating,
    int? reviewCount,
    String? verificationStatus,
    String? availabilityStatus,
    String? profilePicture,
    String? bio,
    String? hospitalAffiliation,
    String? degrees,
    String? bmdcLicense,
    bool? isVerifiedDoctor,
  }) {
    return DoctorProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role,
      specialization: specialization ?? this.specialization,
      specialty: specialty ?? this.specialty,
      yearsExperience: yearsExperience ?? this.yearsExperience,
      fee: fee ?? this.fee,
      serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      profilePicture: profilePicture ?? this.profilePicture,
      bio: bio ?? this.bio,
      hospitalAffiliation: hospitalAffiliation ?? this.hospitalAffiliation,
      degrees: degrees ?? this.degrees,
      bmdcLicense: bmdcLicense ?? this.bmdcLicense,
      nursingLicense: nursingLicense,
      isVerifiedDoctor: isVerifiedDoctor ?? this.isVerifiedDoctor,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        phone,
        role,
        specialization,
        specialty,
        yearsExperience,
        fee,
        serviceRadiusKm,
        rating,
        reviewCount,
        verificationStatus,
        availabilityStatus,
        profilePicture,
        bio,
        hospitalAffiliation,
        degrees,
        bmdcLicense,
        nursingLicense,
        isVerifiedDoctor,
        createdAt,
      ];

  factory DoctorProfile.fromJson(Map<String, dynamic> json) {
    return DoctorProfile(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      role: (json['role'] ?? 'doctor').toString(),
      specialization: (json['specialization'] ?? '').toString(),
      specialty: (json['specialty'] ?? '').toString(),
      yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
      fee: (json['fee'] as num?) ?? 0,
      serviceRadiusKm: (json['service_radius_km'] as num?) ?? 5,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      verificationStatus:
          (json['verification_status'] ?? 'pending').toString(),
      availabilityStatus:
          (json['availability_status'] ?? 'offline').toString(),
      profilePicture: (json['profile_picture'] ?? json['photo_url'] ?? '')
          .toString(),
      bio: (json['bio'] ?? '').toString(),
      hospitalAffiliation:
          (json['hospital_affiliation'] ?? json['hospitalAffiliation'] ?? '')
              .toString(),
      degrees: (json['degrees'] ?? '').toString(),
      bmdcLicense:
          (json['bmdc_license'] ?? json['bmdcLicense'] ?? '').toString(),
      nursingLicense:
          (json['nursing_license'] ?? json['nursingLicense'] ?? '').toString(),
      // Prefer the new explicit boolean; fall back to the admin-managed
      // enum for legacy rows that pre-date the field.
      isVerifiedDoctor: (json['is_verified_doctor'] as bool?) ??
          (json['isVerifiedDoctor'] as bool?) ??
          ((json['verification_status'] ?? '').toString() == 'verified'),
      createdAt: DateTime.tryParse(
        (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      ),
    );
  }
}
