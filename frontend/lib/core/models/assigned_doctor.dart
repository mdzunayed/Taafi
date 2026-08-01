import 'package:equatable/equatable.dart';

/// Read-only view of the doctor that an admin has assigned to a patient's
/// care request. Populated by the backend on `GET /patient/requests/active`
/// (and the `/api/appointments/patient/active` alias) once the admin
/// completes the Assign Team step.
///
/// Every field is nullable / defaulted so a missing record on the backend
/// can't crash the patient app — the UI degrades gracefully (initials in
/// place of the avatar, blank specialty, etc.).
class AssignedDoctor extends Equatable {
  final String id;
  final String fullName;
  final String? profilePicture;
  final String specialty;

  /// Academic degrees ("MBBS, FCPS (Medicine)") — printed on the
  /// prescription pad header. Null when the doctor hasn't filled it.
  final String? degrees;
  final String? hospitalAffiliation;
  final String? bmdcLicense;
  final String? bio;
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final String? phone;
  final String? email;
  final bool isVerifiedDoctor;
  final double fee;
  final int serviceRadiusKm;
  final List<AssignedDoctorExperience> experience;

  const AssignedDoctor({
    required this.id,
    required this.fullName,
    this.profilePicture,
    this.specialty = '',
    this.degrees,
    this.hospitalAffiliation,
    this.bmdcLicense,
    this.bio,
    this.yearsExperience = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.phone,
    this.email,
    this.isVerifiedDoctor = false,
    this.fee = 0,
    this.serviceRadiusKm = 0,
    this.experience = const [],
  });

  /// Two-letter initials for the avatar fallback (`Nafisa Rahman` → `NR`).
  String get initials {
    final cleaned = fullName.replaceAll(RegExp(r'^[Dd]r\.?\s+'), '').trim();
    if (cleaned.isEmpty) return 'DR';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        profilePicture,
        specialty,
        degrees,
        hospitalAffiliation,
        bmdcLicense,
        bio,
        yearsExperience,
        rating,
        reviewCount,
        phone,
        email,
        isVerifiedDoctor,
        fee,
        serviceRadiusKm,
        experience,
      ];

  factory AssignedDoctor.fromJson(Map<String, dynamic> json) {
    String? nonEmpty(dynamic v) {
      final s = v?.toString();
      if (s == null || s.trim().isEmpty) return null;
      return s;
    }

    final rawExperience = (json['experience'] as List?) ?? const [];
    return AssignedDoctor(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString(),
      profilePicture:
          nonEmpty(json['profile_picture'] ?? json['profilePicture']),
      specialty: (json['specialty'] ??
              json['specialization'] ??
              '')
          .toString(),
      degrees: nonEmpty(json['degrees']),
      hospitalAffiliation:
          nonEmpty(json['hospital_affiliation'] ?? json['hospitalAffiliation']),
      bmdcLicense: nonEmpty(json['bmdc_license'] ?? json['bmdcLicense']),
      bio: nonEmpty(json['bio']),
      yearsExperience:
          (json['years_experience'] as num?)?.toInt() ??
              (json['yearsExperience'] as num?)?.toInt() ??
              0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ??
          (json['reviewCount'] as num?)?.toInt() ??
          0,
      phone: nonEmpty(json['phone']),
      email: nonEmpty(json['email']),
      isVerifiedDoctor: (json['is_verified_doctor'] as bool?) ??
          (json['isVerifiedDoctor'] as bool?) ??
          ((json['verification_status'] ?? '').toString().toLowerCase() ==
              'verified'),
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      serviceRadiusKm:
          (json['service_radius_km'] as num?)?.toInt() ??
              (json['serviceRadiusKm'] as num?)?.toInt() ??
              0,
      experience: rawExperience
          .map((e) =>
              AssignedDoctorExperience.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }
}

/// One row from `AssignedDoctor.experience`. Mirrors the backend
/// `Provider.experience[]` sub-doc.
class AssignedDoctorExperience extends Equatable {
  final String hospitalName;
  final String designation;
  final int years;

  const AssignedDoctorExperience({
    required this.hospitalName,
    required this.designation,
    this.years = 0,
  });

  @override
  List<Object?> get props => [hospitalName, designation, years];

  factory AssignedDoctorExperience.fromJson(Map<String, dynamic> json) {
    return AssignedDoctorExperience(
      hospitalName:
          (json['hospital_name'] ?? json['hospitalName'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      years: (json['years'] as num?)?.toInt() ?? 0,
    );
  }
}
