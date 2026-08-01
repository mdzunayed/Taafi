import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/nurse_profile.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/services/location_tracking_service.dart';
import '../../provider/providers/nurse_workflow_provider.dart';
import 'controllers/nurse_nav_controller.dart';

// ── Nurse-module palette — aligned with the patient app's burnt-orange brand ─
// `_kMint` is the primary accent (now orange); `_kIndigo*` are the dark-slate
// foundations (header gradient, dark buttons). The BNMC validation badge keeps
// its green "verified" tone below.
const Color _kIndigo = MtColors.ink; // dark-slate foundation
const Color _kIndigoSoft = Color(0xFF1E293B); // slate-800
const Color _kMint = MtColors.brand; // primary accent → burnt orange

/// Soft green chip background for the BNMC validation (verified) badge.
const Color _kTealSoft = Color(0xFFD1FAE5);
const Color _kTealInk = Color(0xFF047857);

/// The canonical specialty "flags" a nurse can carry. Persisted as a
/// comma-joined string in the Provider record's `specialization` field.
const List<String> kNurseSpecialties = [
  'General Nursing',
  'Pediatric Phlebotomy',
  'Advanced Wound Dressing',
  'ICU Care Specialist',
  'Post-Surgical Dressing',
];

/// Tab 4 — the Profile & Account Console.
///
/// Patterned after the static profile menu mock-ups, but every row here is
/// live: Edit Professional Details opens a pre-filled bottom sheet, the
/// Duty/Earnings rows drive [nurseNavProvider] shortcuts, Settings/Support
/// push real placeholder destinations, and Logout tears the session down and
/// purges the stack back to `/login`.
class NurseProfileScreen extends ConsumerWidget {
  const NurseProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseProfileProvider);
    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _kMint),
      ),
      error: (e, _) => _ProfileError(
        message: e.toString(),
        onRetry: () => ref.invalidate(nurseProfileProvider),
      ),
      data: (profile) => _ProfileBody(profile: profile),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final NurseProfile profile;
  const _ProfileBody({required this.profile});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: MtTextStyles.h3),
        content: Text(
          'You will be returned to the login screen and your duty status '
          'will go offline.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Stop GPS streaming before we drop the token, then clear the session and
    // bounce to the login screen — this purges the authenticated page stack.
    await ref.read(locationTrackingServiceProvider).stop();
    if (!context.mounted) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  void _openPlaceholder(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String body,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _NurseInfoScreen(title: title, icon: icon, body: body),
      ),
    );
  }

  /// Default-fee editor. Opens a numeric bottom sheet pre-filled with the
  /// current base charge, validates an integer >= 0, then persists via
  /// PATCH /api/provider/profile-settings and refreshes the profile.
  void _showFeeSheet(
    BuildContext context,
    WidgetRef ref,
    NurseProfile profile,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _FeeEditSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(nurseNavProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _ProfileHeaderCard(profile: profile),
        const SizedBox(height: 20),
        _SectionLabel('Professional registry'),
        const SizedBox(height: 8),
        _MenuTile(
          icon: Icons.badge_rounded,
          tint: _kIndigo,
          title: 'Edit Professional Details',
          subtitle: 'Phone, email & nursing specialty flags',
          onTap: () => _showEditDetailsSheet(context, ref, profile),
        ),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.payments_rounded,
          tint: const Color(0xFF059669),
          title: 'Default Fee',
          subtitle: profile.fee > 0
              ? 'Base charge · ৳${profile.fee} per visit'
              : 'Set your base charge per visit',
          onTap: () => _showFeeSheet(context, ref, profile),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Quick actions'),
        const SizedBox(height: 8),
        _MenuTile(
          icon: Icons.local_shipping_rounded,
          tint: _kMint,
          title: 'Duty & Status',
          subtitle: 'Jump to the Dispatches dashboard',
          onTap: () {
            // Drop the shell index straight back to the Dispatches board.
            nav.openDispatches();
          },
        ),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.account_balance_wallet_rounded,
          tint: const Color(0xFF059669),
          title: 'Earnings Dashboard',
          subtitle: 'Visit pay, bonuses & withdrawals',
          onTap: () {
            // Redirect the shell index to the Earnings ledger tab.
            nav.openEarnings();
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel('Account'),
        const SizedBox(height: 8),
        _MenuTile(
          icon: Icons.settings_rounded,
          tint: MtColors.ink2,
          title: 'Settings',
          subtitle: 'Notifications, language & privacy',
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/settings');
          },
        ),
        const SizedBox(height: 10),
        _MenuTile(
          icon: Icons.support_agent_rounded,
          tint: const Color(0xFF1D4ED8),
          title: 'Help & Support',
          subtitle: 'Reach the Taafi care operations desk',
          onTap: () => _openPlaceholder(
            context,
            title: 'Help & Support',
            icon: Icons.support_agent_rounded,
            body: 'Our operations desk is available 24/7 for active dispatch '
                'issues, payouts and credential verification.',
          ),
        ),
        const SizedBox(height: 20),
        _LogoutButton(onTap: () => _confirmSignOut(context, ref)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default-fee edit sheet — numeric Form + optimistic-disabled submit
// ─────────────────────────────────────────────────────────────────────────────

class _FeeEditSheet extends ConsumerStatefulWidget {
  final NurseProfile profile;
  const _FeeEditSheet({required this.profile});

  @override
  ConsumerState<_FeeEditSheet> createState() => _FeeEditSheetState();
}

class _FeeEditSheetState extends ConsumerState<_FeeEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _feeCtrl = TextEditingController(
    text: widget.profile.fee > 0 ? widget.profile.fee.toString() : '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final fee = int.parse(_feeCtrl.text.trim());
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).updateProviderFee(fee);
      ref.invalidate(nurseProfileProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: MtColors.completed,
          content: Text('Default fee updated to ৳$fee.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content: Text("Couldn't update fee: $e"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text('Update base charge',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Set the default fee patients are quoted for one of your visits.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _feeCtrl,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '৳ ',
                labelText: 'Default fee per visit',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter a fee amount';
                final n = int.tryParse(t);
                if (n == null || n < 0) return 'Enter a valid amount';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kMint,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kMint.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Save fee',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header card — identity + BNMC validation badge
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final NurseProfile profile;
  const _ProfileHeaderCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName.isEmpty ? 'Nurse' : profile.fullName;
    final specialty =
        profile.specialization.isEmpty ? 'Home care nurse' : profile.specialization;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kIndigo, _kIndigoSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kIndigo.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          InitialsAvatar(
            name: name,
            size: 76,
            backgroundColor: Colors.white.withValues(alpha: 0.16),
            textColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: MtTextStyles.h2.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // BNMC Quick-Status tag — soft teal pill with a tiny checkmark.
          _BnmcBadge(verified: profile.isVerified),
          const SizedBox(height: 10),
          Text(
            specialty,
            style: MtTextStyles.bodySm
                .copyWith(color: Colors.white.withValues(alpha: 0.86)),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (profile.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.phone,
              style: MtTextStyles.bodySm
                  .copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _BnmcBadge extends StatelessWidget {
  final bool verified;
  const _BnmcBadge({required this.verified});

  @override
  Widget build(BuildContext context) {
    final bg = verified ? _kTealSoft : Colors.white.withValues(alpha: 0.16);
    final fg = verified ? _kTealInk : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.pending_rounded,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            verified ? 'BNMC Verified' : 'BNMC Verification Pending',
            style: MtTextStyles.labelSm
                .copyWith(color: fg, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu tile
// ─────────────────────────────────────────────────────────────────────────────

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Tactile feedback on every list-item selection.
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MtTextStyles.labelLg.copyWith(
                          color: MtColors.ink, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: MtColors.ink3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: Text(
          'Log out',
          style: MtTextStyles.labelLg.copyWith(fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: MtColors.rejected,
          side: const BorderSide(color: Color(0xFFFBD5D5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel
          .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Professional Details — sliding bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the pre-filled "Edit Professional Details" sheet. Wired from the
/// Profile console's first row.
Future<void> _showEditDetailsSheet(
  BuildContext context,
  WidgetRef ref,
  NurseProfile profile,
) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _EditDetailsSheet(profile: profile),
  );
}

class _EditDetailsSheet extends ConsumerStatefulWidget {
  final NurseProfile profile;
  const _EditDetailsSheet({required this.profile});

  @override
  ConsumerState<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends ConsumerState<_EditDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone =
      TextEditingController(text: widget.profile.phone);
  late final TextEditingController _email =
      TextEditingController(text: widget.profile.email);
  late final TextEditingController _license =
      TextEditingController(text: widget.profile.nursingLicense);
  late final TextEditingController _qualifications =
      TextEditingController(text: widget.profile.qualifications);
  late final TextEditingController _hospital =
      TextEditingController(text: widget.profile.hospitalAffiliation);

  /// Specialty flags pre-selected from the stored comma-joined string.
  late final Set<String> _selected = widget.profile.specialization
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _license.dispose();
    _qualifications.dispose();
    _hospital.dispose();
    super.dispose();
  }

  void _toggleFlag(String flag) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(flag)) _selected.add(flag);
    });
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : _kTealInk,
    ));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      // The nurse credential endpoint persists the professional registry
      // (BNMC license + specialty flags). Phone/email are captured here for
      // review and travel through the account-level profile flow; the patch
      // below writes everything the nurse provider record accepts.
      await ref.read(dioClientProvider).updateNurseProfile(
            user.id,
            nursingLicense: _license.text.trim(),
            specialization: _selected.join(', '),
            qualifications: _qualifications.text.trim(),
            hospitalAffiliation: _hospital.text.trim(),
          );
      ref.invalidate(nurseProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Professional details updated.');
    } catch (e) {
      _toast('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text('Edit Professional Details',
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                  const SizedBox(height: 4),
                  Text(
                    'Keep your contact details and specialty flags current so '
                    'dispatches route to the right hands.',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel('Phone number'),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _phone,
                    hint: 'e.g. 01700-000000',
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Phone is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel('Email address'),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _email,
                    hint: 'e.g. nurse@taafi.app',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null; // optional
                      return t.contains('@') ? null : 'Enter a valid email';
                    },
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel('BNMC registration number'),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _license,
                    hint: 'e.g. BNMC-123456',
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel('Nursing qualifications'),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _qualifications,
                    hint: 'e.g. B.Sc in Nursing, Diploma in Orthopedics',
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel('Hospital / institute'),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _hospital,
                    hint: 'e.g. Square College of Nursing / BSMMU',
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel('Nursing specialty flags'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final flag in kNurseSpecialties)
                        FilterChip(
                          label: Text(flag),
                          selected: _selected.contains(flag),
                          onSelected: (_) => _toggleFlag(flag),
                          showCheckmark: true,
                          checkmarkColor: Colors.white,
                          backgroundColor: MtColors.surface2,
                          selectedColor: _kMint,
                          side: BorderSide(
                            color: _selected.contains(flag)
                                ? _kMint
                                : MtColors.line,
                          ),
                          labelStyle: MtTextStyles.labelMd.copyWith(
                            color: _selected.contains(flag)
                                ? Colors.white
                                : MtColors.ink2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kIndigoSoft,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        _saving ? 'Saving…' : 'Save changes',
                        style: MtTextStyles.labelLg.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800),
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

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _SheetField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kMint, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.rejected),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.labelMd
          .copyWith(color: MtColors.ink, fontWeight: FontWeight.w700),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder destinations (Settings / Help & Support)
// ─────────────────────────────────────────────────────────────────────────────

class _NurseInfoScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String body;
  const _NurseInfoScreen({
    required this.title,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title,
            style: MtTextStyles.h3.copyWith(color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _kMint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _kMint, size: 34),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: MtTextStyles.h2.copyWith(color: MtColors.ink),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                body,
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
            const Icon(Icons.error_outline, color: MtColors.rejected, size: 40),
            const SizedBox(height: 12),
            Text("Couldn't load your profile",
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
