import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/admin_settings.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../auth/auth_provider.dart';
import 'admin_table_chrome.dart';

/// Backend-backed platform settings. Replaces the former SharedPreferences-only
/// store: reads/writes `GET|PUT /api/admin/settings` so toggles, operational
/// hours, and the patient notice actually persist server-side.
class _SettingsNotifier extends AsyncNotifier<AdminSettings> {
  @override
  Future<AdminSettings> build() {
    return ref.read(dioClientProvider).getAdminSettings();
  }

  Future<void> _update(AdminSettings next) async {
    final prev = state.valueOrNull;
    state = AsyncData(next); // optimistic
    try {
      final saved = await ref.read(dioClientProvider).updateAdminSettings(next);
      state = AsyncData(saved);
    } catch (e) {
      if (prev != null) state = AsyncData(prev); // roll back on failure
      rethrow;
    }
  }

  AdminSettings get _current => state.valueOrNull ?? AdminSettings.empty;

  Future<void> setAutoAssign(bool v) =>
      _update(_current.copyWith(allowAutoAssignment: v));
  Future<void> setRequireVerified(bool v) =>
      _update(_current.copyWith(requireVerifiedDoctors: v));
  Future<void> setMaintenance(bool v) =>
      _update(_current.copyWith(maintenanceMode: v));
  Future<void> setBetaCharts(bool v) =>
      _update(_current.copyWith(betaCharts: v));
  Future<void> setOperationalHours(OperationalHours h) =>
      _update(_current.copyWith(operationalHours: h));
  Future<void> setSystemNotification(String s) =>
      _update(_current.copyWith(systemNotification: s));
}

final _settingsProvider =
    AsyncNotifierProvider<_SettingsNotifier, AdminSettings>(
        _SettingsNotifier.new);

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_settingsProvider);
    final notifier = ref.read(_settingsProvider.notifier);

    return AdminListScaffold(
      title: 'Settings',
      subtitle: 'Operational configuration for the Taafi platform',
      onRefresh: () async {
        ref.invalidate(_settingsProvider);
        await ref.read(_settingsProvider.future);
      },
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(_settingsProvider),
        ),
        data: (v) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: 'Dispatch',
              tiles: [
                _ToggleTile(
                  icon: Icons.bolt_outlined,
                  title: 'Allow auto-assignment',
                  subtitle:
                      'When ON, the matcher picks a doctor for low-urgency requests automatically.',
                  value: v.allowAutoAssignment,
                  onChanged: notifier.setAutoAssign,
                ),
                _ToggleTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Require verified doctors only',
                  subtitle:
                      'Pending-verification providers are hidden from the assign team picker.',
                  value: v.requireVerifiedDoctors,
                  onChanged: notifier.setRequireVerified,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _OperationalHoursSection(
              hours: v.operationalHours,
              onChanged: notifier.setOperationalHours,
            ),
            const SizedBox(height: 18),
            _SystemNoticeSection(
              value: v.systemNotification,
              onSave: notifier.setSystemNotification,
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'System',
              tiles: [
                _ToggleTile(
                  icon: Icons.construction_outlined,
                  title: 'Maintenance mode',
                  subtitle:
                      'Suspends patient-facing request submission with a notice banner.',
                  value: v.maintenanceMode,
                  onChanged: notifier.setMaintenance,
                  danger: true,
                ),
                _ToggleTile(
                  icon: Icons.insights_outlined,
                  title: 'Beta charts',
                  subtitle:
                      'Enables experimental visualizations on the Overview tab.',
                  value: v.betaCharts,
                  onChanged: notifier.setBetaCharts,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _AdminAccessSection(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Operational hours
// ---------------------------------------------------------------------------

const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const _weekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

class _OperationalHoursSection extends StatelessWidget {
  final OperationalHours hours;
  final ValueChanged<OperationalHours> onChanged;
  const _OperationalHoursSection({
    required this.hours,
    required this.onChanged,
  });

  TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(BuildContext context, bool isOpen) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(isOpen ? hours.open : hours.close),
    );
    if (picked == null) return;
    onChanged(isOpen
        ? hours.copyWith(open: _fmt(picked))
        : hours.copyWith(close: _fmt(picked)));
  }

  void _toggleDay(int day) {
    final days = List<int>.from(hours.days);
    if (days.contains(day)) {
      days.remove(day);
    } else {
      days.add(day);
    }
    days.sort();
    onChanged(hours.copyWith(days: days));
  }

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OPERATIONAL HOURS',
                style: MtTextStyles.labelSm
                    .copyWith(color: MtColors.ink3, letterSpacing: 0.9)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Opens',
                    value: hours.open,
                    onTap: () => _pick(context, true),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _TimeField(
                    label: 'Closes',
                    value: hours.close,
                    onTap: () => _pick(context, false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Operating days',
                style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int d = 0; d < 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: _weekdayNames[d],
                      child: _DayToggle(
                        label: _weekdayLabels[d],
                        selected: hours.days.contains(d),
                        onTap: () => _toggleDay(d),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value,
                style:
                    MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
            const Icon(Icons.schedule, size: 18, color: MtColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? MtColors.brand : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? MtColors.brand : MtColors.line),
        ),
        child: Text(label,
            style: MtTextStyles.labelMd.copyWith(
              color: selected ? Colors.white : MtColors.ink3,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System notification banner
// ---------------------------------------------------------------------------

class _SystemNoticeSection extends StatefulWidget {
  final String value;
  final ValueChanged<String> onSave;
  const _SystemNoticeSection({required this.value, required this.onSave});

  @override
  State<_SystemNoticeSection> createState() => _SystemNoticeSectionState();
}

class _SystemNoticeSectionState extends State<_SystemNoticeSection> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SystemNoticeSection old) {
    super.didUpdateWidget(old);
    // Keep the field in sync if the server value changed and the user hasn't
    // diverged from the previous server value.
    if (old.value != widget.value && _ctrl.text == old.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _ctrl.text.trim() != widget.value.trim();
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PATIENT SYSTEM NOTICE',
                style: MtTextStyles.labelSm
                    .copyWith(color: MtColors.ink3, letterSpacing: 0.9)),
            const SizedBox(height: 6),
            Text(
                'Shown as a banner in the patient app. Leave empty to hide it.',
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 2,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g. Service is limited today due to weather.',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: dirty
                    ? () => widget.onSave(_ctrl.text.trim())
                    : null,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text('Save notice',
                    style:
                        MtTextStyles.labelMd.copyWith(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MtColors.ink3.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-admin onboarding
// ---------------------------------------------------------------------------

class _AdminAccessSection extends StatelessWidget {
  const _AdminAccessSection();

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'ADMINISTRATION',
              style: MtTextStyles.labelSm
                  .copyWith(color: MtColors.ink3, letterSpacing: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 16, 18),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MtColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_outlined,
                      color: MtColors.brand, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Onboard new admin',
                          style: MtTextStyles.labelLg
                              .copyWith(color: MtColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        'Securely grant a colleague secondary admin access. Requires your verified admin session.',
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const _OnboardAdminDialog(),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text('Onboard New Admin',
                      style:
                          MtTextStyles.labelLg.copyWith(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MtColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Secure onboarding modal — captures the new admin's identity and a
/// password that must be typed twice. Submit is gated on a matching
/// double-confirmation to prevent spoofing/typos before the account is
/// minted with `role: 'admin'`.
class _OnboardAdminDialog extends ConsumerStatefulWidget {
  const _OnboardAdminDialog();

  @override
  ConsumerState<_OnboardAdminDialog> createState() =>
      _OnboardAdminDialogState();
}

class _OnboardAdminDialogState extends ConsumerState<_OnboardAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(dioClientProvider).registerSubAdmin(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim(),
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Admin "${_name.text.trim()}" onboarded.'),
        backgroundColor: MtColors.completed,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not onboard admin: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MtColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                        child: const Icon(Icons.admin_panel_settings_outlined,
                            color: MtColors.brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Onboard New Admin',
                            style: MtTextStyles.h3.copyWith(
                                color: MtColors.ink,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _OnboardField(
                    controller: _name,
                    label: 'Full name',
                    hint: 'Tania Akter',
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _email,
                    label: 'Email',
                    hint: 'admin@taafi.app',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Email is required';
                      if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(s)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _phone,
                    label: 'Phone (optional)',
                    hint: '+8801…',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _password,
                    label: 'Password',
                    hint: 'At least 8 characters',
                    obscure: _obscure,
                    trailing: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: MtColors.ink3,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) => (v ?? '').length < 8
                        ? 'Use at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _OnboardField(
                    controller: _confirm,
                    label: 'Confirm password',
                    hint: 'Re-enter the password',
                    obscure: _obscure,
                    validator: (v) => v != _password.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                            foregroundColor: MtColors.ink2),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MtColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(_busy ? 'Creating…' : 'Create admin',
                            style: MtTextStyles.labelLg
                                .copyWith(color: Colors.white)),
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

class _OnboardField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _OnboardField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.trailing,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: MtTextStyles.labelMd.copyWith(
                color: MtColors.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          validator: validator,
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
            suffixIcon: trailing,
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
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const _Section({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              title.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.9,
              ),
            ),
          ),
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: MtColors.line),
            tiles[i],
          ],
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool danger;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? MtColors.rejected : MtColors.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: MtTextStyles.labelLg
                        .copyWith(color: MtColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: accent,
          ),
        ],
      ),
    );
  }
}
