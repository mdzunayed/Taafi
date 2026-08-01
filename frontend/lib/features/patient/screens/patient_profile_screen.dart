import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/models/patient_profile.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import 'patient_history_screen.dart';

/// AsyncNotifier backing the Patient Profile screen.
///
/// Fetch lifecycle:
///   • `build()` calls `GET /patient/profile?account_id=<currentUser.id>`.
///   • [refresh] re-runs the GET (used by the AppBar refresh action).
///   • [update] applies a partial PATCH and swaps in the server's
///     authoritative copy on success. Optimistic-update is NOT used here
///     because the profile screen is rarely visited and the user
///     explicitly taps Save — a 250 ms spinner is the better UX trade.
class PatientProfileNotifier extends AutoDisposeAsyncNotifier<PatientProfile> {
  @override
  Future<PatientProfile> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      throw StateError('Not signed in');
    }
    return ref.read(dioClientProvider).getPatientProfile(user.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('Not signed in');
      return ref.read(dioClientProvider).getPatientProfile(user.id);
    });
  }

  /// Partial update. [updates] is a snake_case map of only the fields the
  /// user edited — `{full_name, email, phone}` or any subset. Throws on
  /// network / validation failure so the calling sheet can surface a
  /// SnackBar without altering the cached state.
  ///
  /// Named `save` (not `update`) to avoid clashing with the base
  /// `AsyncNotifierBase.update(transformer)` signature.
  Future<PatientProfile> save(Map<String, dynamic> updates) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Not signed in');
    final fresh =
        await ref.read(dioClientProvider).updatePatientProfile(user.id, updates);
    state = AsyncData(fresh);
    return fresh;
  }
}

final patientProfileProvider = AsyncNotifierProvider.autoDispose<
    PatientProfileNotifier, PatientProfile>(PatientProfileNotifier.new);

class PatientProfileScreen extends ConsumerWidget {
  const PatientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientProfileProvider);

    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MtColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('My profile', style: MtTextStyles.h3),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: MtColors.ink3),
            onPressed: () =>
                ref.read(patientProfileProvider.notifier).refresh(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MtColors.brand),
        ),
        error: (e, _) => _ProfileError(
          message: e.toString(),
          onRetry: () =>
              ref.read(patientProfileProvider.notifier).refresh(),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ProfileError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: MtColors.ink3),
            const SizedBox(height: 12),
            Text('Could not load profile',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 16),
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

class _ProfileBody extends ConsumerWidget {
  final PatientProfile profile;
  const _ProfileBody({required this.profile});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign out?', style: MtTextStyles.h3),
        content: Text(
          "You'll need to sign in again to check your active request and bookings.",
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: Text('Sign out', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  Future<void> _onEdit(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: MtColors.completed,
        ),
      );
    }
  }

  Future<void> _onContactSupport(BuildContext context) async {
    final uri =
        Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Call ${SupportConfig.supportPhoneDisplay}',
        )),
      );
    }
  }

  void _onPastRequests(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PatientHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () => ref.read(patientProfileProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ProfileHeader(profile: profile),
          const SizedBox(height: 20),
          _DetailsCard(profile: profile, onEdit: () => _onEdit(context, ref)),
          const SizedBox(height: 20),
          _SectionLabel('Account'),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.history,
            iconColor: MtColors.brand,
            label: 'View past requests',
            subtitle: 'Completed and cancelled visits',
            onTap: () => _onPastRequests(context),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.support_agent,
            iconColor: MtColors.brand,
            label: 'Contact support',
            subtitle: SupportConfig.supportPhoneDisplay,
            onTap: () => _onContactSupport(context),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.logout,
            iconColor: MtColors.rejected,
            label: 'Log out',
            subtitle: 'Sign out of this device',
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final PatientProfile profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final memberSince = profile.createdAt == null
        ? null
        : 'Member since ${DateFormat('MMM y').format(profile.createdAt!)}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          InitialsAvatar(
            name: profile.fullName.isEmpty ? 'Patient' : profile.fullName,
            size: 64,
            backgroundColor: MtColors.brandSoft,
            textColor: MtColors.brand,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.fullName.isEmpty ? 'Patient' : profile.fullName,
                        style: MtTextStyles.h2.copyWith(color: MtColors.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(active: profile.isActive),
                  ],
                ),
                if (profile.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.email,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (memberSince != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    memberSince,
                    style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;
  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final fg = active ? MtColors.completed : MtColors.ink3;
    final bg = active ? MtColors.completedBg : MtColors.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        active ? 'ACTIVE' : 'INACTIVE',
        style: MtTextStyles.labelSm.copyWith(color: fg, fontSize: 9),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final PatientProfile profile;
  final VoidCallback onEdit;
  const _DetailsCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Contact details', style: MtTextStyles.labelLg),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text('Edit', style: MtTextStyles.labelMd),
                  style: TextButton.styleFrom(
                    foregroundColor: MtColors.brand,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Full name',
            value: profile.fullName.isEmpty ? '—' : profile.fullName,
          ),
          const Divider(height: 1, color: MtColors.line, indent: 56),
          _DetailRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email.isEmpty ? '—' : profile.email,
          ),
          const Divider(height: 1, color: MtColors.line, indent: 56),
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: profile.phone.isEmpty ? '—' : profile.phone,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: MtColors.brand, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: MtTextStyles.sectionLabel.copyWith(
          color: MtColors.ink3,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: MtTextStyles.labelLg),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: MtColors.ink3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit profile sheet
// ---------------------------------------------------------------------------

class _EditProfileSheet extends ConsumerStatefulWidget {
  final PatientProfile profile;
  const _EditProfileSheet({required this.profile});

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _email = TextEditingController(text: widget.profile.email);
    _phone = TextEditingController(text: widget.profile.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Build a sparse patch: only the fields that actually changed. Sending
  /// the whole form would defeat the point of the partial-update backend
  /// and risks overwriting fields the user never touched.
  Map<String, dynamic> _diff() {
    final out = <String, dynamic>{};
    final newName = _name.text.trim();
    final newEmail = _email.text.trim();
    final newPhone = _phone.text.trim();
    if (newName != widget.profile.fullName) out['full_name'] = newName;
    if (newEmail != widget.profile.email) out['email'] = newEmail;
    if (newPhone != widget.profile.phone) out['phone'] = newPhone;
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final updates = _diff();
    if (updates.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(patientProfileProvider.notifier).save(updates);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MtColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Edit profile',
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _name,
                    label: 'Full name',
                    icon: Icons.person_outline,
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'Full name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProfileTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Email is required';
                      if (!value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProfileTextField(
                    controller: _phone,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      _saving ? 'Saving…' : 'Save changes',
                      style:
                          MtTextStyles.labelLg.copyWith(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MtColors.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          MtColors.brand.withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        labelText: label,
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
      ),
    );
  }
}
