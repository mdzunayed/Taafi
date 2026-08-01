import 'package:equatable/equatable.dart';

/// Nurse professional profile returned by `GET /doctor/nurse-profile`.
/// Maps the identity (`accounts`) + professional (`providers`, role: nurse)
/// fields the Nurse Profile screen edits. The BNMC registration number is
/// stored in the Provider's `nursing_license` field.
class NurseProfile extends Equatable {
  /// Canonical account id (the Flutter session id).
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String profilePicture;

  /// Bangladesh Nursing & Midwifery Council registration number.
  final String nursingLicense;
  final String specialization;

  /// Nursing qualifications / degrees (e.g. "B.Sc in Nursing, Diploma in
  /// Orthopedics"). Stored on the shared Provider `degrees` field.
  final String qualifications;
  final int yearsExperience;
  final String hospitalAffiliation;
  final String bio;

  /// `pending` | `verified` — drives the verified badge on the header.
  final String verificationStatus;
  final bool isVerifiedNurse;

  /// Default visit fee / base service charge (BDT). Edited from the
  /// profile's "Default Fee" sheet via PATCH /api/provider/profile-settings.
  final int fee;

  /// `online` | `offline` — current on/off-duty discoverability. Seeds the
  /// duty toggle so it reflects the real server state on load.
  final String availabilityStatus;

  const NurseProfile({
    required this.id,
    required this.fullName,
    this.email = '',
    this.phone = '',
    this.profilePicture = '',
    this.nursingLicense = '',
    this.specialization = '',
    this.qualifications = '',
    this.yearsExperience = 0,
    this.hospitalAffiliation = '',
    this.bio = '',
    this.verificationStatus = 'pending',
    this.isVerifiedNurse = false,
    this.fee = 0,
    this.availabilityStatus = 'offline',
  });

  bool get isVerified => isVerifiedNurse || verificationStatus == 'verified';

  bool get isOnline => availabilityStatus == 'online';

  static const empty = NurseProfile(id: '', fullName: '');

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        phone,
        profilePicture,
        nursingLicense,
        specialization,
        qualifications,
        yearsExperience,
        hospitalAffiliation,
        bio,
        verificationStatus,
        isVerifiedNurse,
        fee,
        availabilityStatus,
      ];

  factory NurseProfile.fromJson(Map<String, dynamic> json) {
    return NurseProfile(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      profilePicture:
          (json['profile_picture'] ?? json['photo_url'] ?? '').toString(),
      nursingLicense:
          (json['nursing_license'] ?? json['nursingLicense'] ?? '').toString(),
      specialization: (json['specialization'] ?? '').toString(),
      qualifications:
          (json['degrees'] ?? json['qualifications'] ?? '').toString(),
      yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
      hospitalAffiliation:
          (json['hospital_affiliation'] ?? json['hospitalAffiliation'] ?? '')
              .toString(),
      bio: (json['bio'] ?? '').toString(),
      verificationStatus:
          (json['verification_status'] ?? 'pending').toString(),
      isVerifiedNurse: (json['is_verified_nurse'] as bool?) ??
          ((json['verification_status'] ?? '').toString() == 'verified'),
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      availabilityStatus:
          (json['availability_status'] ?? 'offline').toString(),
    );
  }
}
