import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/mt_colors.dart';
import '../../core/theme/mt_text_styles.dart';
import '../doctor/providers/profile_completion_provider.dart';
import '../doctor/screens/edit_credentials_screen.dart';
import 'doctor_prescription_screen.dart';

/// Single entry point for the "Write Prescription" action, shared by
/// every surface that lets a doctor author a script (the dashboard
/// appointment card and the active-care console).
///
/// Gates on profile completeness: a doctor can only issue a prescription
/// once their pad-header credentials (name, degrees, hospital, BMDC
/// registration) are on file — the same rule the backend enforces with a
/// 400 on `POST /api/prescriptions`. When credentials are missing we show
/// a "Profile Setup Required" dialog that routes to [EditCredentialsScreen]
/// instead of opening the form.
///
/// Returns the [DoctorPrescriptionScreen] result (`true` when a script was
/// issued) so callers relying on that contract keep working; returns
/// `null` when the gate blocked navigation.
Future<bool?> openPrescriptionFlow(
  BuildContext context,
  WidgetRef ref, {
  required String appointmentId,
  String? patientAccountId,
  String? patientName,
  String? careType,
  int? patientAge,
  String? patientGender,
}) async {
  bool complete;
  try {
    final status = await ref.read(profileCompletionProvider.future);
    complete = status.credentialsComplete;
  } catch (_) {
    // If the status can't be fetched, don't block the doctor — the
    // backend gate remains the authority and will reject with a 400.
    complete = true;
  }
  if (!context.mounted) return null;

  if (!complete) {
    final goToSetup = await _showSetupRequiredDialog(context);
    if (goToSetup == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const EditCredentialsScreen()),
      );
    }
    return null;
  }

  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => DoctorPrescriptionScreen(
        appointmentId: appointmentId,
        patientAccountId: patientAccountId,
        patientName: patientName,
        careType: careType,
        patientAge: patientAge,
        patientGender: patientGender,
      ),
    ),
  );
}

Future<bool?> _showSetupRequiredDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MtColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          const Icon(Icons.assignment_ind_outlined,
              color: MtColors.brand, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Profile Setup Required',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          ),
        ],
      ),
      content: Text(
        'Please add your degrees, college/hospital, and registration '
        'number in your profile before writing prescriptions.',
        style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(foregroundColor: MtColors.ink3),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: MtColors.brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Complete profile'),
        ),
      ],
    ),
  );
}
