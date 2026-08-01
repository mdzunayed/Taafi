import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/models/recent_provider.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/widgets/mt_empty_state.dart';

class ProviderProfileScreen extends StatelessWidget {
  final RecentProvider? provider;

  const ProviderProfileScreen({super.key, this.provider});

  String _lastVisitLabel(DateTime? when) {
    if (when == null) return 'No previous visits';
    final diff = DateTime.now().difference(when);
    if (diff.inDays < 1) return 'Last visit today';
    if (diff.inDays < 7) return 'Last visit ${diff.inDays}d ago';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return 'Last visit ${weeks}w ago';
    }
    return 'Last visit ${DateFormat('MMM d, y').format(when)}';
  }

  Future<void> _contactSupport(BuildContext context) async {
    final digits = SupportConfig.supportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final name = provider?.name ?? 'a provider';
    final text = Uri.encodeComponent(
      'Hi Taafi, I would like to know more about $name.',
    );
    final uri = Uri.parse('https://wa.me/$digits?text=$text');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open WhatsApp. Reach us at ${SupportConfig.supportPhoneDisplay}',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open WhatsApp. Reach us at ${SupportConfig.supportPhoneDisplay}',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = provider;
    return Scaffold(
      backgroundColor: MtColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: 'Provider profile',
              onBack: () => Navigator.of(context).pop(),
            ),
            if (p == null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: MtEmptyState(
                      icon: Icons.person_off_outlined,
                      title: 'Provider details unavailable',
                      subtitle:
                          "We couldn't find this provider in your recent list. "
                          "Try again from a recent visit or contact support.",
                      actionLabel: 'Contact support',
                      onAction: () => _contactSupport(context),
                    ),
                  ),
                ),
              )
            else ...[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _HeroCard(provider: p),
                    const SizedBox(height: 16),
                    _StatRow(provider: p, lastVisitLabel: _lastVisitLabel(p.lastVisitAt)),
                    const SizedBox(height: 20),
                    Text(
                      'About',
                      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: MtColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MtColors.line),
                      ),
                      child: Text(
                        _aboutText(p),
                        style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                onContact: () => _contactSupport(context),
                onBookAgain: () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _aboutText(RecentProvider p) {
    final spec = p.specialization.isNotEmpty ? p.specialization : 'Clinician';
    final years = p.yearsExperience;
    if (years <= 0) {
      return '$spec on the Taafi panel, available for home visits.';
    }
    return '$spec with $years+ years of clinical experience. '
        'Available for home visits through Taafi.';
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _Header({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MtColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MtColors.ink),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Text(title, style: MtTextStyles.h3),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final RecentProvider provider;

  const _HeroCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final spec = provider.specialization;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(
            name: provider.name.replaceFirst('Dr. ', ''),
            size: 64,
            backgroundColor: MtColors.brandSoft,
            textColor: MtColors.brand,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                ),
                if (spec.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    spec,
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                  ),
                ],
                const SizedBox(height: 10),
                if (provider.yearsExperience > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MtColors.brandSofter,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${provider.yearsExperience}+ years experience',
                      style: MtTextStyles.labelSm.copyWith(
                        color: MtColors.brand700,
                      ),
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

class _StatRow extends StatelessWidget {
  final RecentProvider provider;
  final String lastVisitLabel;

  const _StatRow({required this.provider, required this.lastVisitLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFF59E0B),
            primary: provider.rating.toStringAsFixed(1),
            secondary: provider.reviewCount != null
                ? '${provider.reviewCount} reviews'
                : 'Patient rating',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.event_outlined,
            iconColor: MtColors.brand,
            primary: provider.lastVisitAt == null ? '—' : 'Recent',
            secondary: lastVisitLabel,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String primary;
  final String secondary;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(
            primary,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onContact;
  final VoidCallback onBookAgain;

  const _ActionBar({required this.onContact, required this.onBookAgain});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('Contact support', style: MtTextStyles.labelMd),
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.brand,
                side: const BorderSide(color: MtColors.brand),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MtButton(
              label: 'Book again',
              leadingIcon: Icons.event_available,
              onPressed: onBookAgain,
            ),
          ),
        ],
      ),
    );
  }
}
