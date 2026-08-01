import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/doctor_profile.dart';
import '../../../../core/models/provider_update_otp_dispatch.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../auth/auth_provider.dart';
import '../../admin_providers.dart';
import '../add_provider_screen.dart';
import 'admin_table_chrome.dart';

final _feeFmt = NumberFormat('#,###', 'en_US');

class ProvidersTab extends ConsumerWidget {
  const ProvidersTab({super.key});

  Future<void> _onEdit(
    BuildContext context,
    WidgetRef ref,
    DoctorProfile provider,
  ) async {
    final controller = ref.read(providerEditControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.requestOtp(provider.id);
    if (!ok) {
      final err = ref.read(providerEditControllerProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(content: Text(err ?? 'Could not dispatch the code.')),
      );
      return;
    }
    if (!context.mounted) return;
    final dispatch = ref.read(providerEditControllerProvider).dispatch;
    if (dispatch == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProviderUpdateOtpDialog(
        provider: provider,
        dispatch: dispatch,
      ),
    );
  }

  /// Instant verification toggle — flips PENDING ⇄ VERIFIED via a background
  /// PATCH, then refreshes the table so the status pill updates in place.
  Future<void> _onToggleVerify(
    BuildContext context,
    WidgetRef ref,
    DoctorProfile provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final goingVerified = !provider.isVerified;
    try {
      await ref.read(dioClientProvider).toggleProviderVerification(provider.id);
      ref.invalidate(adminProvidersListProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(
          goingVerified
              ? '${provider.fullName} is now VERIFIED.'
              : '${provider.fullName} set back to PENDING.',
        ),
        backgroundColor: goingVerified ? MtColors.completed : MtColors.ink,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update verification: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminProvidersListProvider);
    final editState = ref.watch(providerEditControllerProvider);

    // Watch for errors coming out of the controller so they SnackBar
    // exactly once (instead of every rebuild).
    ref.listen<ProviderEditState>(providerEditControllerProvider, (prev, next) {
      final newError = next.errorMessage;
      if (newError != null && newError != prev?.errorMessage) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(newError)));
      }
    });

    return AdminListScaffold(
      title: 'Providers',
      subtitle: 'Doctors and nurses available for dispatch',
      onRefresh: () async {
        ref.invalidate(adminProvidersListProvider);
        await ref.read(adminProvidersListProvider.future);
      },
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddProviderScreen(),
                      ),
                    );
                    ref.invalidate(adminProvidersListProvider);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MtColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(
                    'Add doctor / nurse',
                    style: MtTextStyles.labelLg.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => MtErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(adminProvidersListProvider),
                ),
                data: (rows) => rows.isEmpty
                    ? const AdminEmptyState(
                        icon: Icons.local_hospital_outlined,
                        title: 'No providers yet',
                        subtitle:
                            'Tap "Add doctor / nurse" above to mint the first provider account.',
                      )
                    : _ProvidersTable(
                        rows: rows,
                        onEdit: (p) => _onEdit(context, ref, p),
                        onToggleVerify: (p) => _onToggleVerify(context, ref, p),
                      ),
              ),
            ],
          ),
          // Loading barrier — covers the table only while the
          // request-OTP stage is in flight so the admin can't fire
          // it twice. The verification dialog has its own spinner.
          if (editState.isLoading && editState.dispatch == null)
            const Positioned.fill(child: _LoadingBarrier()),
        ],
      ),
    );
  }
}

class _LoadingBarrier extends StatelessWidget {
  const _LoadingBarrier();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.18),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: MtColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(MtColors.brand),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Dispatching verification code…',
                style: MtTextStyles.labelMd.copyWith(color: MtColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvidersTable extends StatelessWidget {
  final List<DoctorProfile> rows;
  final ValueChanged<DoctorProfile> onEdit;
  final ValueChanged<DoctorProfile> onToggleVerify;
  const _ProvidersTable({
    required this.rows,
    required this.onEdit,
    required this.onToggleVerify,
  });

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(MtColors.brandSofter),
          headingTextStyle: MtTextStyles.labelSm.copyWith(
            color: MtColors.ink3,
            letterSpacing: 0.8,
          ),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('NAME')),
            DataColumn(label: Text('PHONE')),
            DataColumn(label: Text('SPECIALIZATION')),
            DataColumn(label: Text('FEE'), numeric: true),
            DataColumn(label: Text('VERIFIED')),
            DataColumn(label: Text('AVAILABILITY')),
            DataColumn(label: Text('JOINED')),
            DataColumn(label: Text('EDIT')),
          ],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(_NameCell(name: p.fullName, role: p.role)),
                DataCell(Text(p.phone.isEmpty ? '—' : p.phone,
                    style: MtTextStyles.bodyMd
                        .copyWith(color: MtColors.ink2))),
                DataCell(Text(
                    p.specialization.isEmpty ? '—' : p.specialization,
                    style: MtTextStyles.bodyMd
                        .copyWith(color: MtColors.ink2))),
                DataCell(Text('৳${_feeFmt.format(p.fee.round())}',
                    style: MtTextStyles.labelMd
                        .copyWith(color: MtColors.ink))),
                DataCell(_StatusPill(
                  label: p.verificationStatus.toUpperCase(),
                  fg: p.isVerified ? MtColors.completed : MtColors.pending,
                  bg: p.isVerified
                      ? MtColors.completedBg
                      : MtColors.pendingBg,
                )),
                DataCell(_StatusPill(
                  label: p.availabilityStatus.toUpperCase(),
                  fg: p.isOnline ? MtColors.completed : MtColors.ink3,
                  bg: p.isOnline ? MtColors.completedBg : MtColors.bg,
                )),
                DataCell(Text(
                    p.createdAt == null
                        ? '—'
                        : adminTableDate.format(p.createdAt!),
                    style: MtTextStyles.bodyMd
                        .copyWith(color: MtColors.ink2))),
                DataCell(
                  PopupMenuButton<String>(
                    tooltip: 'Manage provider',
                    icon: const Icon(Icons.more_horiz, color: MtColors.ink2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (value) {
                      if (value == 'edit') onEdit(p);
                      if (value == 'verify') onToggleVerify(p);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note,
                                size: 18, color: MtColors.brand),
                            const SizedBox(width: 10),
                            Text('Request OTP & edit',
                                style: MtTextStyles.labelMd
                                    .copyWith(color: MtColors.ink)),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'verify',
                        child: Row(
                          children: [
                            Icon(
                              p.isVerified
                                  ? Icons.cancel_outlined
                                  : Icons.verified_outlined,
                              size: 18,
                              color: p.isVerified
                                  ? MtColors.rejected
                                  : MtColors.completed,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              p.isVerified
                                  ? 'Set to Pending'
                                  : 'Mark Verified',
                              style: MtTextStyles.labelMd
                                  .copyWith(color: MtColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final String name;
  final String role;
  const _NameCell({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialsAvatar(
          name: name.replaceFirst('Dr. ', ''),
          size: 32,
          backgroundColor: MtColors.brandSoft,
          textColor: MtColors.brand,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
        ),
        const SizedBox(width: 8),
        _RoleBadge(role: role),
      ],
    );
  }
}

/// Visual taxonomy chip distinguishing doctors from nurses in the table.
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isNurse = role.toLowerCase() == 'nurse';
    final (label, fg, bg) = isNurse
        ? ('RN / Nurse', const Color(0xFF7C3AED), const Color(0xFFF5F3FF))
        : ('MD / Doctor', const Color(0xFF0D9488), const Color(0xFFCCFBF1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: MtTextStyles.labelSm
            .copyWith(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusPill({
    required this.label,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            MtTextStyles.labelSm.copyWith(color: fg, fontSize: 9),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2-Step OTP verification dialog
// ---------------------------------------------------------------------------

/// Modal that lets the admin patch a provider profile only after the
/// provider's registered device has confirmed the request via a
/// 6-digit OTP. Layout caps at 450 px wide so the dialog stays
/// compact on desktop/web. All editable fields seed from the live
/// [provider] row; on submit the controller PATCHes the changes
/// alongside the OTP through [ProviderEditController.commitUpdate].
class ProviderUpdateOtpDialog extends ConsumerStatefulWidget {
  final DoctorProfile provider;
  final ProviderUpdateOtpDispatch dispatch;

  const ProviderUpdateOtpDialog({
    super.key,
    required this.provider,
    required this.dispatch,
  });

  @override
  ConsumerState<ProviderUpdateOtpDialog> createState() =>
      _ProviderUpdateOtpDialogState();
}

class _ProviderUpdateOtpDialogState
    extends ConsumerState<ProviderUpdateOtpDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _specialtyCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _otpCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _nameCtrl = TextEditingController(text: p.fullName);
    _phoneCtrl = TextEditingController(text: p.phone);
    _specialtyCtrl = TextEditingController(text: p.specialization);
    _feeCtrl = TextEditingController(text: p.fee == 0 ? '' : p.fee.toString());
    _otpCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _specialtyCtrl.dispose();
    _feeCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  /// Build the partial-update payload — only fields the admin
  /// actually changed get sent. Empty / unchanged fields fall through
  /// so we don't blank-out values the admin didn't touch.
  Map<String, dynamic> _collectUpdates() {
    final p = widget.provider;
    final out = <String, dynamic>{};
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty && name != p.fullName) out['fullName'] = name;
    final phone = _phoneCtrl.text.trim();
    if (phone != p.phone) out['phone'] = phone;
    final specialty = _specialtyCtrl.text.trim();
    if (specialty != p.specialization) {
      out['specialization'] = specialty;
      out['specialty'] = specialty;
    }
    final feeText = _feeCtrl.text.trim();
    if (feeText.isNotEmpty) {
      final n = num.tryParse(feeText);
      if (n != null && n != p.fee) out['fee'] = n;
    }
    return out;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final otp = _otpCtrl.text.trim();
    final controller =
        ref.read(providerEditControllerProvider.notifier);
    final ok = await controller.commitUpdate(
      providerId: widget.provider.id,
      otp: otp,
      updates: _collectUpdates(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Provider "${widget.provider.fullName}" updated successfully.',
          ),
          backgroundColor: MtColors.completed,
        ),
      );
    }
    // Failures are surfaced by the listener in ProvidersTab — we keep
    // the dialog open so the admin can retype the code without
    // losing their field edits.
  }

  void _cancel() {
    ref.read(providerEditControllerProvider.notifier).cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editState = ref.watch(providerEditControllerProvider);
    final devOtp = widget.dispatch.devOtp;
    return Dialog(
      backgroundColor: MtColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: MtColors.brandSofter,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user_outlined,
                          color: MtColors.brand,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Provider Authorization Required',
                          style: MtTextStyles.h3.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "An access token was sent to the provider's registered device. Enter the code below to validate changes.",
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                  ),
                  if (devOtp != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: MtColors.brandSofter,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: MtColors.brandSoft),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bug_report_outlined,
                              size: 16, color: MtColors.brand),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Dev code: $devOtp',
                              style: MtTextStyles.labelMd.copyWith(
                                color: MtColors.brand,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _DialogLabel(label: 'Full name'),
                  const SizedBox(height: 6),
                  _DialogTextField(
                    controller: _nameCtrl,
                    hint: 'Dr. Nafisa Rahman',
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DialogLabel(label: 'Phone'),
                            const SizedBox(height: 6),
                            _DialogTextField(
                              controller: _phoneCtrl,
                              hint: '+8801…',
                              keyboardType: TextInputType.phone,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DialogLabel(label: 'Fee (BDT)'),
                            const SizedBox(height: 6),
                            _DialogTextField(
                              controller: _feeCtrl,
                              hint: '1500',
                              keyboardType: TextInputType.number,
                              validator: (raw) {
                                if ((raw ?? '').isEmpty) return null;
                                final n = num.tryParse(raw!);
                                if (n == null || n < 0) {
                                  return 'Enter a valid amount';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DialogLabel(label: 'Specialization'),
                  const SizedBox(height: 6),
                  _DialogTextField(
                    controller: _specialtyCtrl,
                    hint: 'General Surgery',
                  ),
                  const SizedBox(height: 18),
                  _DialogLabel(label: '6-digit verification code'),
                  const SizedBox(height: 6),
                  _OtpField(controller: _otpCtrl),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: editState.isLoading ? null : _cancel,
                        style: TextButton.styleFrom(
                          foregroundColor: MtColors.ink2,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: editState.isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MtColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: editState.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle_outline,
                                size: 18),
                        label: Text(
                          editState.isLoading
                              ? 'Verifying…'
                              : 'Verify & Save',
                          style: MtTextStyles.labelLg
                              .copyWith(color: Colors.white),
                        ),
                      ),
                    ],
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

class _DialogLabel extends StatelessWidget {
  final String label;
  const _DialogLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: MtTextStyles.labelMd.copyWith(
        color: MtColors.ink,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  const _DialogTextField({
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
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          borderSide: const BorderSide(color: MtColors.brand, width: 1.4),
        ),
      ),
    );
  }
}

/// Six structured boxes for the OTP entry. Backed by a single text
/// controller (so the form validator can read it as a normal field)
/// but visually rendered as discrete segments matching the spec.
class _OtpField extends StatefulWidget {
  final TextEditingController controller;
  const _OtpField({required this.controller});

  @override
  State<_OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<_OtpField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final ch = i < value.length ? value[i] : '';
              final filled = ch.isNotEmpty;
              final active = i == value.length && _focusNode.hasFocus;
              return _OtpBox(label: ch, filled: filled, active: active);
            }),
          ),
          // Invisible TextFormField driving the underlying value.
          // SizedBox.expand traps the gesture onto the segment row,
          // keeping the cursor pinned even though the field itself
          // is visually offscreen.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextFormField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(letterSpacing: 28),
                autofocus: true,
                buildCounter: (_, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) =>
                    null,
                validator: (raw) {
                  if ((raw ?? '').length != 6) {
                    return 'Enter the 6-digit code';
                  }
                  if (!RegExp(r'^\d{6}$').hasMatch(raw!)) {
                    return 'Digits only';
                  }
                  return null;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final String label;
  final bool filled;
  final bool active;
  const _OtpBox({
    required this.label,
    required this.filled,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? MtColors.brandSofter : MtColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? MtColors.brand
              : (filled ? MtColors.brandSoft : MtColors.line),
          width: active ? 1.8 : 1.0,
        ),
      ),
      child: Text(
        label,
        style: MtTextStyles.h2.copyWith(
          color: MtColors.ink,
          fontFeatures: const [],
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
