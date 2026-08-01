import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../navigation/patient_nav_provider.dart';
import 'faq_screen.dart';
import 'patient_profile_screen.dart';
import 'address_book_screen.dart';
import 'family_profiles_screen.dart';
import 'prescription_vault_screen.dart';
import 'service_catalog_screen.dart';

/// Account / "Me" tab in the new patient bottom-nav shell. Consolidates
/// profile preview, edit shortcut, support links, and the Sign out
/// action — all of which used to live on the cluttered top-right
/// corner of the dashboard.
class PatientAccountScreen extends ConsumerWidget {
  const PatientAccountScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final c = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need to sign in again to check your active request and bookings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel',
                style: MtTextStyles.labelMd.copyWith(color: c.body)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.brand),
            child: Text('Sign out', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  Future<void> _callSupport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the dialer. Call ${SupportConfig.supportPhoneDisplay} manually.',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialer. Call ${SupportConfig.supportPhoneDisplay} manually.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = user?.name.trim().isNotEmpty == true ? user!.name : 'Patient';
    final phoneDisplay = user?.phone.isNotEmpty == true ? user!.phone : '—';
    final emailDisplay =
        (user?.email ?? '').trim().isNotEmpty ? user!.email : null;
    final c = context.appColors;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        onPressed: () => ref.goToHome(),
                        icon: Icon(Icons.arrow_back, color: c.accent),
                        tooltip: 'Back to home',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account',
                            style: MtTextStyles.h1.copyWith(color: c.title),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'অ্যাকাউন্ট',
                            style: MtTextStyles.bodySm.copyWith(
                              color: c.body,
                              fontFamily: 'Kalpurush',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ProfileSummaryCard(
                  name: name,
                  phone: phoneDisplay,
                  email: emailDisplay,
                  onView: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PatientProfileScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _SectionHeader(label: 'Profile'),
                const SizedBox(height: 8),
                _MenuCard(
                  children: [
                    _MenuTile(
                      icon: Icons.person_outline,
                      title: 'Edit profile',
                      subtitle: 'Name, contact info, address',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PatientProfileScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(label: 'Preferences'),
                const SizedBox(height: 8),
                _MenuCard(
                  children: [
                    _DarkModeTile(
                      value: isDark,
                      onChanged: (_) => ref
                          .read(themeModeProvider.notifier)
                          .toggleTheme(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(label: 'Health & records'),
                const SizedBox(height: 8),
                _MenuCard(
                  children: [
                    _MenuTile(
                      icon: Icons.description_outlined,
                      title: 'My Prescriptions',
                      subtitle: 'Your secure prescription vault',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PrescriptionVaultScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuTile(
                      icon: Icons.medical_services_outlined,
                      title: 'Browse services',
                      subtitle: 'Catalog of home-care visits & pricing',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ServiceCatalogScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuTile(
                      icon: Icons.location_on_outlined,
                      title: 'Address Book',
                      subtitle: 'Saved addresses for faster checkout',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddressBookScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuTile(
                      icon: Icons.family_restroom,
                      title: 'Family Profiles',
                      subtitle: 'Book care for dependents',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FamilyProfilesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(label: 'Support'),
                const SizedBox(height: 8),
                _MenuCard(
                  children: [
                    _MenuTile(
                      icon: Icons.help_outline,
                      title: 'Help & FAQs',
                      subtitle: 'Common questions answered',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FaqScreen(),
                        ),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.phone_in_talk_outlined,
                      title: 'Call helpline',
                      subtitle: SupportConfig.supportPhoneDisplay,
                      onTap: () => _callSupport(context),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SignOutButton(onPressed: () => _confirmSignOut(context, ref)),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    'Taafi · v1.0',
                    style: MtTextStyles.bodySm.copyWith(color: c.muted),
                  ),
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
// Sub-widgets
// ---------------------------------------------------------------------------

class _ProfileSummaryCard extends StatelessWidget {
  final String name;
  final String phone;
  final String? email;
  final VoidCallback onView;

  const _ProfileSummaryCard({
    required this.name,
    required this.phone,
    required this.email,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          InitialsAvatar(
            name: name,
            size: 56,
            backgroundColor: c.brand.withValues(alpha: 0.16),
            textColor: c.brand,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: MtTextStyles.labelLg.copyWith(
                    color: c.title,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
                if (email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: MtTextStyles.bodySm.copyWith(color: c.body),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              foregroundColor: c.brand,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View',
                    style: MtTextStyles.labelMd.copyWith(
                        color: c.brand, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 16, color: c.brand),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel.copyWith(
        color: context.appColors.muted,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: c.cardBorder,
                indent: 60,
              ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: c.brand, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: MtTextStyles.labelLg.copyWith(
                      color: c.title,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: MtTextStyles.bodySm.copyWith(color: c.body),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.muted, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Preferences tile with an animated switch that flips the app theme instantly.
class _DarkModeTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _DarkModeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            // Icon crossfades between a sun and a moon as the theme flips.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  value ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  key: ValueKey(value),
                  color: c.brand,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dark Mode',
                    style: MtTextStyles.labelLg.copyWith(
                      color: c.title,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ? 'On — midnight theme' : 'Off — light theme',
                    style: MtTextStyles.bodySm.copyWith(color: c.body),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: c.brand,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  final Future<void> Function() onPressed;
  const _SignOutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final danger = context.appColors.danger;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => onPressed(),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger,
          side: BorderSide(color: danger),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.logout, size: 18),
        label: Text(
          'Sign out',
          style: MtTextStyles.labelLg.copyWith(
            color: danger,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
