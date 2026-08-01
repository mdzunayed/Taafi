import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/assigned_doctor.dart';
import '../../core/models/prescription.dart';
import '../../core/theme/app_colors_ext.dart';
import '../../core/theme/mt_text_styles.dart';
import '../../core/widgets/initials_avatar.dart';
import '../patient/screens/prescription_detail_screen.dart';
import '../patient/screens/view_assigned_doctor_screen.dart';
import 'prescription_release_gate.dart';
import 'prescriptions_provider.dart';

/// "Medications" tab inside the patient's Activities hub.
///
/// Renders every prescription ever issued to the patient as a rich,
/// self-contained card: the issuing doctor's profile header (avatar +
/// specialization + View Profile), the diagnosis + issue date +
/// Active/Completed badge, and the itemized medication lines with
/// `1+0+1`-style schedule chips. Active cards additionally expose
/// tappable per-slot adherence toggles for today, backed by the same
/// `PATCH /api/prescriptions/:id/dose` write path the old timeline
/// used, so the hub stays trackable and not just readable.
///
/// All colors come off `context.appColors`, so card outlines render
/// crisp grey/silver on the light theme and the slate hairline on the
/// dark obsidian theme with zero per-widget branching.
class MedicationsTabView extends ConsumerWidget {
  const MedicationsTabView({super.key});

  /// Today's YYYY-MM-DD bucket driving the adherence chips. Derived
  /// per build — the tab is short-lived enough that a midnight
  /// rollover mid-session is a non-issue.
  static String _todayKey() =>
      DateTime.now().toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(medicationsHubProvider);
    final colors = context.appColors;

    return RefreshIndicator(
      color: colors.brand,
      onRefresh: () => ref.read(medicationsHubProvider.notifier).refresh(),
      child: async.when(
        // Skeleton placeholder while the network fetch is in flight —
        // never a bare spinner, and never a spinner that outlives the
        // fetch: `when` swaps to data/error the moment the future
        // settles.
        loading: () => const _SkeletonList(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.read(medicationsHubProvider.notifier).refresh(),
        ),
        data: (prescriptions) {
          if (prescriptions.isEmpty) return const _EmptyView();
          final dayKey = _todayKey();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: prescriptions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _PrescriptionCard(
              prescription: prescriptions[i],
              dayKey: dayKey,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prescription card
// ---------------------------------------------------------------------------

class _PrescriptionCard extends StatelessWidget {
  final Prescription prescription;
  final String dayKey;

  const _PrescriptionCard({
    required this.prescription,
    required this.dayKey,
  });

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrescriptionDetailScreen(prescriptionId: prescription.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isActive = prescription.status == PrescriptionStatus.active;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DoctorHeader(prescription: prescription),
              Divider(height: 1, thickness: 1, color: colors.cardBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusRow(prescription: prescription),
                    if (prescription.diagnosis.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        prescription.diagnosis,
                        style:
                            MtTextStyles.bodySm.copyWith(color: colors.body),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (prescription.locked)
                      // Items are server-redacted while the release gate
                      // is closed — render the gate hint instead of an
                      // empty medication list. Tap-through opens the
                      // detail screen's paywall / pending card.
                      _LockedHint(prescription: prescription)
                    else
                      for (var i = 0;
                          i < prescription.items.length;
                          i++) ...[
                        _MedicationRow(
                          prescription: prescription,
                          item: prescription.items[i],
                          dayKey: dayKey,
                          trackable: isActive,
                        ),
                        if (i != prescription.items.length - 1)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: colors.cardBorder,
                            ),
                          ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked-script hint (release gate)
// ---------------------------------------------------------------------------

class _LockedHint extends StatelessWidget {
  final Prescription prescription;
  const _LockedHint({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final chip = releaseChipColors(prescription.releaseStatus);
    final count = prescription.effectiveItemCount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: chip.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chip.bg),
      ),
      child: Row(
        children: [
          Icon(
            prescription.releaseStatus == PrescriptionReleaseStatus.rejected
                ? Icons.block_outlined
                : Icons.lock_outline,
            size: 20,
            color: chip.fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count medication${count == 1 ? '' : 's'} locked',
                  style: MtTextStyles.labelLg.copyWith(
                    color: colors.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  releaseChipLabel(prescription),
                  style: MtTextStyles.bodySm.copyWith(color: chip.fg),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.body),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Doctor profile header
// ---------------------------------------------------------------------------

class _DoctorHeader extends StatelessWidget {
  final Prescription prescription;
  const _DoctorHeader({required this.prescription});

  /// The doctor block the profile screen needs. Falls back to a
  /// minimal record built from the prescription's flat fields when the
  /// server-side provider join missed, so View Profile always works.
  AssignedDoctor get _doctor =>
      prescription.doctor ??
      AssignedDoctor(
        id: prescription.doctorAccountId,
        fullName: prescription.doctorName,
        specialty: prescription.doctorSpecialization,
        bmdcLicense:
            prescription.doctorBmdc.isEmpty ? null : prescription.doctorBmdc,
        isVerifiedDoctor: prescription.doctorVerified,
      );

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewAssignedDoctorScreen(
          doctor: _doctor,
          appointmentId: prescription.appointmentId,
        ),
      ),
    );
  }

  String get _displayName {
    final name = _doctor.fullName.trim();
    if (name.isEmpty) return 'Your doctor';
    return RegExp(r'^[Dd]r\.?\s').hasMatch(name) ? name : 'Dr. $name';
  }

  String get _subtitle {
    final parts = <String>[
      if (_doctor.specialty.trim().isNotEmpty) _doctor.specialty.trim(),
      if ((_doctor.bmdcLicense ?? '').trim().isNotEmpty)
        'BMDC ${_doctor.bmdcLicense!.trim()}',
    ];
    if (parts.isEmpty && (_doctor.hospitalAffiliation ?? '').isNotEmpty) {
      parts.add(_doctor.hospitalAffiliation!);
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final doctor = _doctor;

    return InkWell(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      onTap: () => _openProfile(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            _DoctorAvatar(doctor: doctor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MtTextStyles.labelLg.copyWith(
                            color: colors.title,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (doctor.isVerifiedDoctor) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified,
                            size: 15, color: colors.brand),
                      ],
                    ],
                  ),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          MtTextStyles.bodySm.copyWith(color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Profile',
                  style: MtTextStyles.labelSm.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: colors.brand),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorAvatar extends StatelessWidget {
  final AssignedDoctor doctor;
  const _DoctorAvatar({required this.doctor});

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final url = doctor.profilePicture;

    final fallback = InitialsAvatar(
      name: doctor.fullName.isEmpty ? 'Dr' : doctor.fullName,
      size: _size,
      backgroundColor: colors.brand,
      textColor: colors.onAccent,
    );

    Widget avatar;
    if (url == null || url.isEmpty) {
      avatar = fallback;
    } else {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, _) => fallback,
          errorWidget: (_, _, _) => fallback,
        ),
      );
    }

    // Hairline ring so the photo separates from the surface on both
    // themes.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.cardBorder),
      ),
      child: avatar,
    );
  }
}

// ---------------------------------------------------------------------------
// Status row
// ---------------------------------------------------------------------------

class _StatusRow extends StatelessWidget {
  final Prescription prescription;
  const _StatusRow({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isActive = prescription.status == PrescriptionStatus.active;
    final issued = DateFormat('MMM d, yyyy').format(prescription.issuedAt);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? colors.positiveBg : colors.surfaceHi,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive ? colors.positive : colors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                isActive ? 'Active' : 'Completed',
                style: MtTextStyles.labelSm.copyWith(
                  color: isActive ? colors.positive : colors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Icon(Icons.event_outlined, size: 13, color: colors.muted),
        const SizedBox(width: 4),
        Text(
          'Issued $issued',
          style: MtTextStyles.bodySm.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Medication line item
// ---------------------------------------------------------------------------

class _MedicationRow extends StatelessWidget {
  final Prescription prescription;
  final PrescriptionItem item;
  final String dayKey;

  /// Whether the per-slot adherence toggles render. Only active
  /// prescriptions are trackable — a completed course is read-only.
  final bool trackable;

  const _MedicationRow({
    required this.prescription,
    required this.item,
    required this.dayKey,
    required this.trackable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: colors.surfaceHi,
                borderRadius: BorderRadius.circular(9),
              ),
              child:
                  Icon(Icons.medication_outlined, size: 16, color: colors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.drugName,
                    style: MtTextStyles.labelLg.copyWith(
                      color: colors.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.dosage.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      item.dosage,
                      style:
                          MtTextStyles.bodySm.copyWith(color: colors.body),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _InfoChip(
              icon: Icons.schedule,
              label: item.frequencyCode,
              emphasized: true,
            ),
            if (item.mealContext != MealContext.either)
              _InfoChip(
                icon: Icons.restaurant_outlined,
                label: item.mealContext.labelEn,
              ),
            _InfoChip(
              icon: Icons.calendar_month_outlined,
              label: '${item.durationDays} days',
            ),
          ],
        ),
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.notes,
            style: MtTextStyles.bodySm.copyWith(color: colors.muted),
          ),
        ],
        if (trackable && item.frequency.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TodayTracker(
            prescription: prescription,
            item: item,
            dayKey: dayKey,
          ),
        ],
      ],
    );
  }
}

/// Small tonal metadata pill (schedule code, meal timing, duration).
/// `emphasized` renders the brand-tinted variant used for the
/// `1+0+1` schedule code.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fg = emphasized ? colors.brand : colors.body;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized ? colors.glow : colors.surfaceHi,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: MtTextStyles.labelSm.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's adherence tracker (active prescriptions only)
// ---------------------------------------------------------------------------

/// One tappable chip per scheduled slot for today. Tapping toggles the
/// dose's taken state through the hub notifier's optimistic
/// write-through; the chip shows a tiny spinner while its own request
/// is in flight.
class _TodayTracker extends ConsumerStatefulWidget {
  final Prescription prescription;
  final PrescriptionItem item;
  final String dayKey;

  const _TodayTracker({
    required this.prescription,
    required this.item,
    required this.dayKey,
  });

  @override
  ConsumerState<_TodayTracker> createState() => _TodayTrackerState();
}

class _TodayTrackerState extends ConsumerState<_TodayTracker> {
  DoseSlot? _busySlot;

  static const List<DoseSlot> _order = [
    DoseSlot.morning,
    DoseSlot.afternoon,
    DoseSlot.night,
  ];

  Future<void> _toggle(DoseSlot slot, bool taken) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busySlot = slot);
    final ok = await ref.read(medicationsHubProvider.notifier).toggleDose(
          prescriptionId: widget.prescription.id,
          itemId: widget.item.id,
          slot: slot,
          dayKey: widget.dayKey,
          taken: taken,
        );
    if (!mounted) return;
    setState(() => _busySlot = null);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't update — try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Text(
          'Today',
          style: MtTextStyles.labelSm.copyWith(
            color: colors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final slot in _order)
                if (widget.item.frequency.contains(slot))
                  _SlotChip(
                    slot: slot,
                    taken: widget.prescription.isDoseTaken(
                      itemId: widget.item.id,
                      slot: slot,
                      dayKey: widget.dayKey,
                    ),
                    busy: _busySlot == slot,
                    onTap: (taken) => _toggle(slot, taken),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  final DoseSlot slot;
  final bool taken;
  final bool busy;
  final ValueChanged<bool> onTap;

  const _SlotChip({
    required this.slot,
    required this.taken,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final fg = taken ? colors.positive : colors.body;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: busy ? null : () => onTap(!taken),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: taken ? colors.positiveBg : colors.surfaceHi,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: taken ? colors.positive : colors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
                ),
              )
            else
              Icon(
                taken ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 13,
                color: fg,
              ),
            const SizedBox(width: 4),
            Text(
              slot.labelEn,
              style: MtTextStyles.labelSm.copyWith(
                color: fg,
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
// Loading skeleton
// ---------------------------------------------------------------------------

/// Pulsing placeholder cards shown while the fetch is in flight —
/// mirrors the real card anatomy (avatar circle, two text bars, three
/// medication bars) so the swap to live data doesn't jump.
class _SkeletonList extends StatefulWidget {
  const _SkeletonList();

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.45,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, _) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget bar(double width, {double height = 11}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colors.surfaceHi,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.surfaceHi,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140),
                  const SizedBox(height: 6),
                  bar(96, height: 9),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          bar(double.infinity),
          const SizedBox(height: 10),
          bar(220),
          const SizedBox(height: 10),
          bar(180),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty + error states
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surfaceHi,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_outlined,
              color: colors.brand,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'No active prescriptions found',
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: colors.title),
        ),
        const SizedBox(height: 6),
        Text(
          'Your issued digital care charts will appear here.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodyMd.copyWith(color: colors.body),
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
    final colors = context.appColors;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Center(
          child:
              Icon(Icons.cloud_off_outlined, size: 36, color: colors.muted),
        ),
        const SizedBox(height: 10),
        Text(
          "Couldn't load your prescriptions",
          textAlign: TextAlign.center,
          style: MtTextStyles.labelLg.copyWith(color: colors.title),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: colors.body),
        ),
        const SizedBox(height: 14),
        Center(
          child: ElevatedButton(
            onPressed: () => onRetry(),
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}
