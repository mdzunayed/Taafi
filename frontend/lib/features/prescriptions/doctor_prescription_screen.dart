import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prescription.dart';
import '../../core/theme/mt_colors.dart';
import '../../core/theme/mt_text_styles.dart';
import '../auth/auth_provider.dart';

/// Doctor-side prescription form. Triggered when the provider flips
/// the visit to "Care Completed". Dynamic list — the doctor can add
/// as many medication line items as the visit requires, each with:
///
///   - Drug name
///   - Dosage
///   - Frequency chips (Morning / Afternoon / Night, bilingual)
///   - Meal context toggle (Before / After / Either)
///   - Duration in days
///   - Optional notes
///
/// Tapping "Finalize and Issue Prescription" POSTs to
/// `/api/prescriptions`; the server fans out an FCM push + in-app
/// notification so the patient sees the new script on the medication
/// timeline immediately.
///
/// Layout cap: `Center → ConstrainedBox(maxWidth: 600)` so the form
/// stays readable on desktop / web instead of stretching.
class DoctorPrescriptionScreen extends ConsumerStatefulWidget {
  final String appointmentId;
  final String? patientAccountId;
  final String? patientName;
  final String? careType;

  /// Target-patient identity for a family-member booking; pre-fills the pad
  /// header. Null on a self-booking (the account holder).
  final int? patientAge;
  final String? patientGender;

  const DoctorPrescriptionScreen({
    super.key,
    required this.appointmentId,
    this.patientAccountId,
    this.patientName,
    this.careType,
    this.patientAge,
    this.patientGender,
  });

  @override
  ConsumerState<DoctorPrescriptionScreen> createState() =>
      _DoctorPrescriptionScreenState();
}

class _DoctorPrescriptionScreenState
    extends ConsumerState<DoctorPrescriptionScreen> {
  final _diagnosisCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _adviceCtrl = TextEditingController();
  DateTime? _followUpDate;
  late final List<_MedDraft> _items = [_MedDraft()];
  bool _busy = false;

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _adviceCtrl.dispose();
    for (final d in _items) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFollowUpDate() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  void _addItem() {
    setState(() => _items.add(_MedDraft()));
  }

  void _removeItem(int idx) {
    if (_items.length == 1) return;
    setState(() {
      _items[idx].dispose();
      _items.removeAt(idx);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    // Validate every draft.
    final errors = <String>[];
    final clean = <PrescriptionItem>[];
    for (var i = 0; i < _items.length; i++) {
      final draft = _items[i];
      final issue = draft.validate();
      if (issue != null) {
        errors.add('Medication ${i + 1}: $issue');
      } else {
        clean.add(draft.toItem());
      }
    }
    if (errors.isNotEmpty) {
      HapticFeedback.vibrate();
      messenger.showSnackBar(SnackBar(content: Text(errors.first)));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioClientProvider);
      final user = ref.read(currentUserProvider);
      await dio.createPrescription(
        appointmentId: widget.appointmentId,
        items: clean,
        patientAccountId: widget.patientAccountId,
        doctorName: user?.name,
        diagnosis: _diagnosisCtrl.text,
        weightKg: double.tryParse(_weightCtrl.text.trim()),
        heightCm: double.tryParse(_heightCtrl.text.trim()),
        advice: _adviceCtrl.text.trim(),
        followUpDate: _followUpDate,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: MtColors.completed,
          content: Text('Prescription issued.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      // The Dio client (`_handleError`) already surfaces the backend's
      // `message` field — including the 409 status-lock reason when the
      // visit isn't in a prescribable state — wrapped as an Exception.
      // Strip the "Exception: " prefix so the doctor sees the plain
      // server reason rather than a raw exception string, with a
      // bilingual fallback matching this screen's `English (বাংলা)`
      // convention when no server message is available.
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content: Text(_friendlyError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Normalises a thrown error into a clean, user-facing message.
  String _friendlyError(Object e) {
    var msg = e.toString().trim();
    if (msg.startsWith('Exception:')) {
      msg = msg.substring('Exception:'.length).trim();
    }
    if (msg.isEmpty) {
      return "Couldn't issue prescription (প্রেসক্রিপশন দেওয়া যায়নি). "
          'Please try again.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Issue prescription'),
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
                      _ContextBanner(
                        patientName: widget.patientName,
                        careType: widget.careType,
                        patientAge: widget.patientAge,
                        patientGender: widget.patientGender,
                      ),
                      const SizedBox(height: 14),
                      _SectionLabel(label: 'Diagnosis (optional)'),
                      const SizedBox(height: 6),
                      _PlainField(
                        controller: _diagnosisCtrl,
                        hint: 'e.g. Post-surgical recovery, wound clean',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 18),
                      // Pad vitals bar inputs — BP is copied from the
                      // visit's recorded vitals server-side; weight and
                      // height are the doctor's call at prescribing time.
                      _SectionLabel(label: 'Patient metrics (optional)'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _PlainField(
                              controller: _weightCtrl,
                              hint: 'Weight (kg)',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PlainField(
                              controller: _heightCtrl,
                              hint: 'Height (cm)',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(label: 'Medications'),
                      const SizedBox(height: 6),
                      for (var i = 0; i < _items.length; i++) ...[
                        _MedCard(
                          index: i,
                          draft: _items[i],
                          canDelete: _items.length > 1,
                          onDelete: () => _removeItem(i),
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _AddMedRow(onTap: _addItem),
                      const SizedBox(height: 18),
                      _SectionLabel(label: 'Advice given (optional)'),
                      const SizedBox(height: 6),
                      _PlainField(
                        controller: _adviceCtrl,
                        hint: 'e.g. Take adequate rest, drink plenty of '
                            'fluids, avoid oily food',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(label: 'Follow-up (optional)'),
                      const SizedBox(height: 6),
                      _FollowUpPicker(
                        date: _followUpDate,
                        onPick: _pickFollowUpDate,
                        onClear: () =>
                            setState(() => _followUpDate = null),
                      ),
                    ],
                  ),
                ),
                _FinalizeBar(busy: _busy, onTap: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedDraft {
  final TextEditingController drug = TextEditingController();
  final TextEditingController dosage = TextEditingController();
  final TextEditingController duration = TextEditingController(text: '7');
  final TextEditingController notes = TextEditingController();
  MedicationForm? form;
  Set<DoseSlot> slots = <DoseSlot>{};
  MealContext meal = MealContext.either;

  void dispose() {
    drug.dispose();
    dosage.dispose();
    duration.dispose();
    notes.dispose();
  }

  String? validate() {
    if (drug.text.trim().isEmpty) return 'Drug name is required';
    if (dosage.text.trim().isEmpty) return 'Dosage is required';
    if (slots.isEmpty) return 'Select at least one time slot';
    final n = int.tryParse(duration.text.trim());
    if (n == null || n < 1 || n > 365) {
      return 'Duration must be between 1 and 365 days';
    }
    return null;
  }

  PrescriptionItem toItem() => PrescriptionItem(
        form: form,
        drugName: drug.text.trim(),
        dosage: dosage.text.trim(),
        frequency: Set.of(slots),
        mealContext: meal,
        durationDays: int.parse(duration.text.trim()),
        notes: notes.text.trim(),
      );
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ContextBanner extends StatelessWidget {
  final String? patientName;
  final String? careType;
  final int? patientAge;
  final String? patientGender;
  const _ContextBanner({
    this.patientName,
    this.careType,
    this.patientAge,
    this.patientGender,
  });

  /// "62 yrs · Female" style line for the target patient, dropping unknowns.
  String get _ageSexLine {
    final parts = <String>[];
    if (patientAge != null) parts.add('$patientAge yrs');
    final g = (patientGender ?? '').trim();
    if (g.isNotEmpty) parts.add(g[0].toUpperCase() + g.substring(1));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if ((patientName ?? '').isEmpty && (careType ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    final ageSex = _ageSexLine;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.brandSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_outlined,
              color: MtColors.brand, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (patientName ?? '').isEmpty
                      ? 'Issuing prescription'
                      : 'Issuing prescription for $patientName',
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (ageSex.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ageSex,
                    style: MtTextStyles.bodySm.copyWith(
                      color: MtColors.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if ((careType ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    careType!,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink2),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel.copyWith(
        color: MtColors.ink3,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _MedCard extends StatelessWidget {
  final int index;
  final _MedDraft draft;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _MedCard({
    required this.index,
    required this.draft,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Medication ${index + 1}',
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close,
                      size: 18, color: MtColors.ink3),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Optional dosage form — the pad prints it before the drug
          // name ("Tab. Napa"). Tapping the active chip clears it.
          _FormChips(
            selected: draft.form,
            onChanged: (next) {
              draft.form = next;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          _PlainField(
            controller: draft.drug,
            hint: 'Drug name (e.g. Paracetamol 500mg)',
          ),
          const SizedBox(height: 8),
          _PlainField(
            controller: draft.dosage,
            hint: 'Dosage (e.g. 1 tablet, 5 ml)',
          ),
          const SizedBox(height: 12),
          _SlotChips(
            selected: draft.slots,
            onChanged: (next) {
              draft.slots = next;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          _MealToggle(
            selected: draft.meal,
            onChanged: (next) {
              draft.meal = next;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          _DurationField(controller: draft.duration),
          const SizedBox(height: 10),
          _PlainField(
            controller: draft.notes,
            hint: 'Notes (optional)',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _FormChips extends StatelessWidget {
  final MedicationForm? selected;
  final ValueChanged<MedicationForm?> onChanged;
  const _FormChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in MedicationForm.values)
          _Chip(
            label: f.label,
            active: selected == f,
            onTap: () => onChanged(selected == f ? null : f),
          ),
      ],
    );
  }
}

class _FollowUpPicker extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _FollowUpPicker({
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = date == null
        ? 'Pick a follow-up date'
        : '${date!.day}/${date!.month}/${date!.year}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  date == null ? MtColors.ink2 : MtColors.brand,
              side: BorderSide(
                color: date == null ? MtColors.line : MtColors.brand,
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              label,
              style: MtTextStyles.labelMd.copyWith(
                color: date == null ? MtColors.ink2 : MtColors.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (date != null)
          IconButton(
            tooltip: 'Clear follow-up',
            icon: const Icon(Icons.close, size: 18, color: MtColors.ink3),
            onPressed: onClear,
          ),
      ],
    );
  }
}

class _SlotChips extends StatelessWidget {
  final Set<DoseSlot> selected;
  final ValueChanged<Set<DoseSlot>> onChanged;
  const _SlotChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in DoseSlot.values)
          _Chip(
            label: '${s.labelEn} (${s.labelBn})',
            active: selected.contains(s),
            onTap: () {
              final next = Set<DoseSlot>.of(selected);
              if (!next.add(s)) next.remove(s);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _MealToggle extends StatelessWidget {
  final MealContext selected;
  final ValueChanged<MealContext> onChanged;
  const _MealToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in MealContext.values)
          _Chip(
            label: '${m.labelEn} (${m.labelBn})',
            active: selected == m,
            onTap: () => onChanged(m),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? MtColors.brand : MtColors.surface2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? MtColors.brand : MtColors.line,
            ),
          ),
          child: Text(
            label,
            style: MtTextStyles.labelMd.copyWith(
              color: active ? Colors.white : MtColors.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationField extends StatelessWidget {
  final TextEditingController controller;
  const _DurationField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlainField(
            controller: controller,
            hint: 'Duration',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 8),
        Text('days',
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
      ],
    );
  }
}

class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const _PlainField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
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

class _AddMedRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMedRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: MtColors.brand,
        side: const BorderSide(color: MtColors.brand),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text(
        'Add another medication',
        style: MtTextStyles.labelLg.copyWith(
          color: MtColors.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FinalizeBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _FinalizeBar({required this.busy, required this.onTap});

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
        height: 52,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: MtColors.brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MtColors.brandSofter,
            disabledForegroundColor: MtColors.brand,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
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
              : const Icon(Icons.check_circle_outline, size: 20),
          label: Text(
            busy ? 'Issuing…' : 'Finalize and Issue Prescription',
            style: MtTextStyles.labelLg.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
