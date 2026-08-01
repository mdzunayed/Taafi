import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/appointment.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../appointments/providers/feedback_provider.dart';

/// Patient-facing "Care Completed" + Rating screen. The whole screen
/// is data-driven now:
///   • Hero card + vitals + payment come from the live [Appointment]
///     fetched by [latestCompletedAppointmentProvider].
///   • Stars and tag chips are owned by [FeedbackNotifier] keyed on
///     the appointment id, so the in-progress draft is preserved if
///     the user navigates away and back.
///   • Submit fires a real POST and surfaces success / error states.
///
/// Pre-tap state shows a 0-star rating (no caption) so the user is
/// nudged to pick — not given a misleading 5-star default.
class RatingTab extends ConsumerWidget {
  const RatingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(latestCompletedAppointmentProvider);
    return async.when(
      loading: () => const _RatingTabLoading(),
      error: (e, _) => MtErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(latestCompletedAppointmentProvider),
      ),
      data: (appt) => appt == null
          ? const _EmptyState()
          : _RatingBody(appointment: appt),
    );
  }
}

class _RatingBody extends ConsumerWidget {
  final Appointment appointment;
  const _RatingBody({required this.appointment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedbackProvider(appointment.id));
    final notifier = ref.read(feedbackProvider(appointment.id).notifier);

    // React to async status changes — show a green snackbar on success
    // and an orange-red snackbar on failure. The notifier handles the
    // state mutation; the screen just observes.
    ref.listen<FeedbackState>(feedbackProvider(appointment.id), (prev, next) {
      if (prev?.status == next.status) return;
      next.status.whenOrNull(
        data: (appt) {
          if (appt != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Thanks! ${next.selectedRating}★'
                  '${next.selectedTags.isEmpty ? '' : ' · ${next.selectedTags.join(", ")}'}',
                ),
                backgroundColor: MtColors.completed,
              ),
            );
            // Refresh the latest-appointment provider so the screen
            // flips to the "already reviewed" empty state on next render.
            // ignore: unused_result
            ref.refresh(latestCompletedAppointmentProvider);
          }
        },
        error: (e, _) {
          final msg = e.toString().startsWith('Exception: ')
              ? e.toString().substring(11)
              : e.toString();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: MtColors.rejected),
          );
        },
      );
    });

    final alreadyReviewed = appointment.isReviewed;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _CompletedCard(appointment: appointment),
              if (appointment.vitals != null &&
                  !appointment.vitals!.isEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  _vitalsHeaderFor(appointment),
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                _VitalsGrid(vitals: appointment.vitals!),
              ],
              if (appointment.procedures.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'PROCEDURES COMPLETED',
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                _ProceduresWrap(procedures: appointment.procedures),
              ],
              if (appointment.completionSummary.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  appointment.isNurseRecorded
                      ? 'NURSE REMARKS'
                      : 'CLINICAL REMARKS',
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                _RemarksCard(text: appointment.completionSummary.trim()),
              ],
              const SizedBox(height: 18),
              _RatingCard(
                rating: state.selectedRating,
                ratingLabel: kRatingLabels[state.selectedRating],
                selectedTags: state.selectedTags,
                onRatingChanged:
                    alreadyReviewed ? null : notifier.updateRating,
                onTagToggled:
                    alreadyReviewed ? null : notifier.toggleTag,
              ),
              if (appointment.payment != null &&
                  !appointment.payment!.isEmpty) ...[
                const SizedBox(height: 18),
                _PaymentCard(payment: appointment.payment!),
              ],
            ],
          ),
        ),
        _SubmitBar(
          isLoading: state.isLoading,
          isEnabled: !alreadyReviewed && state.isReady && !state.isLoading,
          label: alreadyReviewed ? 'Feedback submitted' : 'Submit feedback',
          onSubmit: () => notifier.submitFeedback(),
        ),
      ],
    );
  }

  String _vitalsHeaderFor(Appointment a) {
    // Home visits are nurse-led — attribute the readings to the nurse who
    // recorded them on-site, falling back to the doctor otherwise.
    if (a.isNurseRecorded) {
      final n = (a.nurse?.fullName ?? '')
          .replaceFirst(RegExp(r'^(Nurse|Sister)\s+'), '')
          .trim();
      if (n.isEmpty) return 'VITALS RECORDED BY YOUR NURSE';
      return 'VITALS RECORDED BY NURSE ${n.toUpperCase()}';
    }
    final name = (a.assignedDoctorName ?? '').replaceFirst('Dr. ', '').trim();
    if (name.isEmpty) return 'VITALS RECORDED';
    return 'VITALS RECORDED BY DR. ${name.toUpperCase()}';
  }
}

// ---------------------------------------------------------------------------
// Loading + empty states
// ---------------------------------------------------------------------------

class _RatingTabLoading extends StatelessWidget {
  const _RatingTabLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: MtColors.brand),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.reviews_outlined,
                size: 48, color: MtColors.ink3),
            const SizedBox(height: 12),
            Text('No completed visits yet',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(
              'When a doctor finishes a visit you booked, you’ll be able to rate it here.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Completed hero card
// ---------------------------------------------------------------------------

class _CompletedCard extends StatelessWidget {
  final Appointment appointment;
  const _CompletedCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.completed, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: MtColors.completedBg,
              shape: BoxShape.circle,
              border: Border.all(color: MtColors.completed, width: 1.5),
            ),
            child: const Icon(Icons.check, color: MtColors.completed, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            'Care completed',
            style: MtTextStyles.h2.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            appointment.sessionCaption,
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
          ),
          if (appointment.careType.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              appointment.careType,
              style: MtTextStyles.labelMd.copyWith(color: MtColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Procedures + remarks (nursing report)
// ---------------------------------------------------------------------------

/// Read-only chips listing the procedures the nurse performed on-site.
class _ProceduresWrap extends StatelessWidget {
  final List<String> procedures;
  const _ProceduresWrap({required this.procedures});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in procedures)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MtColors.completedBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: MtColors.completed.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 15, color: MtColors.completed),
                const SizedBox(width: 6),
                Text(p,
                    style: MtTextStyles.labelMd.copyWith(
                        color: MtColors.ink, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Read-only clinical wrap-up note the nurse (or doctor) left at completion.
class _RemarksCard extends StatelessWidget {
  final String text;
  const _RemarksCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sticky_note_2_outlined,
              size: 18, color: MtColors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: MtTextStyles.bodyMd
                    .copyWith(color: MtColors.ink2, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vitals — dynamic
// ---------------------------------------------------------------------------

class _Vital {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _Vital(this.label, this.value, this.unit, this.color);
}

class _VitalsGrid extends StatelessWidget {
  final AppointmentVitals vitals;
  const _VitalsGrid({required this.vitals});

  /// Builds the list of tiles to render, skipping any metric the
  /// doctor didn't capture. This avoids forcing six tiles when the
  /// visit only has BP and pulse.
  List<_Vital> _tiles() {
    final out = <_Vital>[];
    if (vitals.bloodPressure != null) {
      out.add(_Vital('BP', vitals.bloodPressure!, vitals.bloodPressureUnit,
          MtColors.completed));
    }
    if (vitals.temperature != null) {
      out.add(_Vital(
          'TEMP', vitals.temperature!, vitals.temperatureUnit, MtColors.brand));
    }
    if (vitals.spo2 != null) {
      out.add(_Vital('SPO₂', vitals.spo2!, vitals.spo2Unit, MtColors.completed));
    }
    if (vitals.pulse != null) {
      out.add(_Vital(
          'PULSE', vitals.pulse!, vitals.pulseUnit, MtColors.completed));
    }
    if (vitals.bloodSugar != null) {
      out.add(_Vital(
          'RBS', vitals.bloodSugar!, vitals.bloodSugarUnit, MtColors.brand));
    }
    if (vitals.painScore != null) {
      out.add(_Vital('PAIN', vitals.painScore!, 'scale', MtColors.brand));
    }
    if (vitals.woundStatus != null) {
      out.add(_Vital(
          'WOUND', vitals.woundStatus!, 'healing', MtColors.completed));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (_, i) => _VitalTile(vital: tiles[i]),
    );
  }
}

class _VitalTile extends StatelessWidget {
  final _Vital vital;
  const _VitalTile({required this.vital});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            vital.label,
            style: MtTextStyles.sectionLabel.copyWith(
              color: MtColors.ink3,
              letterSpacing: 1.0,
            ),
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: vital.value,
                  style: MtTextStyles.h2.copyWith(
                    color: vital.color,
                    fontSize: 22,
                  ),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: vital.unit,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rating card — interactive stars + toggleable chips
// ---------------------------------------------------------------------------

class _RatingCard extends StatelessWidget {
  final int rating;
  final String ratingLabel;
  final Set<String> selectedTags;
  // Null → already-reviewed read-only mode. Disables tap handlers but
  // keeps the visual state so the user can see what they submitted.
  final ValueChanged<int>? onRatingChanged;
  final ValueChanged<String>? onTagToggled;

  const _RatingCard({
    required this.rating,
    required this.ratingLabel,
    required this.selectedTags,
    required this.onRatingChanged,
    required this.onTagToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How was the care?',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'সেবা কেমন ছিল?',
            style: MtTextStyles.bodySm.copyWith(
              color: MtColors.ink3,
              fontFamily: 'Kalpurush',
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= 5; i++) ...[
                  GestureDetector(
                    onTap: onRatingChanged == null
                        ? null
                        : () => onRatingChanged!(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        i <= rating ? Icons.star : Icons.star_outline,
                        color: MtColors.brand,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (ratingLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                ratingLabel,
                style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final t in kFeedbackTagOptions)
                _TagChip(
                  label: t,
                  selected: selectedTags.contains(t),
                  onTap: onTagToggled == null ? null : () => onTagToggled!(t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MtColors.brand : MtColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? MtColors.brand : MtColors.line,
          ),
        ),
        child: Text(
          label,
          style: MtTextStyles.labelMd.copyWith(
            color: selected ? Colors.white : MtColors.ink2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment card — dynamic
// ---------------------------------------------------------------------------

final _paymentMoney = NumberFormat('#,###', 'en_US');
String _money(num n, {String currency = 'BDT'}) {
  final symbol = currency == 'BDT' ? '৳' : '$currency ';
  return '$symbol${_paymentMoney.format(n.round())}';
}

class _PaymentCard extends StatelessWidget {
  final AppointmentPayment payment;
  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    // Build the line item list, only rendering rows the backend
    // actually populated. Total is always rendered last + bold.
    final rows = <(String, num, bool)>[];
    if (payment.doctorFee > 0) {
      rows.add(('Doctor fee', payment.doctorFee, false));
    }
    if (payment.helperFee > 0) {
      rows.add(('Helper fee', payment.helperFee, false));
    }
    if (payment.platformFee > 0) {
      rows.add(('Platform', payment.platformFee, false));
    }
    rows.add(('Total charged', payment.total, true));

    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  payment.isReleased ? 'Payment released' : 'Payment pending',
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: MtColors.bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: payment.isReleased
                              ? MtColors.completed
                              : MtColors.ink2,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        payment.isReleased ? 'COMPLETED' : 'PENDING',
                        style: MtTextStyles.labelSm.copyWith(
                          color: payment.isReleased
                              ? MtColors.completed
                              : MtColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: rows[i].$3
                          ? MtTextStyles.labelLg.copyWith(color: MtColors.ink)
                          : MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                  ),
                  Text(
                    _money(rows[i].$2, currency: payment.currency),
                    style: rows[i].$3
                        ? MtTextStyles.labelLg.copyWith(color: MtColors.ink)
                        : MtTextStyles.labelMd.copyWith(color: MtColors.ink),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1)
              const Divider(
                height: 1,
                color: MtColors.line,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Submit bar — loading + disabled states
// ---------------------------------------------------------------------------

class _SubmitBar extends StatelessWidget {
  final bool isLoading;
  final bool isEnabled;
  final String label;
  final VoidCallback onSubmit;

  const _SubmitBar({
    required this.isLoading,
    required this.isEnabled,
    required this.label,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isEnabled ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: MtColors.brand.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style:
                            MtTextStyles.labelLg.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
