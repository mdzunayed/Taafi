import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/models/doctor_profile.dart';
import '../presentation/controllers/doctor_nav_controller.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/image_upload.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../doctor_providers.dart';
import '../services/location_tracking_service.dart';

final _doctorMoneyFmt = NumberFormat('#,###', 'en_US');
String _doctorMoney(num n) => '৳${_doctorMoneyFmt.format(n.round())}';

/// AsyncNotifier backing the Doctor Profile screen.
///
/// Lifecycle:
///   • `build()` calls `GET /doctor/profile?doctor_id=<currentUser.id>`.
///   • [refresh] re-runs the GET.
///   • [save] patches editable fields (whitelisted server-side too).
///   • [setAvailability] fires `PATCH /doctor/availability`, mirrors the
///     change into the legacy `doctorAvailabilityProvider` + GPS tracker,
///     and updates local state so the AppBar chip flips instantly.
class DoctorProfileNotifier
    extends AutoDisposeAsyncNotifier<DoctorProfile> {
  @override
  Future<DoctorProfile> build() async {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      throw StateError('Not signed in');
    }
    return ref.read(dioClientProvider).getDoctorProfile(user.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('Not signed in');
      return ref.read(dioClientProvider).getDoctorProfile(user.id);
    });
  }

  Future<DoctorProfile> save(Map<String, dynamic> updates) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Not signed in');
    final fresh = await ref
        .read(dioClientProvider)
        .updateDoctorProfile(user.id, updates);
    state = AsyncData(fresh);
    return fresh;
  }

  /// Canonical "update my profile" path — POSTs camelCase keys to
  /// `PUT /api/users/:id/profile`. Use this for new call sites; the
  /// legacy `_EditDoctorSheet` still calls [save] for back-compat.
  Future<DoctorProfile> updateProfessionalDetails(
    Map<String, dynamic> updates,
  ) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Not signed in');
    final fresh = await ref
        .read(dioClientProvider)
        .updateProfessionalDetails(user.id, updates);
    state = AsyncData(fresh);
    return fresh;
  }

  /// Uploads a picked image to `/api/users/:id/upload-avatar`, then
  /// swaps the resulting URL into local state so the avatar repaints
  /// on the next frame without a full profile re-fetch.
  Future<String> uploadAvatar({
    required List<int> bytes,
    String filename = 'avatar.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Not signed in');
    final url = await ref.read(dioClientProvider).uploadProfilePicture(
          userId: user.id,
          bytes: Uint8List.fromList(bytes),
          filename: filename,
          mimeType: mimeType,
        );
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(profilePicture: url));
    }
    return url;
  }

  /// Optimistic availability toggle. Flips the chip instantly so the
  /// Switch feels responsive, rolls back if the PATCH fails. Also
  /// starts/stops [LocationTrackingService] so GPS coordinates flow
  /// only while ONLINE.
  Future<void> setAvailability(bool online) async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('Not signed in');
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(availabilityStatus: online ? 'online' : 'offline'),
    );
    final tracker = ref.read(locationTrackingServiceProvider);
    try {
      await ref
          .read(dioClientProvider)
          .setAvailability(online, doctorId: user.id);
      if (online) {
        await tracker.start();
      } else {
        await tracker.stop();
      }
    } catch (e) {
      // Roll back so the chip never lies to the doctor.
      state = AsyncData(current);
      rethrow;
    }
  }
}

final doctorProfileProvider = AsyncNotifierProvider.autoDispose<
    DoctorProfileNotifier, DoctorProfile>(DoctorProfileNotifier.new);

class DoctorProfileScreen extends ConsumerWidget {
  const DoctorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorProfileProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MtColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('My profile', style: MtTextStyles.h3),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: MtColors.ink3),
            onPressed: () =>
                ref.read(doctorProfileProvider.notifier).refresh(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MtColors.brand),
        ),
        error: (e, _) => _DoctorProfileError(
          message: e.toString(),
          onRetry: () =>
              ref.read(doctorProfileProvider.notifier).refresh(),
        ),
        data: (profile) => _DoctorProfileBody(profile: profile),
      ),
    );
  }
}

class _DoctorProfileError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _DoctorProfileError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: MtColors.ink3),
            const SizedBox(height: 12),
            Text('Could not load profile',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorProfileBody extends ConsumerWidget {
  final DoctorProfile profile;
  const _DoctorProfileBody({required this.profile});

  Future<void> _onEdit(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditDoctorSheet(profile: profile),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: MtColors.completed,
        ),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign out?', style: MtTextStyles.h3),
        content: Text(
          'You will need to sign in again to receive new assignments.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: Text('Sign out', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  Future<void> _onContactSupport(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Call ${SupportConfig.supportPhoneDisplay}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () =>
          ref.read(doctorProfileProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _DoctorHeader(profile: profile),
          const SizedBox(height: 16),
          _StatsTriad(profile: profile),
          const SizedBox(height: 16),
          const _AvailabilityCard(),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BioCard(bio: profile.bio),
          ],
          const SizedBox(height: 16),
          _PracticeCard(
            profile: profile,
            onEdit: () => _onEdit(context, ref),
          ),
          const SizedBox(height: 16),
          _ContactCard(
            profile: profile,
            onEdit: () => _onEdit(context, ref),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Account'),
          const SizedBox(height: 8),
          _MenuCard(
            children: [
              _MenuTile(
                icon: Icons.edit_outlined,
                label: 'Edit Professional Details',
                onTap: () {
                  HapticFeedback.lightImpact();
                  _onEdit(context, ref);
                },
              ),
              _MenuTile(
                icon: Icons.calendar_month_outlined,
                label: 'My Schedule & Availability',
                onTap: () {
                  HapticFeedback.lightImpact();
                  // Switch the workspace shell to the Schedule tab, then pop
                  // this pushed profile route to reveal it. doctorNavProvider
                  // persists across the pop, so the shell rebuilds on tab 3.
                  ref
                      .read(doctorNavProvider.notifier)
                      .select(DoctorTab.schedule.index);
                  Navigator.of(context).pop();
                },
              ),
              _MenuTile(
                icon: Icons.payments_outlined,
                label: 'Earnings Dashboard',
                onTap: () {
                  HapticFeedback.lightImpact();
                  // Land on the Earnings & Analytics performance workspace.
                  ref
                      .read(doctorNavProvider.notifier)
                      .select(DoctorTab.earnings.index);
                  Navigator.of(context).pop();
                },
              ),
              _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push('/settings');
                },
              ),
              _MenuTile(
                icon: Icons.support_agent,
                label: 'Help & Support',
                subtitle: SupportConfig.supportPhoneDisplay,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _onContactSupport(context);
                },
              ),
              _MenuTile(
                icon: Icons.logout,
                label: 'Logout',
                iconColor: MtColors.rejected,
                labelColor: MtColors.rejected,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _confirmSignOut(context, ref);
                },
                isLast: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Premium-redesign header: centered avatar + name (+ verified badge)
/// + specialty/hospital subtitle. The previous left-aligned row layout
/// is gone; the 3-card stats row now lives in [_StatsTriad] below.
class _DoctorHeader extends StatelessWidget {
  final DoctorProfile profile;
  const _DoctorHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (profile.specialization.isNotEmpty) profile.specialization,
      if (profile.hospitalAffiliation.isNotEmpty)
        profile.hospitalAffiliation,
    ];
    final subtitle = subtitleParts.join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _AvatarUploader(profile: profile),
          const SizedBox(height: 14),
          // Name + inline verified checkmark. `mainAxisSize: min` keeps
          // the badge tight to the name without forcing the Row across
          // the full width on long names.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  profile.fullName.isEmpty ? 'Doctor' : profile.fullName,
                  style: MtTextStyles.h1.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.isVerifiedDoctor) ...[
                const SizedBox(width: 6),
                const _VerifiedBadge(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.green.shade700, size: 14),
                const SizedBox(width: 4),
                Text(
                  'BMDC Verified',
                  style: MtTextStyles.labelSm.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small filled circle with a white check — sits inline with the
/// doctor's name on the Profile hero when `isVerifiedDoctor` is true.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Verified by Taafi',
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFF1D9BF0), // social-style verified blue
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 12),
      ),
    );
  }
}

/// 3-card stats row rendered just below the hero header. "Patients"
/// reuses the existing reviewCount metric — each completed visit that
/// can be rated comes from a unique patient, so it's a close-enough
/// proxy until we add a dedicated `patients_served` counter.
class _StatsTriad extends StatelessWidget {
  final DoctorProfile profile;
  const _StatsTriad({required this.profile});

  /// 1234 → "1.2k", 980 → "980". Drops the decimal when it would be ".0".
  String _formatPatients(int n) {
    if (n < 1000) return n.toString();
    final k = n / 1000;
    final shown = k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '${shown}k+';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.work_history_outlined,
            value: profile.yearsExperience > 0
                ? '${profile.yearsExperience}+ Years'
                : 'New',
            label: 'Experience',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.favorite_outline,
            value: profile.reviewCount > 0
                ? _formatPatients(profile.reviewCount)
                : '0',
            label: 'Patients',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFF59E0B),
            value: '${profile.rating.toStringAsFixed(1)} ★',
            label: 'Rating',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  /// Overrides the default brand-orange icon color. The Rating card
  /// uses amber to read as "star-rating" not "brand metric".
  final Color? iconColor;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.brandSoft.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor ?? MtColors.brand, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: MtTextStyles.labelLg.copyWith(
              color: MtColors.ink,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: MtTextStyles.labelSm.copyWith(
              color: MtColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// "About me" card. Hidden when the doctor hasn't written a bio yet
/// so we don't render an empty container — they fill it via Edit.
class _BioCard extends StatelessWidget {
  final String bio;
  const _BioCard({required this.bio});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About me',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            bio,
            style: MtTextStyles.bodyMd
                .copyWith(color: MtColors.ink2, height: 1.45),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu card — single Card container with ListTile rows + chevron
// trailing icons, the premium pattern the spec calls for.
// ---------------------------------------------------------------------------

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  /// Optional override for the leading icon (defaults to brand orange).
  final Color? iconColor;
  /// Optional override for the label color (used for the destructive
  /// Logout row to read red).
  final Color? labelColor;
  /// Suppresses the bottom divider on the last row in the card.
  final bool isLast;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.labelColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = iconColor ?? MtColors.brand;
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: effectiveIcon.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: effectiveIcon, size: 18),
          ),
          title: Text(
            label,
            style: MtTextStyles.labelLg
                .copyWith(color: labelColor ?? MtColors.ink),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style:
                      MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
          trailing: const Icon(Icons.chevron_right,
              color: MtColors.ink3, size: 22),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            color: MtColors.line,
            indent: 64,
            endIndent: 16,
          ),
      ],
    );
  }
}

/// Prominent availability switch. Highlighted in brand color when ONLINE
/// so a doctor scanning the screen knows their dispatch status at a glance.
class _AvailabilityCard extends ConsumerWidget {
  const _AvailabilityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorProfileProvider);
    final profile = async.valueOrNull;
    final isOnline = profile?.isOnline ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOnline ? MtColors.brand : MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline ? MtColors.brand : MtColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOnline
                  ? Colors.white.withValues(alpha: 0.18)
                  : MtColors.brandSofter,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isOnline ? Icons.bolt : Icons.bolt_outlined,
              color: isOnline ? Colors.white : MtColors.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Online — taking visits' : 'Offline',
                  style: MtTextStyles.labelLg.copyWith(
                    color: isOnline ? Colors.white : MtColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline
                      ? 'Admin can dispatch a request to you right now.'
                      : 'Toggle on to start receiving new assignments.',
                  style: MtTextStyles.bodySm.copyWith(
                    color: isOnline
                        ? Colors.white.withValues(alpha: 0.85)
                        : MtColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AvailabilityToggle(isOnline: isOnline),
        ],
      ),
    );
  }
}

class _AvailabilityToggle extends ConsumerStatefulWidget {
  final bool isOnline;
  const _AvailabilityToggle({required this.isOnline});

  @override
  ConsumerState<_AvailabilityToggle> createState() =>
      _AvailabilityToggleState();
}

class _AvailabilityToggleState extends ConsumerState<_AvailabilityToggle> {
  bool _busy = false;

  Future<void> _onChanged(bool value) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await ref
          .read(doctorProfileProvider.notifier)
          .setAvailability(value);
      // Keep the legacy dashboard chip in lockstep so the Dashboard tab
      // doesn't show a stale availability while the profile is live.
      // ignore: unused_result
      ref.invalidate(doctorAvailabilityProvider);
      ref.invalidate(doctorDashboardProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update availability: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Switch.adaptive(
      value: widget.isOnline,
      onChanged: _onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: Colors.white.withValues(alpha: 0.45),
      inactiveThumbColor: MtColors.ink3,
      inactiveTrackColor: MtColors.line,
    );
  }
}

class _PracticeCard extends StatelessWidget {
  final DoctorProfile profile;
  final VoidCallback onEdit;
  const _PracticeCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Practice',
      onEdit: onEdit,
      rows: [
        _DetailRow(
          icon: Icons.local_hospital_outlined,
          label: 'Specialization',
          value: profile.specialization.isEmpty ? '—' : profile.specialization,
        ),
        if (profile.specialty.isNotEmpty)
          _DetailRow(
            icon: Icons.medical_information_outlined,
            label: 'Specialty',
            value: profile.specialty,
          ),
        _DetailRow(
          icon: Icons.payments_outlined,
          label: 'Default fee',
          value: _doctorMoney(profile.fee),
        ),
        _DetailRow(
          icon: Icons.map_outlined,
          label: 'Service radius',
          value:
              '${profile.serviceRadiusKm.toStringAsFixed(profile.serviceRadiusKm % 1 == 0 ? 0 : 1)} km',
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  final DoctorProfile profile;
  final VoidCallback onEdit;
  const _ContactCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Contact',
      onEdit: onEdit,
      rows: [
        _DetailRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: profile.email.isEmpty ? '—' : profile.email,
        ),
        _DetailRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: profile.phone.isEmpty ? '—' : profile.phone,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<Widget> rows;
  const _Card({
    required this.title,
    required this.onEdit,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: MtTextStyles.labelLg),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text('Edit', style: MtTextStyles.labelMd),
                  style: TextButton.styleFrom(foregroundColor: MtColors.brand),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: MtColors.line, indent: 56),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: MtColors.brand, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: MtTextStyles.sectionLabel.copyWith(
          color: MtColors.ink3,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit sheet — covers contact info, professional details, bio.
// ---------------------------------------------------------------------------

class _EditDoctorSheet extends ConsumerStatefulWidget {
  final DoctorProfile profile;
  const _EditDoctorSheet({required this.profile});

  @override
  ConsumerState<_EditDoctorSheet> createState() => _EditDoctorSheetState();
}

class _EditDoctorSheetState extends ConsumerState<_EditDoctorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _specialization;
  late final TextEditingController _degrees;
  late final TextEditingController _hospital;
  late final TextEditingController _fee;
  late final TextEditingController _radius;
  late final TextEditingController _bio;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _email = TextEditingController(text: widget.profile.email);
    _phone = TextEditingController(text: widget.profile.phone);
    _specialization =
        TextEditingController(text: widget.profile.specialization);
    _degrees = TextEditingController(text: widget.profile.degrees);
    _hospital =
        TextEditingController(text: widget.profile.hospitalAffiliation);
    _fee = TextEditingController(text: widget.profile.fee.toString());
    _radius = TextEditingController(
      text: widget.profile.serviceRadiusKm.toString(),
    );
    _bio = TextEditingController(text: widget.profile.bio);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _specialization.dispose();
    _degrees.dispose();
    _hospital.dispose();
    _fee.dispose();
    _radius.dispose();
    _bio.dispose();
    super.dispose();
  }

  Map<String, dynamic> _diff() {
    final out = <String, dynamic>{};
    final newName = _name.text.trim();
    final newEmail = _email.text.trim();
    final newPhone = _phone.text.trim();
    final newSpec = _specialization.text.trim();
    final newDegrees = _degrees.text.trim();
    final newHospital = _hospital.text.trim();
    final newFee = num.tryParse(_fee.text.trim());
    final newRadius = num.tryParse(_radius.text.trim());
    final newBio = _bio.text.trim();
    if (newName != widget.profile.fullName) out['full_name'] = newName;
    if (newEmail != widget.profile.email) out['email'] = newEmail;
    if (newPhone != widget.profile.phone) out['phone'] = newPhone;
    if (newSpec != widget.profile.specialization) {
      out['specialization'] = newSpec;
    }
    if (newDegrees != widget.profile.degrees) {
      out['degrees'] = newDegrees;
    }
    if (newHospital != widget.profile.hospitalAffiliation) {
      out['hospital_affiliation'] = newHospital;
    }
    if (newFee != null && newFee != widget.profile.fee) {
      out['fee'] = newFee;
    }
    if (newRadius != null && newRadius != widget.profile.serviceRadiusKm) {
      out['service_radius_km'] = newRadius;
    }
    if (newBio != widget.profile.bio) out['bio'] = newBio;
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final updates = _diff();
    if (updates.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      // Route through the new PUT /api/users/:id/profile endpoint so
      // identity fields land on Account and professional fields land
      // on Provider (parallel write). The legacy save() path only
      // touched Provider and silently no-op'd when the session id was
      // an Account id — the exact bug that caused "Doctor not found".
      await ref
          .read(doctorProfileProvider.notifier)
          .updateProfessionalDetails(updates);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MtColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Edit profile',
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                  const SizedBox(height: 14),
                  _DoctorTextField(
                    controller: _name,
                    label: 'Full name',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _DoctorTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Required';
                      if (!value.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _DoctorTextField(
                    controller: _phone,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _DoctorTextField(
                    controller: _specialization,
                    label: 'Specialization',
                    icon: Icons.local_hospital_outlined,
                  ),
                  const SizedBox(height: 12),
                  _DoctorTextField(
                    controller: _degrees,
                    label: 'Degrees / qualifications',
                    hint: 'MBBS, FCPS (Medicine)',
                    icon: Icons.school_outlined,
                  ),
                  const SizedBox(height: 12),
                  _DoctorTextField(
                    controller: _hospital,
                    label: 'Hospital affiliation',
                    icon: Icons.business_outlined,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DoctorTextField(
                          controller: _fee,
                          label: 'Default fee (BDT)',
                          icon: Icons.payments_outlined,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return null;
                            return num.tryParse(v!.trim()) == null
                                ? 'Number'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DoctorTextField(
                          controller: _radius,
                          label: 'Radius (km)',
                          icon: Icons.map_outlined,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return null;
                            return num.tryParse(v!.trim()) == null
                                ? 'Number'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Multi-line bio. Capped at ~2000 chars on the
                  // backend; we don't enforce that here so the doctor
                  // sees the trailing characters as they type and the
                  // server's `maxlength` is the final word.
                  _DoctorTextField(
                    controller: _bio,
                    label: 'About me / bio',
                    icon: Icons.notes_outlined,
                    keyboardType: TextInputType.multiline,
                    maxLines: 5,
                    minLines: 3,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      _saving ? 'Saving…' : 'Save changes',
                      style:
                          MtTextStyles.labelLg.copyWith(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MtColors.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          MtColors.brand.withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar uploader — interactive ring around the doctor's profile photo.
//
// Renders the network image (or initials fallback) as a 64×64 circle, with
// a small "camera" button at the bottom-right that triggers ImagePicker.
// During upload an orange CircularProgressIndicator overlays the avatar
// so the doctor sees the spinner without losing the existing image.
// ---------------------------------------------------------------------------

class _AvatarUploader extends ConsumerStatefulWidget {
  final DoctorProfile profile;
  const _AvatarUploader({required this.profile});

  @override
  ConsumerState<_AvatarUploader> createState() => _AvatarUploaderState();
}

class _AvatarUploaderState extends ConsumerState<_AvatarUploader> {
  bool _uploading = false;
  final _picker = ImagePicker();

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open photo picker: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
      return;
    }
    if (picked == null) return; // user cancelled

    setState(() => _uploading = true);
    try {
      // Derives the filename and MIME from the bytes. Guessing them from the
      // extension sent an iOS HEIC as `IMG_1.heic` labelled image/jpeg —
      // which the upload filter rejects on the extension, and which used to
      // be stored as an unrenderable avatar.
      final prepared = await prepareImageForUpload(picked);
      await ref.read(doctorProfileProvider.notifier).uploadAvatar(
            bytes: prepared.bytes,
            filename: prepared.filename,
            mimeType: prepared.mimeType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated'),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $msg'),
          backgroundColor: MtColors.rejected,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final cleanName = profile.fullName.replaceFirst('Dr. ', '').trim();
    final initialsName = cleanName.isEmpty ? 'Doctor' : cleanName;
    final hasPhoto = profile.profilePicture.isNotEmpty;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The avatar itself — network image when uploaded, falling
          // back to the existing initials chip otherwise.
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: hasPhoto
                  ? Image.network(
                      profile.profilePicture,
                      fit: BoxFit.cover,
                      // Light skeleton while the image streams in. We
                      // intentionally use a plain shimmer (not the
                      // upload spinner) so the user can tell "loading"
                      // apart from "uploading".
                      loadingBuilder: (_, child, evt) {
                        if (evt == null) return child;
                        return Container(color: MtColors.brandSoft);
                      },
                      errorBuilder: (_, _, _) => InitialsAvatar(
                        name: initialsName,
                        size: 64,
                        backgroundColor: MtColors.brandSoft,
                        textColor: MtColors.brand,
                      ),
                    )
                  : InitialsAvatar(
                      name: initialsName,
                      size: 64,
                      backgroundColor: MtColors.brandSoft,
                      textColor: MtColors.brand,
                    ),
            ),
          ),
          // Upload spinner overlay. Same 64×64 footprint, semi-opaque
          // black wash + brand spinner so the existing image stays
          // visible underneath.
          if (_uploading)
            Positioned.fill(
              left: 0,
              top: 0,
              right: 8,
              bottom: 8,
              child: ClipOval(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          // Camera button — bottom-right, brand orange, ringed in
          // white so it pops against any avatar color.
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploading ? null : _pickAndUpload,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MtColors.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  /// Drives the height of the field. Defaults to single-line; the bio
  /// editor passes `minLines: 3, maxLines: 5` to render a tall area.
  final int? minLines;
  final int? maxLines;

  const _DoctorTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.validator,
    this.minLines,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      minLines: minLines,
      maxLines: maxLines,
      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: MtTextStyles.labelMd.copyWith(color: MtColors.ink3),
        labelStyle: MtTextStyles.labelMd.copyWith(color: MtColors.ink3),
        prefixIcon: Icon(icon, color: MtColors.ink3, size: 18),
        filled: true,
        fillColor: MtColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
        ),
      ),
    );
  }
}
