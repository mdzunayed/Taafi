import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/prescription.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../../prescriptions/prescription_release_gate.dart';
import '../../prescriptions/prescriptions_provider.dart';
import 'prescription_detail_screen.dart';

/// Secure prescription vault — the patient's full historical repository of
/// scripts issued by platform physicians. Tapping a row opens the typeset
/// digital prescription card.
class PrescriptionVaultScreen extends ConsumerWidget {
  const PrescriptionVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientPrescriptionVaultProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Prescription Vault',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
      ),
      body: RefreshIndicator(
        color: MtColors.brand,
        onRefresh: () async => ref.invalidate(patientPrescriptionVaultProvider),
        child: async.when(
          loading: () => const _VaultSkeletonList(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MtErrorState(
                title: "Couldn't load prescriptions",
                message: e.toString(),
                onRetry: () =>
                    ref.invalidate(patientPrescriptionVaultProvider),
              ),
            ],
          ),
          data: (scripts) {
            if (scripts.isEmpty) return const _VaultEmpty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: scripts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _VaultCard(script: scripts[i]),
            );
          },
        ),
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  final Prescription script;
  const _VaultCard({required this.script});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM y').format(script.issuedAt);
    // On a locked script `items` arrives server-redacted; the count
    // rides in separately so the card can still say "N medications".
    final count = script.effectiveItemCount;
    final locked = script.locked;
    final chip = releaseChipColors(script.releaseStatus);
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PrescriptionDetailScreen(prescriptionId: script.id),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: locked ? chip.bg : MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  locked ? Icons.lock_outline : Icons.description_outlined,
                  color: locked ? chip.fg : MtColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Diagnosis is server-redacted while locked.
                      locked
                          ? 'Locked prescription'
                          : (script.diagnosis.isEmpty
                              ? 'Prescription'
                              : script.diagnosis),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.labelLg.copyWith(
                          color: MtColors.ink, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${script.doctorName.isEmpty ? 'Attending physician' : script.doctorName} · $date',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink3),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          count == 1 ? '1 medication' : '$count medications',
                          style: MtTextStyles.labelSm
                              .copyWith(color: MtColors.brand),
                        ),
                        if (locked) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: chip.bg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                releaseChipLabel(script),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MtTextStyles.labelSm.copyWith(
                                  color: chip.fg,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: MtColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton ────────────────────────────────────────────────────────────────

class _VaultSkeletonList extends StatelessWidget {
  const _VaultSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ShimmerLoadingPlaceholder(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            children: [
              const ShimmerBox(
                  width: 46,
                  height: 46,
                  borderRadius: BorderRadius.all(Radius.circular(12))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox.line(width: 180, height: 16),
                    const SizedBox(height: 8),
                    ShimmerBox.line(width: 220, height: 12),
                    const SizedBox(height: 8),
                    ShimmerBox.line(width: 90, height: 12),
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

class _VaultEmpty extends StatelessWidget {
  const _VaultEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.folder_open_outlined,
            size: 46, color: MtColors.ink3.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('No prescriptions yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 4),
        Text(
          'Scripts issued by your doctor will be securely stored here.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
      ],
    );
  }
}
