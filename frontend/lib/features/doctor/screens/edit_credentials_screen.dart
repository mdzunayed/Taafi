import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/doctor_profile.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../providers/profile_completion_provider.dart';
import 'doctor_profile_screen.dart';

/// Full-page editor for the doctor's clinical credentials — the six
/// fields frozen onto every prescription's pad header.
///
/// The four starred fields (name, degrees, hospital/college, BMDC
/// registration) are required: the backend refuses to issue a script
/// until they're all on file (see `credentialsComplete` in
/// `utils/doctorView.js`), and the "Write Prescription" gate pushes here
/// when they're missing. Specialization and email are optional.
///
/// Prefills from [doctorProfileProvider]; saves through
/// `updateProfessionalDetails` (→ `PUT /api/users/:id/profile`) and then
/// refreshes [profileCompletionProvider] so the gate re-opens within the
/// same session.
class EditCredentialsScreen extends ConsumerWidget {
  const EditCredentialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorProfileProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: Text(
          'Clinical Credentials',
          style: MtTextStyles.h3.copyWith(color: MtColors.ink),
        ),
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MtColors.brand),
        ),
        error: (e, _) => _ErrorBody(
          message: _friendlyError(e),
          onRetry: () => ref.read(doctorProfileProvider.notifier).refresh(),
        ),
        data: (profile) => _CredentialsForm(profile: profile),
      ),
    );
  }
}

class _CredentialsForm extends ConsumerStatefulWidget {
  final DoctorProfile profile;
  const _CredentialsForm({required this.profile});

  @override
  ConsumerState<_CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends ConsumerState<_CredentialsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _degrees;
  late final TextEditingController _hospital;
  late final TextEditingController _bmdc;
  late final TextEditingController _specialization;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _fullName = TextEditingController(text: p.fullName);
    _degrees = TextEditingController(text: p.degrees);
    _hospital = TextEditingController(text: p.hospitalAffiliation);
    _bmdc = TextEditingController(text: p.bmdcLicense);
    _specialization = TextEditingController(text: p.specialization);
    _email = TextEditingController(text: p.email);
  }

  @override
  void dispose() {
    _fullName.dispose();
    _degrees.dispose();
    _hospital.dispose();
    _bmdc.dispose();
    _specialization.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Snake_case keys, matching the convention used by the existing
      // doctor edit flows. `updateProfessionalDetails` writes to the
      // Provider row and swaps the fresh profile into state.
      await ref.read(doctorProfileProvider.notifier).updateProfessionalDetails({
        'full_name': _fullName.text.trim(),
        'degrees': _degrees.text.trim(),
        'hospital_affiliation': _hospital.text.trim(),
        'bmdc_license': _bmdc.text.trim(),
        'specialization': _specialization.text.trim(),
        'email': _email.text.trim(),
      });
      // Keep the completion checklist / prescription gate in lockstep.
      await ref.read(profileCompletionProvider.notifier).refresh();
      if (!mounted) return;
      _snack('Credentials saved', success: true);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _snack(_friendlyError(e), danger: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool success = false, bool danger = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger
            ? MtColors.rejected
            : success
                ? MtColors.completed
                : MtColors.ink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'These details are printed on every prescription you issue. '
            'Complete the required fields (*) to unlock prescription writing.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 20),
          _CredField(
            controller: _fullName,
            label: 'Full Name *',
            icon: Icons.person_outline,
            hint: 'Dr. Rahim Uddin',
            validator: _required,
          ),
          const SizedBox(height: 14),
          _CredField(
            controller: _degrees,
            label: 'Degrees / Qualifications *',
            icon: Icons.school_outlined,
            hint: 'M.B.B.S., M.D. (Internal Medicine)',
            validator: _required,
          ),
          const SizedBox(height: 14),
          _CredField(
            controller: _hospital,
            label: 'College / Hospital *',
            icon: Icons.local_hospital_outlined,
            hint: 'Dhaka Medical College & Hospital',
            validator: _required,
          ),
          const SizedBox(height: 14),
          _CredField(
            controller: _bmdc,
            label: 'BMDC Registration Number *',
            icon: Icons.badge_outlined,
            hint: 'A-12345',
            validator: _required,
          ),
          const SizedBox(height: 14),
          _CredField(
            controller: _specialization,
            label: 'Specialization',
            icon: Icons.medical_services_outlined,
            hint: 'General Physician',
          ),
          const SizedBox(height: 14),
          _CredField(
            controller: _email,
            label: 'Email Address',
            icon: Icons.email_outlined,
            hint: 'doctor@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MtColors.brand.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Save credentials',
                    style: MtTextStyles.labelLg.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// Styled credential input — mirrors `_DoctorTextField` in
/// `doctor_profile_screen.dart` (that one is file-private). The default
/// `errorBorder` turns the outline red when [validator] fails.
class _CredField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _CredField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: MtTextStyles.labelMd.copyWith(color: MtColors.ink3),
        labelStyle: MtTextStyles.labelMd.copyWith(color: MtColors.ink3),
        prefixIcon: Icon(icon, color: MtColors.ink3, size: 18),
        filled: true,
        fillColor: MtColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.rejected),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.rejected, width: 1.5),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: MtColors.ink3),
            const SizedBox(height: 8),
            Text('Could not load your profile',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyError(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
