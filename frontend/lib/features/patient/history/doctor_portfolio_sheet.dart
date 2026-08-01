import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/assigned_doctor.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';

/// Premium slide-up modal showing the assigned doctor's professional
/// portfolio. Triggered from the doctor row inside a history card so
/// the patient can re-read the credentials of a provider they've
/// already worked with without leaving the History tab.
///
/// All fields except [name] are optional — missing values either fall
/// back to a graceful em-dash placeholder or hide their row entirely
/// so a partial backend payload still renders cleanly.
Future<void> showDoctorPortfolioSheet({
  required BuildContext context,
  required AssignedDoctor doctor,
  String? fallbackName,
  String? careType,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _DoctorPortfolioSheet(
      doctor: doctor,
      fallbackName: fallbackName,
      careType: careType,
    ),
  );
}

class _DoctorPortfolioSheet extends StatelessWidget {
  final AssignedDoctor doctor;
  final String? fallbackName;
  final String? careType;

  const _DoctorPortfolioSheet({
    required this.doctor,
    this.fallbackName,
    this.careType,
  });

  String get _name {
    final n = doctor.fullName.trim();
    if (n.isNotEmpty) return n;
    return (fallbackName ?? '').trim().isEmpty ? 'Provider' : fallbackName!;
  }

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = doctor.phone?.trim();
    if (phone == null || phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("This doctor's phone is unavailable.")),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open the dialer. Call $phone manually.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the dialer. Call $phone manually.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      _Header(
                        doctor: doctor,
                        name: _name,
                        careType: careType,
                      ),
                      const SizedBox(height: 16),
                      _StatsTriad(doctor: doctor),
                      const SizedBox(height: 16),
                      if ((doctor.bmdcLicense ?? '').isNotEmpty)
                        _CredentialTile(
                          icon: Icons.badge_outlined,
                          label: 'BMDC LICENSE',
                          value: doctor.bmdcLicense!,
                        ),
                      if ((doctor.hospitalAffiliation ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _CredentialTile(
                          icon: Icons.local_hospital_outlined,
                          label: 'AFFILIATION',
                          value: doctor.hospitalAffiliation!,
                        ),
                      ],
                      if (doctor.experience.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _SectionLabel(label: 'Experience'),
                        const SizedBox(height: 8),
                        _ExperienceList(rows: doctor.experience),
                      ],
                      if ((doctor.bio ?? '').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _SectionLabel(label: 'About'),
                        const SizedBox(height: 8),
                        Text(
                          doctor.bio!,
                          style: MtTextStyles.bodyMd
                              .copyWith(color: MtColors.ink2, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _ActionRow(
                        canCall: (doctor.phone ?? '').isNotEmpty,
                        onCall: () => _call(context),
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final AssignedDoctor doctor;
  final String name;
  final String? careType;

  const _Header({
    required this.doctor,
    required this.name,
    required this.careType,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfilePicture(doctor: doctor, name: name),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: MtTextStyles.h2.copyWith(color: MtColors.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (doctor.isVerifiedDoctor) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified,
                        size: 18, color: MtColors.brand),
                  ],
                ],
              ),
              if (doctor.specialty.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  doctor.specialty,
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
              ],
              if ((careType ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MtColors.brandSofter,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    careType!,
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.brand,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfilePicture extends StatelessWidget {
  final AssignedDoctor doctor;
  final String name;
  const _ProfilePicture({required this.doctor, required this.name});

  @override
  Widget build(BuildContext context) {
    final url = doctor.profilePicture;
    Widget child;
    if (url != null && url.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          url,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: name,
            size: 72,
            backgroundColor: MtColors.brandSoft,
            textColor: MtColors.brand,
          ),
        ),
      );
    } else {
      child = InitialsAvatar(
        name: name,
        size: 72,
        backgroundColor: MtColors.brandSoft,
        textColor: MtColors.brand,
      );
    }
    if (!doctor.isVerifiedDoctor) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified, size: 18, color: MtColors.brand),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats triad (experience · rating · consultation fee)
// ---------------------------------------------------------------------------

class _StatsTriad extends StatelessWidget {
  final AssignedDoctor doctor;
  const _StatsTriad({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final years = doctor.yearsExperience > 0
        ? '${doctor.yearsExperience} yr'
        : '—';
    final rating =
        doctor.rating > 0 ? doctor.rating.toStringAsFixed(1) : '—';
    final fee = doctor.fee > 0 ? '৳${doctor.fee.toStringAsFixed(0)}' : '—';
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.workspace_premium_outlined,
            label: 'Experience',
            value: years,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.star_rounded,
            accent: const Color(0xFFF59E0B),
            label: 'Rating',
            value: rating,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.payments_outlined,
            label: 'Consult fee',
            value: fee,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color? accent;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: accent ?? MtColors.brand),
          const SizedBox(height: 6),
          Text(value,
              style: MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
          const SizedBox(height: 2),
          Text(label,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Credential tile + experience rows
// ---------------------------------------------------------------------------

class _CredentialTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CredentialTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: MtColors.brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value,
                    style: MtTextStyles.labelLg
                        .copyWith(color: MtColors.ink)),
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

class _ExperienceList extends StatelessWidget {
  final List<AssignedDoctorExperience> rows;
  const _ExperienceList({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _ExperienceRow(item: rows[i]),
            if (i != rows.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: MtColors.line,
                indent: 14,
                endIndent: 14,
              ),
          ],
        ],
      ),
    );
  }
}

class _ExperienceRow extends StatelessWidget {
  final AssignedDoctorExperience item;
  const _ExperienceRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              size: 16,
              color: MtColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.designation.isNotEmpty
                      ? item.designation
                      : item.hospitalName,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
                if (item.designation.isNotEmpty &&
                    item.hospitalName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.hospitalName,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink2),
                  ),
                ],
              ],
            ),
          ),
          if (item.years > 0)
            Text(
              '${item.years} yr',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer actions
// ---------------------------------------------------------------------------

class _ActionRow extends StatelessWidget {
  final bool canCall;
  final VoidCallback onCall;
  final VoidCallback onClose;
  const _ActionRow({
    required this.canCall,
    required this.onCall,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onClose,
            style: OutlinedButton.styleFrom(
              foregroundColor: MtColors.ink2,
              side: const BorderSide(color: MtColors.line),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Close',
                style: MtTextStyles.labelLg.copyWith(color: MtColors.ink2)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: canCall ? onCall : null,
            icon: const Icon(Icons.phone, size: 18),
            label: Text(
              canCall ? 'Call doctor' : 'Phone unavailable',
              style: MtTextStyles.labelLg.copyWith(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MtColors.brandSoft,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
