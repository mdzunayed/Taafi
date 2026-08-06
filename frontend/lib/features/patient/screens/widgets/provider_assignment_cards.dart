import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/assigned_doctor.dart';
import '../../../../core/models/assigned_nurse.dart';
import '../../../../core/models/patient_active_request.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import 'patient_home_palette.dart';

/// True when the booking names a clinician through the older populate blocks
/// only (no `assigned_provider` contact snapshot).
bool hasLegacyProvider(PatientActiveRequest r) =>
    r.assignedDoctor != null ||
    r.assignedNurse != null ||
    (r.displayProviderName?.isNotEmpty ?? false);

/// Fallback contact card for a booking whose clinician is only described by
/// the populated doctor / nurse blocks. Same three answers as
/// `AssignedProviderCard` — who, what are their credentials, how do I call —
/// built from whichever record exists.
class LegacyProviderCard extends StatelessWidget {
  final PatientActiveRequest request;

  const LegacyProviderCard({super.key, required this.request});

  static Future<void> _call(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: trimmed));
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final AssignedDoctor? doctor = request.assignedDoctor;
    final AssignedNurse? nurse = request.assignedNurse;

    final name = doctor?.fullName ??
        nurse?.fullName ??
        request.displayProviderName ??
        'Your assigned ${request.providerRoleLabel.toLowerCase()}';
    final speciality = doctor?.specialty ??
        nurse?.qualifications ??
        request.providerSpecialization ??
        '';
    final phone = (nurse?.phone ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hd.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), ''),
                size: 48,
                backgroundColor: hd.surface,
                textColor: hd.violetBright,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.labelLg.copyWith(color: hd.title),
                    ),
                    if (speciality.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        speciality,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.bodySm.copyWith(color: hd.body),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              // A dead button is worse than no button: without a number on
              // file the patient is pointed at the support desk below.
              onPressed: phone.isEmpty ? null : () => _call(phone),
              style: OutlinedButton.styleFrom(
                foregroundColor: hd.violetBright,
                side: BorderSide(color: hd.violetBright),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: Text(
                phone.isEmpty
                    ? 'Contact via support'
                    : 'Call ${request.providerRoleLabel}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rendered while the admin is still matching a clinician to the booking.
class AwaitingAssignmentCard extends StatelessWidget {
  final String roleLabel;

  const AwaitingAssignmentCard({super.key, required this.roleLabel});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hd.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(hd.violetBright),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matching your ${roleLabel.toLowerCase()}',
                  style: MtTextStyles.labelMd.copyWith(
                    color: hd.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Their name and direct number appear here the moment "
                  "they're assigned.",
                  style: MtTextStyles.bodySm.copyWith(color: hd.body),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
