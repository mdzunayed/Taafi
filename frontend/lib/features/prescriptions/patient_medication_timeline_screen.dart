import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/prescription.dart';
import '../../core/theme/mt_colors.dart';
import '../../core/theme/mt_text_styles.dart';
import 'prescriptions_provider.dart';

/// Patient-facing medication timeline. Pulls active prescriptions via
/// [patientPrescriptionsProvider] and lays them out as a vertical
/// per-slot schedule (Morning / Afternoon / Night). Each medication
/// row in a slot carries a "Mark as Taken" checkbox so the patient
/// logs adherence — the toggle round-trips to
/// `PATCH /api/prescriptions/:id/dose` and reconciles against the
/// canonical server response.
///
/// Layout cap: `Center → ConstrainedBox(maxWidth: 600)` so the
/// timeline stays compact on desktop / web.
class PatientMedicationTimelineScreen extends ConsumerWidget {
  const PatientMedicationTimelineScreen({super.key});

  /// Today's YYYY-MM-DD bucket — the doses logged against this key
  /// drive the checkbox state. Computed once per build; the screen
  /// is short-lived enough that a midnight rollover mid-session is a
  /// non-issue (a refresh re-derives it).
  static String _todayKey() => DateTime.now().toIso8601String().slice0to10();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientPrescriptionsProvider);
    final dayKey = _todayKey();

    return Scaffold(
      backgroundColor: MtColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              color: MtColors.brand,
              onRefresh: () =>
                  ref.read(patientPrescriptionsProvider.notifier).refresh(),
              child: async.when(
                loading: () => const _LoadingView(),
                error: (e, _) => _ErrorView(
                  message: e.toString(),
                  onRetry: () => ref
                      .read(patientPrescriptionsProvider.notifier)
                      .refresh(),
                ),
                data: (prescriptions) {
                  final rows = _buildSlotRows(prescriptions);
                  if (rows.isEmpty) return const _EmptyView();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const _Header(),
                      const SizedBox(height: 14),
                      for (final slot in DoseSlot.values)
                        if (rows[slot]!.isNotEmpty) ...[
                          _SlotSection(
                            slot: slot,
                            entries: rows[slot]!,
                            dayKey: dayKey,
                          ),
                          const SizedBox(height: 18),
                        ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fan the prescriptions out into per-slot buckets. One
  /// medication scheduled for Morning + Night shows up in both
  /// buckets as two separate timeline entries.
  Map<DoseSlot, List<_DoseEntry>> _buildSlotRows(
    List<Prescription> prescriptions,
  ) {
    final map = {
      for (final s in DoseSlot.values) s: <_DoseEntry>[],
    };
    for (final p in prescriptions) {
      // Locked scripts never surface dose slots — their items arrive
      // server-redacted anyway; the explicit skip is defence in depth.
      if (p.locked) continue;
      for (final item in p.items) {
        for (final slot in item.frequency) {
          map[slot]!.add(_DoseEntry(prescription: p, item: item, slot: slot));
        }
      }
    }
    return map;
  }
}

/// One renderable (prescription, item, slot) triple.
class _DoseEntry {
  final Prescription prescription;
  final PrescriptionItem item;
  final DoseSlot slot;
  const _DoseEntry({
    required this.prescription,
    required this.item,
    required this.slot,
  });
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's medications",
          style: MtTextStyles.h1.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          today,
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Slot section
// ---------------------------------------------------------------------------

class _SlotSection extends StatelessWidget {
  final DoseSlot slot;
  final List<_DoseEntry> entries;
  final String dayKey;

  const _SlotSection({
    required this.slot,
    required this.entries,
    required this.dayKey,
  });

  IconData get _icon {
    switch (slot) {
      case DoseSlot.morning:
        return Icons.wb_twilight;
      case DoseSlot.afternoon:
        return Icons.wb_sunny_outlined;
      case DoseSlot.night:
        return Icons.nightlight_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: MtColors.brandSofter,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_icon, size: 17, color: MtColors.brand),
            ),
            const SizedBox(width: 10),
            Text(
              slot.labelEn,
              style: MtTextStyles.labelLg.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${slot.labelBn})',
              style: MtTextStyles.bodySm.copyWith(
                color: MtColors.ink3,
                fontFamily: 'Kalpurush',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++) ...[
          _DoseCard(entry: entries[i], dayKey: dayKey),
          if (i != entries.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dose card
// ---------------------------------------------------------------------------

class _DoseCard extends ConsumerStatefulWidget {
  final _DoseEntry entry;
  final String dayKey;

  const _DoseCard({required this.entry, required this.dayKey});

  @override
  ConsumerState<_DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends ConsumerState<_DoseCard> {
  bool _busy = false;

  Future<void> _toggle(bool taken) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final ok = await ref
        .read(patientPrescriptionsProvider.notifier)
        .toggleDose(
          prescriptionId: widget.entry.prescription.id,
          itemId: widget.entry.item.id,
          slot: widget.entry.slot,
          dayKey: widget.dayKey,
          taken: taken,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update — try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.entry.item;
    final taken = widget.entry.prescription.isDoseTaken(
      itemId: item.id,
      slot: widget.entry.slot,
      dayKey: widget.dayKey,
    );
    final mealLabel = item.mealContext == MealContext.either
        ? null
        : '${item.mealContext.labelEn} · ${item.mealContext.labelBn}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: taken ? MtColors.completedBg : MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: taken ? MtColors.completed : MtColors.line,
          width: taken ? 1.2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.drugName,
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                    decoration:
                        taken ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.dosage,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                if (mealLabel != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.restaurant_outlined,
                          size: 13, color: MtColors.ink3),
                      const SizedBox(width: 4),
                      Text(
                        mealLabel,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3),
                      ),
                    ],
                  ),
                ],
                if (item.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.notes,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TakenControl(
            taken: taken,
            busy: _busy,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}

class _TakenControl extends StatelessWidget {
  final bool taken;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _TakenControl({
    required this.taken,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: busy ? null : () => onChanged(!taken),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(MtColors.brand),
                      ),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color:
                            taken ? MtColors.completed : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: taken ? MtColors.completed : MtColors.ink3,
                          width: 1.6,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 16,
                        color: taken ? Colors.white : Colors.transparent,
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              taken ? 'Taken' : 'Mark',
              style: MtTextStyles.bodySm.copyWith(
                color: taken ? MtColors.completed : MtColors.ink3,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / loading / error
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: MtColors.brand)),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: MtColors.brandSofter,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medication_outlined,
              color: MtColors.brand,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'No active medications',
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'When a doctor issues a prescription at the end of a visit, your '
          'medication schedule will appear here.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        const Center(
          child: Icon(Icons.cloud_off_outlined,
              size: 36, color: MtColors.ink3),
        ),
        const SizedBox(height: 10),
        Text(
          "Couldn't load medications",
          textAlign: TextAlign.center,
          style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
        ),
        const SizedBox(height: 14),
        Center(
          child: ElevatedButton(
            onPressed: () => onRetry(),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

/// Tiny helper so the day-key derivation reads cleanly above.
extension _Slice on String {
  String slice0to10() => length >= 10 ? substring(0, 10) : this;
}
