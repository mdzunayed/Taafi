import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/doctor_profile.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../auth/auth_provider.dart';
import '../../admin_providers.dart';
import 'admin_table_chrome.dart';

/// Credential-review queue for a single provider role. Unlike the flat
/// Providers directory, this surfaces the actual registration credentials
/// (BMDC / BNMC number, degrees, institute affiliation, experience) so an
/// admin can review them before flipping the verification toggle. One
/// instance is mounted per role (doctor / nurse).
class ProviderVerificationTab extends ConsumerWidget {
  /// `'doctor'` or `'nurse'` — the backend Provider role to review.
  final String role;
  const ProviderVerificationTab({super.key, required this.role});

  bool get _isNurse => role == 'nurse';

  String get _licenseLabel => _isNurse ? 'BNMC registration' : 'BMDC registration';

  String _licenseOf(DoctorProfile p) =>
      _isNurse ? p.nursingLicense : p.bmdcLicense;

  Future<void> _toggle(
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
        content: Text(goingVerified
            ? '${provider.fullName} is now VERIFIED.'
            : '${provider.fullName} set back to PENDING.'),
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
    final title =
        _isNurse ? 'Nurse Verification Queue' : 'Doctor Verification Queue';
    return AdminListScaffold(
      title: title,
      subtitle: _isNurse
          ? 'Review BNMC registration, qualifications & institute before approving'
          : 'Review BMDC registration, degrees & affiliation before approving',
      onRefresh: () async {
        ref.invalidate(adminProvidersListProvider);
        await ref.read(adminProvidersListProvider.future);
      },
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(adminProvidersListProvider),
        ),
        data: (providers) {
          // Role-scoped, pending-first (the work queue floats to the top).
          final scoped = providers.where((p) => p.role == role).toList()
            ..sort((a, b) {
              if (a.isVerified == b.isVerified) {
                return a.fullName.compareTo(b.fullName);
              }
              return a.isVerified ? 1 : -1;
            });
          if (scoped.isEmpty) {
            return AdminEmptyState(
              icon: _isNurse
                  ? Icons.vaccines_outlined
                  : Icons.medical_information_outlined,
              title: 'No ${_isNurse ? 'nurses' : 'doctors'} to review',
              subtitle:
                  'Newly onboarded ${_isNurse ? 'nurses' : 'doctors'} appear here for credential review.',
            );
          }
          final pending = scoped.where((p) => !p.isVerified).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QueueSummary(total: scoped.length, pending: pending),
              const SizedBox(height: 16),
              for (final p in scoped) ...[
                _VerificationCard(
                  provider: p,
                  licenseLabel: _licenseLabel,
                  license: _licenseOf(p),
                  isNurse: _isNurse,
                  onToggle: () => _toggle(context, ref, p),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _QueueSummary extends StatelessWidget {
  final int total;
  final int pending;
  const _QueueSummary({required this.total, required this.pending});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _pill('$pending pending review', MtColors.pending, filled: pending > 0),
        const SizedBox(width: 10),
        _pill('${total - pending} verified', MtColors.completed),
      ],
    );
  }

  Widget _pill(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: MtTextStyles.labelSm.copyWith(
            color: filled ? Colors.white : color,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final DoctorProfile provider;
  final String licenseLabel;
  final String license;
  final bool isNurse;
  final VoidCallback onToggle;
  const _VerificationCard({
    required this.provider,
    required this.licenseLabel,
    required this.license,
    required this.isNurse,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final verified = p.isVerified;
    final missingLicense = license.trim().isEmpty;
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: identity + status ────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InitialsAvatar(name: p.fullName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName,
                          style: MtTextStyles.h3
                              .copyWith(color: MtColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                          [
                            if (p.specialization.isNotEmpty) p.specialization,
                            if (p.phone.isNotEmpty) p.phone,
                          ].join(' · '),
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink3)),
                    ],
                  ),
                ),
                _StatusChip(verified: verified),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: MtColors.line),
            const SizedBox(height: 16),
            // ── Credential grid ──────────────────────────────────────────
            Wrap(
              spacing: 28,
              runSpacing: 14,
              children: [
                _CredField(
                  label: licenseLabel,
                  value: missingLicense ? 'Not provided' : license,
                  warn: missingLicense,
                ),
                _CredField(
                  label: 'Qualifications',
                  value: p.degrees.isEmpty ? 'Not provided' : p.degrees,
                  warn: p.degrees.isEmpty,
                ),
                _CredField(
                  label: isNurse ? 'Institute' : 'Hospital affiliation',
                  value: p.hospitalAffiliation.isEmpty
                      ? 'Not provided'
                      : p.hospitalAffiliation,
                  warn: p.hospitalAffiliation.isEmpty,
                ),
                _CredField(
                  label: 'Experience',
                  value: '${p.yearsExperience} yr'
                      '${p.yearsExperience == 1 ? '' : 's'}',
                ),
                if (p.email.isNotEmpty)
                  _CredField(label: 'Email', value: p.email),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (missingLicense) ...[
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: MtColors.pending),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Missing ${licenseLabel.toLowerCase()} — confirm before approving.',
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.pending)),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 12),
                if (verified)
                  OutlinedButton.icon(
                    onPressed: onToggle,
                    icon: const Icon(Icons.undo, size: 16),
                    label: Text('Set to pending', style: MtTextStyles.labelMd),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MtColors.ink,
                      side: const BorderSide(color: MtColors.line),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: onToggle,
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: Text('Approve & verify',
                        style:
                            MtTextStyles.labelMd.copyWith(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MtColors.completed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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

class _CredField extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;
  const _CredField({
    required this.label,
    required this.value,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 3),
          Text(value,
              style: MtTextStyles.labelMd.copyWith(
                color: warn ? MtColors.pending : MtColors.ink,
              )),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool verified;
  const _StatusChip({required this.verified});

  @override
  Widget build(BuildContext context) {
    final color = verified ? MtColors.completed : MtColors.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified : Icons.pending_outlined,
              size: 14, color: color),
          const SizedBox(width: 5),
          Text(verified ? 'Verified' : 'Pending',
              style: MtTextStyles.labelSm.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}
