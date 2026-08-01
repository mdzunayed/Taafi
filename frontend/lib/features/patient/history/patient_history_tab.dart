import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/service_catalog_providers.dart';
import '../../../core/models/appointment.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../appointments/providers/feedback_provider.dart';
import '../../chat/archive/archived_chat_screen.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import 'doctor_portfolio_sheet.dart';
import 'patient_history_provider.dart';

/// History sub-tab inside the Activities screen. Pulls past visits via
/// [patientHistoryProvider] and renders each one through one of two
/// card templates:
///
///   - Scenario A — unrated visit: a full "Care completed" feedback
///     form card (stars + tag chips + Submit feedback button).
///   - Scenario B — already-rated visit: a compact ledger row showing
///     the provider, the timestamp, and the star score they gave.
///
/// Both card variants embed a "View Chat Logs" link that pushes the
/// read-only [ArchivedChatScreen] scoped to that appointment id.
class PatientHistoryTab extends ConsumerWidget {
  const PatientHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientHistoryProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () => ref.read(patientHistoryProvider.notifier).refresh(),
      child: async.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.read(patientHistoryProvider.notifier).refresh(),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyView();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final appt = items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: appt.isReviewed
                    ? _RatedSummaryCard(appointment: appt)
                    : _UnratedFeedbackCard(appointment: appt),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _ViewChatLogsLink extends StatelessWidget {
  final Appointment appointment;
  const _ViewChatLogsLink({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArchivedChatScreen(appointment: appointment),
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: MtColors.brand,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
        label: Text(
          'View Chat Logs',
          style: MtTextStyles.labelMd.copyWith(
            color: MtColors.brand,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Quick Re-Book shortcut. Copies the historic service configuration into the
/// booking prefill rail and jumps straight to the New Request screen, so a
/// repeat booking is a couple of taps instead of refilling the whole form.
class _BookAgainLink extends ConsumerWidget {
  final Appointment appointment;
  const _BookAgainLink({required this.appointment});

  void _bookAgain(WidgetRef ref) {
    HapticFeedback.lightImpact();
    final services = ref.read(activeServicesProvider).valueOrNull ?? const [];
    for (final s in services) {
      if (s.title.trim().toLowerCase() ==
          appointment.careType.trim().toLowerCase()) {
        ref.read(newRequestProvider.notifier).applyServicePrefill(s, fromLink: true);
        break;
      }
    }
    ref.goToNewRequest();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _bookAgain(ref),
        style: TextButton.styleFrom(
          foregroundColor: MtColors.brand,
          backgroundColor: MtColors.brandSofter,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: MtColors.brand),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.replay_rounded, size: 16),
        label: Text(
          'Book Again',
          style: MtTextStyles.labelMd
              .copyWith(color: MtColors.brand, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Tappable doctor metadata row. When the appointment carries a
/// populated `doctor` block (the History endpoint always sends one
/// now), tapping anywhere on the row slides up the doctor portfolio
/// bottom sheet. Falls back to a passive presentation when no doctor
/// block is available so legacy payloads still render cleanly.
class _ProviderRow extends StatelessWidget {
  final Appointment appointment;
  const _ProviderRow({required this.appointment});

  String get _name {
    final populated = appointment.doctor?.fullName.trim();
    if (populated != null && populated.isNotEmpty) return populated;
    final legacy = appointment.assignedDoctorName?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return 'Provider';
  }

  String get _subtitle {
    final specialty = appointment.doctor?.specialty.trim() ?? '';
    if (specialty.isNotEmpty) return specialty;
    return appointment.careType.isEmpty ? 'Care visit' : appointment.careType;
  }

  String? get _photoUrl => appointment.doctor?.profilePicture;

  bool get _hasPortfolio {
    final d = appointment.doctor;
    if (d == null) return false;
    return d.fullName.trim().isNotEmpty || d.id.isNotEmpty;
  }

  void _open(BuildContext context) {
    final doctor = appointment.doctor;
    if (doctor == null) return;
    showDoctorPortfolioSheet(
      context: context,
      doctor: doctor,
      fallbackName: appointment.assignedDoctorName,
      careType: appointment.careType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = _name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '');
    final url = _photoUrl;
    final avatar = (url != null && url.isNotEmpty)
        ? ClipOval(
            child: Image.network(
              url,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => InitialsAvatar(
                name: cleaned,
                size: 40,
                backgroundColor: const Color(0xFFFFF4E5),
                textColor: const Color(0xFF92400E),
              ),
            ),
          )
        : InitialsAvatar(
            name: cleaned,
            size: 40,
            backgroundColor: const Color(0xFFFFF4E5),
            textColor: const Color(0xFF92400E),
          );

    final row = Row(
      children: [
        avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _name,
                      style: MtTextStyles.labelLg.copyWith(
                        color: MtColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (appointment.doctor?.isVerifiedDoctor ?? false) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified,
                        size: 14, color: MtColors.brand),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (_hasPortfolio) ...[
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right,
              color: MtColors.ink3, size: 22),
        ],
      ],
    );

    if (!_hasPortfolio) return row;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: row,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scenario A — unrated card (full feedback form)
// ---------------------------------------------------------------------------

class _UnratedFeedbackCard extends ConsumerWidget {
  final Appointment appointment;
  const _UnratedFeedbackCard({required this.appointment});

  String _completedTimestamp() {
    final fmt = DateFormat('MMM d · h:mm a');
    return fmt.format(appointment.updatedAt.toLocal());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedbackProvider(appointment.id));
    final notifier = ref.read(feedbackProvider(appointment.id).notifier);

    ref.listen<FeedbackState>(feedbackProvider(appointment.id),
        (prev, next) {
      // Surface server errors once via SnackBar; refresh the History
      // list when a submit lands so the same card flips into the
      // Scenario B summary.
      if (next.status.hasError && prev?.status != next.status) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.status.error.toString()),
          ),
        );
      }
      final submitted = next.status.valueOrNull;
      if (submitted != null && prev?.status.valueOrNull == null) {
        ref
            .read(patientHistoryProvider.notifier)
            .replace(submitted);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: MtColors.completed,
            content: Text('Thanks for the feedback!'),
          ),
        );
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Care completed" green banner
          Container(
            color: MtColors.completedBg,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: MtColors.completed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Care completed',
                    style: MtTextStyles.labelMd.copyWith(
                      color: MtColors.completed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _completedTimestamp(),
                  style: MtTextStyles.bodySm
                      .copyWith(color: MtColors.completed),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProviderRow(appointment: appointment),
                const SizedBox(height: 14),
                Text(
                  'How would you rate this visit?',
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (state.selectedRating > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    kRatingLabels[state.selectedRating],
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink2),
                  ),
                ],
                const SizedBox(height: 10),
                _StarRow(
                  rating: state.selectedRating,
                  onTap: notifier.updateRating,
                ),
                const SizedBox(height: 14),
                Text(
                  "What stood out? (optional)",
                  style:
                      MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
                const SizedBox(height: 8),
                _TagWrap(
                  selected: state.selectedTags,
                  onToggle: notifier.toggleTag,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: state.isReady && !state.isLoading
                        ? notifier.submitFeedback
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MtColors.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: MtColors.brandSofter,
                      disabledForegroundColor: MtColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: state.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      state.isLoading
                          ? 'Submitting…'
                          : 'Submit feedback',
                      style: MtTextStyles.labelLg
                          .copyWith(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _BookAgainLink(appointment: appointment),
                    const Spacer(),
                    _ViewChatLogsLink(appointment: appointment),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onTap;
  const _StarRow({required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final v = i + 1;
        final active = v <= rating;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkResponse(
            onTap: () => onTap(v),
            radius: 22,
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              color: active ? const Color(0xFFF59E0B) : MtColors.ink3,
              size: 32,
            ),
          ),
        );
      }),
    );
  }
}

class _TagWrap extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _TagWrap({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in kFeedbackTagOptions)
          _TagChip(
            label: tag,
            active: selected.contains(tag),
            onTap: () => onToggle(tag),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TagChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? MtColors.brand : MtColors.surface2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? MtColors.brand : MtColors.line,
            ),
          ),
          child: Text(
            label,
            style: MtTextStyles.labelMd.copyWith(
              color: active ? Colors.white : MtColors.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scenario B — already-rated summary
// ---------------------------------------------------------------------------

class _RatedSummaryCard extends StatelessWidget {
  final Appointment appointment;
  const _RatedSummaryCard({required this.appointment});

  String _whenLabel() {
    final fmt = DateFormat('MMM d · h:mm a');
    return fmt.format(appointment.updatedAt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final rating = appointment.feedback.rating ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ProviderRow(appointment: appointment),
              ),
              const SizedBox(width: 10),
              _RatedPill(rating: rating.toDouble()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event,
                  size: 14, color: MtColors.ink3),
              const SizedBox(width: 4),
              Text(
                _whenLabel(),
                style:
                    MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
            ],
          ),
          if (appointment.feedback.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in appointment.feedback.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MtColors.brandSofter,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: MtTextStyles.bodySm.copyWith(
                        color: MtColors.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              _BookAgainLink(appointment: appointment),
              const Spacer(),
              _ViewChatLogsLink(appointment: appointment),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatedPill extends StatelessWidget {
  final double rating;
  const _RatedPill({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded,
              size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 4),
          Text(
            '${rating.toStringAsFixed(1)} Rated',
            style: MtTextStyles.labelSm.copyWith(
              color: const Color(0xFF92400E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error / loading
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
              Icons.assignment_outlined,
              color: MtColors.brand,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'No past visits yet',
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Your completed and cancelled appointments will show up here so you can rate them and pull up the conversation later.',
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
          "Couldn't load history",
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
