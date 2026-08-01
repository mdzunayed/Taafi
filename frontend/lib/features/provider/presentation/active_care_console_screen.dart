import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/doctor_dashboard.dart';
import '../../../core/models/patient_medical_vault.dart';
import '../../../core/models/prescription.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/age.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../shared/presentation/widgets/active_chat_drawer.dart';
import '../../prescriptions/prescription_entry.dart';
import '../../prescriptions/prescription_pad_actions.dart';
import '../providers/doctor_workflow_provider.dart';
import 'collect_cash_panel.dart';
import 'widgets/target_patient_panel.dart';

/// Phase 3 + 4 of the Doctor Operations Hub: a full-screen overlay that
/// gives the doctor absolute control of a live visit — patient intake +
/// medical vault, live chat / call utilities, and the prescription +
/// close-case engine. Launched from the Assignments tab once the visit is
/// `arrived` / `in_service`.
///
/// Layout cap: `Center → ConstrainedBox(maxWidth: 600)` so it stays
/// readable on desktop / web instead of stretching to monitor edges.
class ActiveCareConsoleScreen extends ConsumerStatefulWidget {
  final UpcomingAppointment appointment;
  const ActiveCareConsoleScreen({super.key, required this.appointment});

  @override
  ConsumerState<ActiveCareConsoleScreen> createState() =>
      _ActiveCareConsoleScreenState();
}

class _ActiveCareConsoleScreenState
    extends ConsumerState<ActiveCareConsoleScreen> {
  bool _finishing = false;

  UpcomingAppointment get _appt => widget.appointment;
  String get _accountId => _appt.patientAccountId ?? '';

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? MtColors.rejected : MtColors.completed,
      ),
    );
  }

  Future<void> _openChat() async {
    final me = ref.read(currentUserProvider);
    final patientId = _accountId;
    if (me == null || patientId.isEmpty || _appt.id.isEmpty) {
      _toast('Chat is not available for this visit yet', error: true);
      return;
    }
    // Slide-in communication drawer — text/image/location chat plus the
    // in-header "Call via Secure Line" masked-calling button.
    await openActiveChatDrawer(
      context,
      appointmentId: _appt.id,
      currentUserId: me.id,
      otherUserId: patientId,
      otherUserName: _appt.patientName,
      otherRoleLabel: 'Patient',
    );
  }

  Future<void> _emergencyCall() async {
    final phone = _appt.patientPhone;
    if (phone == null || phone.isEmpty) {
      _toast('Patient phone is not available yet', error: true);
      return;
    }
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok) _toast('No phone app available to place the call', error: true);
  }

  /// "Formulate Digital Prescription & Complete Visit": push the existing
  /// authoring form; if the doctor finalises a script (`pop(true)`), close
  /// the case — flip the visit to `completed` (which fires the socket
  /// event that locks the chat) and return to the hub with a banner.
  Future<void> _formulateAndComplete() async {
    // For a family-member booking the script is issued for the recipient —
    // pre-fill the pad with their name/age/sex, not the account holder's.
    final recipient = _appt.careRecipient;
    final issued = await openPrescriptionFlow(
      context,
      ref,
      appointmentId: _appt.id,
      patientAccountId: _accountId.isEmpty ? null : _accountId,
      patientName: recipient?.name ?? _appt.patientName,
      careType: _appt.serviceName,
      patientAge: recipient != null
          ? ageFromDob(recipient.dateOfBirth)
          : null,
      patientGender: recipient?.gender,
    );
    if (issued != true || !mounted) return;
    setState(() => _finishing = true);
    try {
      final updated =
          await ref.read(doctorWorkflowProvider).completeVisit(_appt.id);
      if (!mounted) return;
      _toast('Visit completed — prescription issued.');
      // Balance still unpaid → offer on-the-spot cash collection while
      // the doctor is still at the patient's door. No-op for visits
      // whose balance was already settled.
      await offerCashCollection(
        context,
        ref,
        appointment: updated,
        patientName: _appt.patientName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        _toast('Could not close the visit: $e', error: true);
      }
    }
  }

  Future<void> _editVault(PatientMedicalVault current) async {
    final me = ref.read(currentUserProvider);
    final updated = await showModalBottomSheet<PatientMedicalVault>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VaultEditorSheet(
        accountId: _accountId,
        editorId: me?.id ?? '',
        initial: current,
      ),
    );
    if (updated != null && mounted) {
      ref.invalidate(patientVaultProvider(_accountId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Clinical Care Console'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _PatientHeaderCard(appt: _appt),
                      if (_appt.isCashOnService) ...[
                        const SizedBox(height: 12),
                        const CashOnServiceBadge(),
                      ],
                      const SizedBox(height: 16),
                      _SectionLabel('Patient intake & medical vault'),
                      const SizedBox(height: 8),
                      _VaultGrid(
                        accountId: _accountId,
                        onEdit: _editVault,
                      ),
                      const SizedBox(height: 16),
                      _PrescriptionHistoryDisclosure(accountId: _accountId),
                      const SizedBox(height: 20),
                      _SectionLabel('Live synchronization utilities'),
                      const SizedBox(height: 8),
                      _SyncUtilitiesRow(
                        onChat: _openChat,
                        onCall: _emergencyCall,
                      ),
                    ],
                  ),
                ),
                _CompleteFooter(
                  busy: _finishing,
                  onTap: _formulateAndComplete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient header
// ---------------------------------------------------------------------------

class _PatientHeaderCard extends StatelessWidget {
  final UpcomingAppointment appt;
  const _PatientHeaderCard({required this.appt});

  @override
  Widget build(BuildContext context) {
    final address = appt.address;
    // When booked for a family member, the visit is FOR the recipient — show
    // them as the patient, with the account holder noted as who booked it.
    final recipient = appt.careRecipient;
    final displayName =
        recipient != null ? recipient.name : appt.patientName;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: displayName,
                size: 52,
                backgroundColor: const Color(0xFFFEF3C7),
                textColor: const Color(0xFF92400E),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recipient != null
                          ? '${appt.serviceName} · booked by ${appt.patientName}'
                          : appt.serviceName,
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (recipient != null) ...[
            const SizedBox(height: 12),
            TargetPatientPanel(recipient: recipient),
          ],
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: MtColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Medical vault grid
// ---------------------------------------------------------------------------

class _VaultGrid extends ConsumerWidget {
  final String accountId;
  final Future<void> Function(PatientMedicalVault) onEdit;
  const _VaultGrid({required this.accountId, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accountId.isEmpty) {
      return _VaultShell(
        onEdit: null,
        child: Text(
          'No patient account linked to this visit — vault unavailable.',
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
      );
    }
    final async = ref.watch(patientVaultProvider(accountId));
    return async.when(
      loading: () => _VaultShell(
        onEdit: null,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: MtColors.brand),
            ),
          ),
        ),
      ),
      error: (e, _) => _VaultShell(
        onEdit: () => onEdit(PatientMedicalVault.empty),
        child: Text(
          "Couldn't load the medical vault.",
          style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
        ),
      ),
      data: (vault) => _VaultShell(
        onEdit: () => onEdit(vault),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _VaultTile(
                    icon: Icons.bloodtype_outlined,
                    label: 'Blood type',
                    value: (vault.bloodType.isEmpty ||
                            vault.bloodType == 'Unknown')
                        ? null
                        : vault.bloodType,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VaultTile(
                    icon: Icons.warning_amber_rounded,
                    label: 'Allergies',
                    value: vault.allergies.isEmpty
                        ? null
                        : vault.allergies.join(', '),
                    danger: vault.allergies.isNotEmpty,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _VaultTile(
              icon: Icons.monitor_heart_outlined,
              label: 'Chronic conditions',
              value: vault.chronicConditions.isEmpty
                  ? null
                  : vault.chronicConditions.join(', '),
              wide: true,
            ),
            const SizedBox(height: 10),
            _VaultTile(
              icon: Icons.notes_outlined,
              label: 'Emergency notes',
              value: vault.emergencyNotes.trim().isEmpty
                  ? null
                  : vault.emergencyNotes.trim(),
              wide: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEdit;
  const _VaultShell({required this.child, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (onEdit != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('Edit medical info', style: MtTextStyles.labelMd),
                style: TextButton.styleFrom(foregroundColor: MtColors.brand),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VaultTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool wide;
  final bool danger;
  const _VaultTile({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    final accent = danger && hasValue ? MtColors.rejected : MtColors.ink3;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasValue ? value! : 'Not recorded',
            maxLines: wide ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.bodyMd.copyWith(
              color: hasValue
                  ? (danger ? MtColors.rejected : MtColors.ink)
                  : MtColors.ink3,
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Past prescription history disclosure
// ---------------------------------------------------------------------------

class _PrescriptionHistoryDisclosure extends ConsumerWidget {
  final String accountId;
  const _PrescriptionHistoryDisclosure({required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: const Icon(Icons.history, color: MtColors.brand, size: 20),
          title: Text(
            'View past prescription history',
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          subtitle: Text(
            'Family profile medication log',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          onExpansionChanged: (open) {
            // Lazy-load only when first opened.
            if (open) ref.read(patientPrescriptionsProvider(accountId));
          },
          children: [
            if (accountId.isEmpty)
              Text(
                'No patient account linked to this visit.',
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              )
            else
              Consumer(
                builder: (context, ref, _) {
                  final async =
                      ref.watch(patientPrescriptionsProvider(accountId));
                  return async.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: MtColors.brand),
                        ),
                      ),
                    ),
                    error: (e, _) => Text(
                      "Couldn't load prescriptions.",
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return Text(
                          'No prescriptions on file for this patient.',
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink3),
                        );
                      }
                      return Column(
                        children: [
                          for (final p in list) _PrescriptionRow(prescription: p),
                        ],
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionRow extends StatelessWidget {
  final Prescription prescription;
  const _PrescriptionRow({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final date =
        '${p.issuedAt.day}/${p.issuedAt.month}/${p.issuedAt.year}';
    final drugs = p.items.map((i) => i.drugName).where((s) => s.isNotEmpty);
    // Tap opens the full prescription pad — the doctor is privileged, so
    // the script arrives unredacted regardless of the patient's gate.
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showPrescriptionPadSheet(context, p),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MtColors.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.diagnosis.isEmpty ? 'Prescription' : p.diagnosis,
                    style: MtTextStyles.labelMd.copyWith(
                      color: MtColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  date,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_full,
                    size: 14, color: MtColors.ink3),
              ],
            ),
            if (drugs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                drugs.join(' · '),
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live sync utilities (chat / call)
// ---------------------------------------------------------------------------

class _SyncUtilitiesRow extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onCall;
  const _SyncUtilitiesRow({required this.onChat, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('Open Live Chat',
                  style: MtTextStyles.labelLg.copyWith(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: Text('Emergency Call', style: MtTextStyles.labelLg),
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.ink,
                side: const BorderSide(color: MtColors.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Complete-visit footer
// ---------------------------------------------------------------------------

class _CompleteFooter extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _CompleteFooter({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: MtColors.brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MtColors.brandSofter,
            disabledForegroundColor: MtColors.brand,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.edit_document, size: 20),
          label: Text(
            busy ? 'Closing visit…' : 'Formulate Prescription & Complete Visit',
            style: MtTextStyles.labelLg
                .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault editor sheet — lets the doctor populate the vault inline so the
// grid isn't empty (writes through PATCH /doctor/patients/:id/vault).
// ---------------------------------------------------------------------------

class _VaultEditorSheet extends ConsumerStatefulWidget {
  final String accountId;
  final String editorId;
  final PatientMedicalVault initial;
  const _VaultEditorSheet({
    required this.accountId,
    required this.editorId,
    required this.initial,
  });

  @override
  ConsumerState<_VaultEditorSheet> createState() => _VaultEditorSheetState();
}

class _VaultEditorSheetState extends ConsumerState<_VaultEditorSheet> {
  static const _bloodTypes = [
    'Unknown', 'O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-',
  ];

  late final TextEditingController _allergies =
      TextEditingController(text: widget.initial.allergies.join(', '));
  late final TextEditingController _conditions =
      TextEditingController(text: widget.initial.chronicConditions.join(', '));
  late final TextEditingController _notes =
      TextEditingController(text: widget.initial.emergencyNotes);
  late String _bloodType = _bloodTypes.contains(widget.initial.bloodType)
      ? widget.initial.bloodType
      : 'Unknown';
  bool _saving = false;

  @override
  void dispose() {
    _allergies.dispose();
    _conditions.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _split(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated =
          await ref.read(dioClientProvider).updatePatientMedicalVault(
                widget.accountId,
                allergies: _split(_allergies.text),
                chronicConditions: _split(_conditions.text),
                bloodType: _bloodType,
                emergencyNotes: _notes.text.trim(),
                updatedBy: widget.editorId,
              );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: MtColors.rejected,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MtColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Edit medical vault',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 16),
            _label('Blood type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _bloodType,
              decoration: _fieldDecoration(),
              items: [
                for (final t in _bloodTypes)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _bloodType = v ?? 'Unknown'),
            ),
            const SizedBox(height: 14),
            _label('Allergies (comma separated)'),
            const SizedBox(height: 6),
            TextField(
              controller: _allergies,
              decoration:
                  _fieldDecoration(hint: 'e.g. Penicillin, Peanuts'),
            ),
            const SizedBox(height: 14),
            _label('Chronic conditions (comma separated)'),
            const SizedBox(height: 6),
            TextField(
              controller: _conditions,
              decoration:
                  _fieldDecoration(hint: 'e.g. Type 2 diabetes, Hypertension'),
            ),
            const SizedBox(height: 14),
            _label('Emergency notes'),
            const SizedBox(height: 6),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: _fieldDecoration(hint: 'Anything a responder should know'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text('Save vault',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Text(
        t.toUpperCase(),
        style: MtTextStyles.sectionLabel
            .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
      );

  InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface2,
        isDense: true,
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
      );
}

// ---------------------------------------------------------------------------

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
