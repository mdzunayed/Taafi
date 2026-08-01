import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/assigned_doctor.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../shared/presentation/widgets/active_chat_drawer.dart';

/// Read-only "Your Assigned Doctor" screen the patient reaches from the
/// Tracking tab once the admin has matched a doctor. Renders the full
/// professional profile: photo, verified badge, BMDC license, experience,
/// rating, and a single big Call Doctor CTA that triggers a `tel:` deep
/// link. A secondary "Message" button opens the real-time chat surface
/// scoped to the current appointment.
class ViewAssignedDoctorScreen extends ConsumerWidget {
  final AssignedDoctor doctor;
  final String? appointmentId;
  const ViewAssignedDoctorScreen({
    super.key,
    required this.doctor,
    this.appointmentId,
  });

  void _openChat(BuildContext context, String currentUserId) {
    final apptId = appointmentId;
    if (apptId == null || apptId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat is only available for active appointments.')),
      );
      return;
    }
    // Slide-in communication drawer — text/image/location chat plus the
    // in-header "Call via Secure Line" masked-calling button.
    openActiveChatDrawer(
      context,
      appointmentId: apptId,
      currentUserId: currentUserId,
      otherUserId: doctor.id,
      otherUserName: doctor.fullName,
      otherUserAvatarUrl: doctor.profilePicture,
      otherRoleLabel: 'Assigned Doctor',
    );
  }

  Future<void> _callDoctor(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = doctor.phone?.trim();
    if (phone == null || phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("This doctor's phone number is unavailable.")),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Your Assigned Doctor'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeaderCard(doctor: doctor),
            const SizedBox(height: 16),
            if ((doctor.bmdcLicense ?? '').isNotEmpty)
              _CredentialsBox(license: doctor.bmdcLicense!),
            if ((doctor.bmdcLicense ?? '').isNotEmpty)
              const SizedBox(height: 16),
            _StatsMatrix(doctor: doctor),
            if (doctor.experience.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Experience',
                child: Column(
                  children: [
                    for (int i = 0; i < doctor.experience.length; i++) ...[
                      _ExperienceRow(item: doctor.experience[i]),
                      if (i != doctor.experience.length - 1)
                        const Divider(height: 20, color: MtColors.line),
                    ],
                  ],
                ),
              ),
            ],
            if ((doctor.hospitalAffiliation ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Affiliation',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MtColors.brandSofter,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_hospital_outlined,
                        size: 18,
                        color: MtColors.brand,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doctor.hospitalAffiliation!,
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if ((doctor.bio ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'About',
                child: Text(
                  doctor.bio!,
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _CallButton(
              enabled: (doctor.phone ?? '').isNotEmpty,
              onPressed: () => _callDoctor(context),
            ),
            const SizedBox(height: 10),
            _MessageButton(
              enabled: currentUser != null &&
                  appointmentId != null &&
                  appointmentId!.isNotEmpty,
              onPressed: () {
                if (currentUser == null) return;
                _openChat(context, currentUser.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;
  const _MessageButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: MtColors.brand,
          side: const BorderSide(color: MtColors.brand),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.chat_bubble_outline, size: 20),
        label: Text(
          enabled ? 'Message Doctor' : 'Chat unavailable',
          style: MtTextStyles.labelLg.copyWith(color: MtColors.brand),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AssignedDoctor doctor;
  const _HeaderCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final url = doctor.profilePicture;
    Widget avatar;
    if (url != null && url.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          url,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: doctor.fullName,
            size: 88,
            backgroundColor: MtColors.brand,
            textColor: Colors.white,
          ),
        ),
      );
    } else {
      avatar = InitialsAvatar(
        name: doctor.fullName,
        size: 88,
        backgroundColor: MtColors.brand,
        textColor: Colors.white,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              if (doctor.isVerifiedDoctor)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: MtColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: MtColors.line),
                    ),
                    child: const Icon(
                      Icons.verified,
                      size: 22,
                      color: MtColors.brand,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            doctor.fullName,
            style: MtTextStyles.h1.copyWith(color: MtColors.ink),
            textAlign: TextAlign.center,
          ),
          if (doctor.specialty.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              doctor.specialty,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
              textAlign: TextAlign.center,
            ),
          ],
          if (doctor.isVerifiedDoctor) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MtColors.brandSofter,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MtColors.brandSoft),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified,
                    size: 14,
                    color: MtColors.brand,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Verified by Taafi',
                    style: MtTextStyles.bodySm.copyWith(
                      color: MtColors.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CredentialsBox extends StatelessWidget {
  final String license;
  const _CredentialsBox({required this.license});

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
            child: const Icon(
              Icons.badge_outlined,
              size: 20,
              color: MtColors.brand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BMDC LICENSE',
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  license,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: MtColors.brand,
          ),
        ],
      ),
    );
  }
}

class _StatsMatrix extends StatelessWidget {
  final AssignedDoctor doctor;
  const _StatsMatrix({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final years = doctor.yearsExperience > 0
        ? '${doctor.yearsExperience} yr'
        : '—';
    final rating = doctor.rating > 0
        ? doctor.rating.toStringAsFixed(1)
        : '—';
    final reviews = doctor.reviewCount > 0
        ? '${doctor.reviewCount}'
        : '—';

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
            iconColor: const Color(0xFFF59E0B),
            label: 'Rating',
            value: rating,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.reviews_outlined,
            label: 'Reviews',
            value: reviews,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
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
          Icon(icon, size: 22, color: iconColor ?? MtColors.brand),
          const SizedBox(height: 6),
          Text(
            value,
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: MtTextStyles.sectionLabel.copyWith(
              color: MtColors.ink3,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          child,
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
    return Row(
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
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
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
    );
  }
}

class _CallButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;
  const _CallButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MtColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MtColors.brandSoft,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.phone, size: 20),
        label: Text(
          enabled ? 'Call Doctor' : 'Phone unavailable',
          style: MtTextStyles.labelLg.copyWith(
            color: enabled ? Colors.white : MtColors.brand,
          ),
        ),
      ),
    );
  }
}
