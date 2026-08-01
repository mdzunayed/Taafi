import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/doctor_profile_status.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/image_upload.dart';
import '../../auth/auth_provider.dart';
import '../providers/profile_completion_provider.dart';

/// Bottom sheet shown when the doctor taps the "Profile X% complete" banner.
///
/// Entire content is data-driven by [profileCompletionProvider]:
///   • Percentage + "items remaining" copy come from the live status.
///   • Each of the five rows reads its `has_*` boolean.
///   • The "Add" buttons open task-specific modals that save through
///     the notifier — once saved, the row flips green within the same
///     frame because the notifier swaps in the fresh status.
///
/// The dashboard banner behind the sheet also re-renders because the
/// notifier invalidates `doctorDashboardProvider` after every save.
Future<void> showCredentialsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: MtColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CredentialsSheet(),
  );
}

class _CredentialsSheet extends ConsumerWidget {
  const _CredentialsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileCompletionProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: async.when(
          loading: () => const _LoadingBody(),
          error: (e, _) => _ErrorBody(
            message: e.toString(),
            onRetry: () =>
                ref.read(profileCompletionProvider.notifier).refresh(),
          ),
          data: (status) => _ChecklistBody(status: status),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading + error states
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragHandle(),
        const SizedBox(height: 80),
        const CircularProgressIndicator(color: MtColors.brand),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragHandle(),
        const SizedBox(height: 24),
        const Icon(Icons.cloud_off_outlined, size: 36, color: MtColors.ink3),
        const SizedBox(height: 8),
        Text('Could not load checklist',
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
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main body (data) — header, progress bar, five checklist rows
// ---------------------------------------------------------------------------

class _ChecklistBody extends ConsumerWidget {
  final ProfileCompletionStatus status;
  const _ChecklistBody({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = status.itemsRemaining;
    final isNurse = ref.watch(currentUserProvider)?.role == UserRole.nurse;
    final licenseLabelEn = isNurse
        ? 'Nursing Council License Number'
        : 'BMDC license number';
    final licenseLabelBn =
        isNurse ? 'নার্সিং কাউন্সিল লাইসেন্স' : 'বিএমডিসি লাইসেন্স';
    final licenseHint = isNurse ? 'e.g. NC-99887' : 'e.g. A-12345';
    final licenseField = isNurse ? 'nursing_license' : 'bmdc_license';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DragHandle(),
        const SizedBox(height: 8),
        Text('Complete your profile',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 4),
        Text(
          'প্রোফাইল সম্পূর্ণ করুন',
          style: MtTextStyles.bodySm.copyWith(
            color: MtColors.ink2,
            fontFamily: 'Kalpurush',
          ),
        ),
        const SizedBox(height: 12),
        _ProgressRow(percent: status.completionPercent),
        const SizedBox(height: 16),
        Text(
          remaining == 0
              ? "You're all set — admin will review for verification."
              : '$remaining item${remaining == 1 ? '' : 's'} remaining. Completing your profile unlocks higher-value assignments.',
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
        const SizedBox(height: 16),
        _Row(
          done: status.hasPhoto,
          labelEn: 'Profile photo',
          labelBn: 'প্রোফাইল ছবি',
          onAdd: () => _onAddPhoto(context, ref),
        ),
        _Row(
          done: status.hasLicense,
          labelEn: licenseLabelEn,
          labelBn: licenseLabelBn,
          onAdd: () => _onAddText(
            context,
            ref,
            title: licenseLabelEn,
            hint: licenseHint,
            field: licenseField,
          ),
        ),
        _Row(
          done: status.hasSpecialty,
          labelEn: 'Specialization details',
          labelBn: 'বিশেষজ্ঞ তথ্য',
          onAdd: () => _onAddText(
            context,
            ref,
            title: 'Specialization details',
            hint: 'e.g. General Surgery',
            field: 'specialization',
          ),
        ),
        _Row(
          done: status.hasExperience,
          labelEn: 'Work experience',
          labelBn: 'কাজের অভিজ্ঞতা',
          onAdd: () => _onAddExperience(context, ref, status.experience),
        ),
        _Row(
          done: status.hasPayout,
          labelEn: 'Bank / bKash payout details',
          labelBn: 'পেমেন্ট তথ্য',
          // Show the masked account number inline once saved.
          trailingHint: status.hasPayout
              ? '${status.payout.method} · ${status.payout.accountNumber}'
              : null,
          onAdd: () => _onAddPayout(context, ref, status.payout),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---- Add handlers ------------------------------------------------------

  Future<void> _onAddPhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not open photo picker: $e', danger: true);
      }
      return;
    }
    if (picked == null) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      // Derives the filename and MIME from the bytes. Guessing them from
      // `picked.name`/`picked.mimeType` sent an iOS HEIC as `IMG_1.heic`
      // labelled image/jpeg — which the upload filter rejects on the
      // extension, and which used to be stored as an unrenderable avatar.
      final prepared = await prepareImageForUpload(picked);
      await ref.read(dioClientProvider).uploadProfilePicture(
            userId: user.id,
            bytes: prepared.bytes,
            filename: prepared.filename,
            mimeType: prepared.mimeType,
          );
      // Avatar upload doesn't return the full status; pull a fresh one.
      await ref.read(profileCompletionProvider.notifier).refresh();
      if (context.mounted) {
        _snack(context, 'Profile photo updated', success: true);
      }
    } on UnsupportedImageException catch (e) {
      if (context.mounted) _snack(context, e.message, danger: true);
    } catch (e) {
      if (context.mounted) _snack(context, _friendly(e), danger: true);
    }
  }

  /// Single-line text input modal used by both BMDC and Specialization
  /// rows. `field` is the snake_case key the backend whitelist
  /// expects (`bmdc_license` or `specialization`).
  Future<void> _onAddText(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String hint,
    required String field,
  }) async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _SingleFieldSheet(
        title: title,
        hint: hint,
        controller: controller,
      ),
    );
    if (value == null || value.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      await ref.read(dioClientProvider).updateProfessionalDetails(
        user.id,
        {
          // Backend accepts camelCase + snake_case; we send snake_case
          // here to match the existing convention of the rest of the
          // doctor edit sheet.
          field: value,
        },
      );
      await ref.read(profileCompletionProvider.notifier).refresh();
      if (context.mounted) _snack(context, '$title saved', success: true);
    } catch (e) {
      if (context.mounted) _snack(context, _friendly(e), danger: true);
    }
  }

  Future<void> _onAddExperience(
    BuildContext context,
    WidgetRef ref,
    List<DoctorExperience> existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WorkExperienceSheet(existing: existing),
    );
  }

  Future<void> _onAddPayout(
    BuildContext context,
    WidgetRef ref,
    DoctorPayoutDetails existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PayoutSheet(existing: existing),
    );
  }
}

String _friendly(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

void _snack(BuildContext context, String message,
    {bool success = false, bool danger = false}) {
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

// ---------------------------------------------------------------------------
// Reusable atoms
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: MtColors.line,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final int percent;
  const _ProgressRow({required this.percent});

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$clamped% complete',
                style:
                    MtTextStyles.labelLg.copyWith(color: MtColors.brand700)),
            Text(
              clamped >= 100 ? 'Verified-ready' : 'In progress',
              style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped / 100,
            backgroundColor: MtColors.line,
            color: MtColors.brand,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final bool done;
  final String labelEn;
  final String labelBn;
  final VoidCallback onAdd;
  final String? trailingHint;

  const _Row({
    required this.done,
    required this.labelEn,
    required this.labelBn,
    required this.onAdd,
    this.trailingHint,
  });

  @override
  Widget build(BuildContext context) {
    final iconBg = done ? const Color(0xFFDCF3E7) : MtColors.bg;
    final iconColor = done ? const Color(0xFF059669) : MtColors.ink3;
    final icon = done ? Icons.check : Icons.add_circle_outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: Text(
          labelEn,
          style: MtTextStyles.labelLg.copyWith(
            color: done ? MtColors.ink3 : MtColors.ink,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(labelBn,
                style: MtTextStyles.bodySm.copyWith(
                  color: MtColors.ink3,
                  fontFamily: 'Kalpurush',
                )),
            if (trailingHint != null && done)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  trailingHint!,
                  style:
                      MtTextStyles.labelSm.copyWith(color: MtColors.ink2),
                ),
              ),
          ],
        ),
        trailing: done
            ? null
            : TextButton(
                onPressed: onAdd,
                style: TextButton.styleFrom(foregroundColor: MtColors.brand),
                child: Text('Add', style: MtTextStyles.labelMd),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modals — single field, work experience, payout
// ---------------------------------------------------------------------------

class _SingleFieldSheet extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;

  const _SingleFieldSheet({
    required this.title,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _DragHandle()),
              Text(title,
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MtColors.line),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Save',
                    style:
                        MtTextStyles.labelLg.copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkExperienceSheet extends ConsumerStatefulWidget {
  final List<DoctorExperience> existing;
  const _WorkExperienceSheet({required this.existing});

  @override
  ConsumerState<_WorkExperienceSheet> createState() =>
      _WorkExperienceSheetState();
}

class _WorkExperienceSheetState
    extends ConsumerState<_WorkExperienceSheet> {
  late List<DoctorExperience> _entries;
  final _hospital = TextEditingController();
  final _designation = TextEditingController();
  final _years = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.existing);
  }

  @override
  void dispose() {
    _hospital.dispose();
    _designation.dispose();
    _years.dispose();
    super.dispose();
  }

  void _addLocalEntry() {
    final h = _hospital.text.trim();
    final d = _designation.text.trim();
    final y = int.tryParse(_years.text.trim()) ?? 0;
    if (h.isEmpty || d.isEmpty) {
      _snack(context, 'Hospital and designation are required.', danger: true);
      return;
    }
    setState(() {
      _entries = [..._entries, DoctorExperience(hospitalName: h, designation: d, years: y)];
      _hospital.clear();
      _designation.clear();
      _years.clear();
    });
  }

  void _removeAt(int index) {
    setState(() {
      _entries = [..._entries]..removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await ref
        .read(profileCompletionProvider.notifier)
        .saveExperience(_entries);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
      _snack(context, 'Work experience saved', success: true);
    } else {
      final err = ref.read(profileCompletionProvider).whenOrNull(
            error: (e, _) => _friendly(e),
          );
      _snack(context, err ?? 'Could not save', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _DragHandle()),
              Text('Work experience',
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 8),
              if (_entries.isNotEmpty) ...[
                for (var i = 0; i < _entries.length; i++)
                  _ExistingExperienceRow(
                    entry: _entries[i],
                    onRemove: () => _removeAt(i),
                  ),
                const SizedBox(height: 8),
                Text('Add another',
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 0.6,
                    )),
                const SizedBox(height: 6),
              ],
              TextField(
                controller: _hospital,
                decoration: InputDecoration(
                  labelText: 'Hospital / clinic',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _designation,
                decoration: InputDecoration(
                  labelText: 'Designation',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _years,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Years',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _addLocalEntry,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add entry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MtColors.brand,
                  side: const BorderSide(color: MtColors.brand),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saving || _entries.isEmpty ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MtColors.brand.withValues(alpha: 0.45),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                    : Text('Save',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingExperienceRow extends StatelessWidget {
  final DoctorExperience entry;
  final VoidCallback onRemove;
  const _ExistingExperienceRow({
    required this.entry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.designation} · ${entry.hospitalName}',
                    style: MtTextStyles.labelMd
                        .copyWith(color: MtColors.ink)),
                Text('${entry.years} yrs',
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18, color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _PayoutSheet extends ConsumerStatefulWidget {
  final DoctorPayoutDetails existing;
  const _PayoutSheet({required this.existing});

  @override
  ConsumerState<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends ConsumerState<_PayoutSheet> {
  late String _method;
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  final _bankName = TextEditingController();
  final _branch = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _method = widget.existing.method.isEmpty ? 'bKash' : widget.existing.method;
    _accountName.text = widget.existing.accountName;
    _bankName.text = widget.existing.bankName;
    _branch.text = widget.existing.branch;
    // Don't prefill the account number — backend only returns the
    // masked value, and pre-populating the masked string into an edit
    // field would be a footgun.
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountName.dispose();
    _bankName.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _accountNumber.text.trim();
    if (raw.isEmpty) {
      _snack(context, 'Account number is required.', danger: true);
      return;
    }
    setState(() => _saving = true);
    final ok =
        await ref.read(profileCompletionProvider.notifier).savePayout(
              method: _method,
              accountNumber: raw,
              accountName: _accountName.text.trim(),
              bankName: _bankName.text.trim(),
              branch: _branch.text.trim(),
            );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
      _snack(context, 'Payout details saved', success: true);
    } else {
      final err = ref.read(profileCompletionProvider).whenOrNull(
            error: (e, _) => _friendly(e),
          );
      _snack(context, err ?? 'Could not save', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final isBkash = _method == 'bKash';
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _DragHandle()),
              Text('Payout details',
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bKash', label: Text('bKash')),
                  ButtonSegment(value: 'Bank', label: Text('Bank transfer')),
                ],
                selected: {_method},
                onSelectionChanged: (s) =>
                    setState(() => _method = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _accountNumber,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText:
                      isBkash ? 'bKash phone number' : 'Account number',
                  hintText: widget.existing.isSet
                      ? 'Replaces saved ${widget.existing.accountNumber}'
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (!isBkash) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _accountName,
                  decoration: InputDecoration(
                    labelText: 'Account holder name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bankName,
                  decoration: InputDecoration(
                    labelText: 'Bank name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _branch,
                  decoration: InputDecoration(
                    labelText: 'Branch',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MtColors.brand.withValues(alpha: 0.45),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                    : Text('Save',
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
