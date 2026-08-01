import 'package:equatable/equatable.dart';

/// Server response for `POST /api/admin/providers/:id/request-update-otp`.
///
/// The OTP is dispatched server-side to the provider's registered
/// number; the admin client only ever sees [providerName] +
/// [expiresAt] for the verification dialog header / countdown.
/// [devOtp] is populated ONLY in non-strict dev mode so the QA loop
/// can drive the dialog without watching the server console — the
/// production response strips it.
class ProviderUpdateOtpDispatch extends Equatable {
  final String providerId;
  final String providerName;
  final DateTime expiresAt;
  final String? devOtp;

  const ProviderUpdateOtpDispatch({
    required this.providerId,
    required this.providerName,
    required this.expiresAt,
    this.devOtp,
  });

  @override
  List<Object?> get props => [providerId, providerName, expiresAt, devOtp];

  factory ProviderUpdateOtpDispatch.fromJson(Map<String, dynamic> json) {
    final raw = json['expiresAt']?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return ProviderUpdateOtpDispatch(
      providerId: (json['providerId'] ?? '').toString(),
      providerName: (json['providerName'] ?? '').toString(),
      expiresAt:
          parsed ?? DateTime.now().add(const Duration(minutes: 5)),
      devOtp: json['dev_otp']?.toString(),
    );
  }
}
