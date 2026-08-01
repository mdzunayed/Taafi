import 'package:equatable/equatable.dart';

/// Single work-experience row on the doctor's profile. Mirrors the
/// backend `Provider.experience[]` sub-doc.
class DoctorExperience extends Equatable {
  final String hospitalName;
  final String designation;
  final int years;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const DoctorExperience({
    required this.hospitalName,
    required this.designation,
    this.years = 0,
    this.startedAt,
    this.endedAt,
  });

  @override
  List<Object?> get props => [hospitalName, designation, years, startedAt, endedAt];

  /// Sent to `PUT /doctor/work-experience` as part of the `experience`
  /// array. Camel-cased per the backend body alias table.
  Map<String, dynamic> toJson() => {
        'hospitalName': hospitalName,
        'designation': designation,
        'years': years,
        if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
      };

  factory DoctorExperience.fromJson(Map<String, dynamic> json) {
    return DoctorExperience(
      hospitalName:
          (json['hospital_name'] ?? json['hospitalName'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      years: (json['years'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
    );
  }
}

/// bKash / Bank payout snapshot. `accountNumber` is the **masked**
/// value as it comes off the wire (`**** **** *5678`) — full plaintext
/// is write-only and never round-trips. [accountNumberLast4] is
/// convenient for compact displays.
class DoctorPayoutDetails extends Equatable {
  final String method; // 'bKash' | 'Bank' | ''
  final String accountNumber; // masked
  final String accountNumberLast4;
  final String accountName;
  final String bankName;
  final String branch;
  final DateTime? updatedAt;

  const DoctorPayoutDetails({
    this.method = '',
    this.accountNumber = '',
    this.accountNumberLast4 = '',
    this.accountName = '',
    this.bankName = '',
    this.branch = '',
    this.updatedAt,
  });

  bool get isSet => method.isNotEmpty && accountNumberLast4.isNotEmpty;
  bool get isBkash => method == 'bKash';
  bool get isBank => method == 'Bank';

  @override
  List<Object?> get props => [
        method,
        accountNumber,
        accountNumberLast4,
        accountName,
        bankName,
        branch,
        updatedAt,
      ];

  factory DoctorPayoutDetails.fromJson(Map<String, dynamic> json) {
    return DoctorPayoutDetails(
      method: (json['method'] ?? '').toString(),
      accountNumber: (json['account_number'] ?? '').toString(),
      accountNumberLast4: (json['account_number_last4'] ?? '').toString(),
      accountName: (json['account_name'] ?? '').toString(),
      bankName: (json['bank_name'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  static const empty = DoctorPayoutDetails();
}

/// Response shape of `GET /doctor/profile-status`. Five booleans,
/// one percentage, the underlying experience list, and the masked
/// payout block. The credentials sheet reads everything off this.
class ProfileCompletionStatus extends Equatable {
  final bool hasPhoto;

  /// Unified license flag — true when the provider has filled in a
  /// BMDC license (doctor) OR a Nursing Council license (nurse). The
  /// onboarding sheet picks which label to render based on the
  /// signed-in user's role; the engine only cares whether *some*
  /// license is on file.
  final bool hasLicense;

  final bool hasSpecialty;
  final bool hasExperience;
  final bool hasPayout;
  final bool hasDegrees;
  final bool hasHospital;

  /// True when the four pad-header credentials (name, degrees, hospital,
  /// BMDC license) are all on file. The backend gates prescription
  /// issuance on this exact rule; the client mirrors it to gate the
  /// "Write Prescription" entry point.
  final bool credentialsComplete;

  final int completionPercent;
  final int itemsRemaining;
  final List<DoctorExperience> experience;
  final DoctorPayoutDetails payout;

  const ProfileCompletionStatus({
    this.hasPhoto = false,
    this.hasLicense = false,
    this.hasSpecialty = false,
    this.hasExperience = false,
    this.hasPayout = false,
    this.hasDegrees = false,
    this.hasHospital = false,
    this.credentialsComplete = false,
    this.completionPercent = 0,
    this.itemsRemaining = 5,
    this.experience = const [],
    this.payout = DoctorPayoutDetails.empty,
  });

  /// Deprecated alias kept so existing doctor-side callers in
  /// `credentials_sheet.dart` keep compiling during the transition.
  /// New code should read [hasLicense] directly.
  bool get hasBmdc => hasLicense;

  @override
  List<Object?> get props => [
        hasPhoto,
        hasLicense,
        hasSpecialty,
        hasExperience,
        hasPayout,
        hasDegrees,
        hasHospital,
        credentialsComplete,
        completionPercent,
        itemsRemaining,
        experience,
        payout,
      ];

  factory ProfileCompletionStatus.fromResponse(
    Map<String, dynamic> body,
  ) {
    final status = (body['status'] ?? const <String, dynamic>{}) as Map;
    final provider = body['provider'] as Map<String, dynamic>?;
    final rawExperience =
        (provider?['experience'] as List?) ?? const <dynamic>[];
    final rawPayout = provider?['payout_details'] as Map<String, dynamic>?;

    // Prefer the unified `has_license` field; fall back to the legacy
    // `has_bmdc` / role-specific `has_nursing_license` flags for older
    // backend responses still in flight.
    final bool license = (status['has_license'] as bool?) ??
        (status['has_bmdc'] as bool?) ??
        (status['has_nursing_license'] as bool?) ??
        false;

    return ProfileCompletionStatus(
      hasPhoto: (status['has_photo'] as bool?) ?? false,
      hasLicense: license,
      hasSpecialty: (status['has_specialty'] as bool?) ?? false,
      hasExperience: (status['has_experience'] as bool?) ?? false,
      hasPayout: (status['has_payout'] as bool?) ?? false,
      hasDegrees: (status['has_degrees'] as bool?) ?? false,
      hasHospital: (status['has_hospital'] as bool?) ?? false,
      credentialsComplete: (status['credentials_complete'] as bool?) ?? false,
      completionPercent: (status['completion_percent'] as num?)?.toInt() ?? 0,
      itemsRemaining: (status['items_remaining'] as num?)?.toInt() ?? 5,
      experience: rawExperience
          .map((e) => DoctorExperience.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      payout: rawPayout == null
          ? DoctorPayoutDetails.empty
          : DoctorPayoutDetails.fromJson(rawPayout),
    );
  }

  static const empty = ProfileCompletionStatus();
}
