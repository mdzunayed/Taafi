import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_provision_result.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../auth/auth_provider.dart';

/// Admin-only provisioning surface for new doctors and nurses. The
/// backend rail is `POST /api/admin/create-provider`, gated by the
/// `requireRole('admin')` middleware — only an authenticated admin
/// session can reach the endpoint, and the screen itself is mounted
/// inside the admin shell so anonymous visitors are bounced by the
/// router redirect before they get here.
///
/// On a successful response the temporary password is shown ONCE
/// inside a dedicated card with a [Clipboard.setData] copy button —
/// the plaintext value never round-trips again, so the admin has to
/// stash it or read it aloud at that moment.
class AddProviderScreen extends ConsumerStatefulWidget {
  const AddProviderScreen({super.key});

  @override
  ConsumerState<AddProviderScreen> createState() =>
      _AddProviderScreenState();
}

class _AddProviderScreenState extends ConsumerState<AddProviderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  UserRole _role = UserRole.doctor;
  bool _busy = false;
  AdminProvisionResult? _result;

  /// Maximum content width so the form stays readable on wide
  /// desktop / web viewports instead of stretching across the screen.
  static const double _maxContentWidth = 720;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref.read(dioClientProvider).createProvider(
            fullName: _nameCtrl.text,
            email: _emailCtrl.text,
            phone: _phoneCtrl.text,
            role: _role,
          );
      if (!mounted) return;
      setState(() => _result = result);
      _resetForm();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't create account: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetForm() {
    _nameCtrl.clear();
    _emailCtrl.clear();
    _phoneCtrl.clear();
    _formKey.currentState?.reset();
    setState(() => _role = UserRole.doctor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Provision provider'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _IntroBanner(),
                  const SizedBox(height: 16),
                  _FormCard(
                    formKey: _formKey,
                    nameCtrl: _nameCtrl,
                    emailCtrl: _emailCtrl,
                    phoneCtrl: _phoneCtrl,
                    role: _role,
                    onRoleChanged: (r) => setState(() => _role = r),
                    busy: _busy,
                    onSubmit: _submit,
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 18),
                    _CopyCredentialsCard(result: _result!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intro banner
// ---------------------------------------------------------------------------

class _IntroBanner extends StatelessWidget {
  const _IntroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.brandSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: MtColors.brand,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin-only provisioning',
                  style: MtTextStyles.labelLg
                      .copyWith(color: MtColors.ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Doctors and nurses cannot self-register. Fill in the form below to mint a new account; the system returns a one-shot temporary password the new hire uses to set their own credential on first sign-in.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form card
// ---------------------------------------------------------------------------

class _FormCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final UserRole role;
  final ValueChanged<UserRole> onRoleChanged;
  final bool busy;
  final Future<void> Function() onSubmit;

  const _FormCard({
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.role,
    required this.onRoleChanged,
    required this.busy,
    required this.onSubmit,
  });

  String? _validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Full name is required';
    if (s.length < 2) return 'Name is too short';
    return null;
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _validatePhone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Phone is required';
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 'Enter a complete phone number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Form(
        key: formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoleDropdown(role: role, onChanged: onRoleChanged),
                const SizedBox(height: 16),
                if (twoColumn)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LabeledField(
                          label: 'Full name',
                          child: TextFormField(
                            controller: nameCtrl,
                            decoration: _decoration('e.g. Dr. Nafisa Rahman'),
                            validator: _validateName,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _LabeledField(
                          label: 'Email',
                          child: TextFormField(
                            controller: emailCtrl,
                            decoration: _decoration('name@taafi.app'),
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                            autocorrect: false,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _LabeledField(
                    label: 'Full name',
                    child: TextFormField(
                      controller: nameCtrl,
                      decoration: _decoration('e.g. Dr. Nafisa Rahman'),
                      validator: _validateName,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LabeledField(
                    label: 'Email',
                    child: TextFormField(
                      controller: emailCtrl,
                      decoration: _decoration('name@taafi.app'),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      autocorrect: false,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Mobile phone',
                  child: TextFormField(
                    controller: phoneCtrl,
                    decoration: _decoration('+8801XXXXXXXXX'),
                    keyboardType: TextInputType.phone,
                    validator: _validatePhone,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : () => onSubmit(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MtColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(
                      busy ? 'Creating account…' : 'Create provider account',
                      style:
                          MtTextStyles.labelLg.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
      filled: true,
      fillColor: MtColors.surface2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MtTextStyles.labelMd.copyWith(
            color: MtColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  final UserRole role;
  final ValueChanged<UserRole> onChanged;
  const _RoleDropdown({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _LabeledField(
      label: 'Provider role',
      child: Container(
        decoration: BoxDecoration(
          color: MtColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MtColors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<UserRole>(
            value: role,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, color: MtColors.ink2),
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
            borderRadius: BorderRadius.circular(12),
            items: const [
              DropdownMenuItem(
                value: UserRole.doctor,
                child: _RoleOption(
                  icon: Icons.medical_services_outlined,
                  label: 'Doctor',
                ),
              ),
              DropdownMenuItem(
                value: UserRole.nurse,
                child: _RoleOption(
                  icon: Icons.medical_information_outlined,
                  label: 'Nurse',
                ),
              ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RoleOption({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: MtColors.brandSofter,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: MtColors.brand),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Temporary-credentials card (success state)
// ---------------------------------------------------------------------------

class _CopyCredentialsCard extends StatefulWidget {
  final AdminProvisionResult result;
  const _CopyCredentialsCard({required this.result});

  @override
  State<_CopyCredentialsCard> createState() => _CopyCredentialsCardState();
}

class _CopyCredentialsCardState extends State<_CopyCredentialsCard> {
  bool _copied = false;

  String get _credentialsBlock {
    final r = widget.result;
    return [
      'Name: ${r.account.name}',
      if (r.account.email.isNotEmpty) 'Email: ${r.account.email}',
      'Phone: ${r.account.phone}',
      'Role: ${r.account.role.toString().split('.').last}',
      'Temporary password: ${r.temporaryPassword}',
    ].join('\n');
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _credentialsBlock));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credentials copied to clipboard.')),
    );
  }

  Future<void> _copyPasswordOnly() async {
    await Clipboard.setData(
      ClipboardData(text: widget.result.temporaryPassword),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Temporary password copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.brand, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: MtColors.brand.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: MtColors.brand,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${r.account.role.toString().split('.').last[0].toUpperCase()}${r.account.role.toString().split('.').last.substring(1)} provisioned',
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Share these credentials securely with the new hire. The temporary password is shown only once — make sure to copy it now.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
          ),
          const SizedBox(height: 14),
          _CredentialRow(label: 'Name', value: r.account.name),
          if (r.account.email.isNotEmpty)
            _CredentialRow(label: 'Email', value: r.account.email),
          _CredentialRow(label: 'Phone', value: r.account.phone),
          _CredentialRow(
            label: 'Temporary password',
            value: r.temporaryPassword,
            mono: true,
            highlight: true,
            trailing: IconButton(
              tooltip: 'Copy password',
              onPressed: _copyPasswordOnly,
              icon: const Icon(
                Icons.copy_outlined,
                color: MtColors.brand,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _copyAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: _copied ? MtColors.completed : MtColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                _copied ? Icons.check : Icons.copy_all,
                size: 18,
              ),
              label: Text(
                _copied ? 'Credentials copied' : 'Copy credentials',
                style: MtTextStyles.labelLg.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool highlight;
  final Widget? trailing;
  const _CredentialRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.highlight = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: highlight ? MtColors.brandSofter : MtColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? MtColors.brandSoft : MtColors.line,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: MtTextStyles.bodySm.copyWith(
                  color: MtColors.ink2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: (mono
                        ? const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          )
                        : MtTextStyles.labelMd)
                    .copyWith(color: MtColors.ink),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
