import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/saved_address.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import '../new_request/new_request_state.dart';
import '../screens/booking_flow_pages.dart' show money;
import '../screens/select_address_sheet.dart';
import '../screens/widgets/active_booking_banner.dart';
import 'booking_payment_method.dart';
import 'booking_pricing.dart';
import 'booking_summary_screen.dart' show FreeSubmissionNotice;
import 'select_payment_method_sheet.dart';
import 'widgets/booking_stepper.dart';
import 'widgets/checkout_primitives.dart';

/// Step 3 of the care checkout — where the visit is placed.
///
/// Collects the care location (+ clinician instructions), the dispatch window
/// and the payment rail, then commits the booking through the shared
/// [NewRequestNotifier.submit] pipeline. Nothing is charged: the request is
/// placed free and the patient is prompted for a deposit only after the care
/// team's review call sets one.
///
/// The payment rail is still collected here — it is saved, not charged, so the
/// Phase-3 deposit sheet can preselect the method the patient already chose.
class BookingCheckoutScreen extends ConsumerStatefulWidget {
  const BookingCheckoutScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
        builder: (_) => const BookingCheckoutScreen(),
      );

  @override
  ConsumerState<BookingCheckoutScreen> createState() =>
      _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen> {
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    // Seeded from the address's landmark line, which is exactly this field:
    // floor / flat / entrance detail for the visiting clinician.
    _instructionsController = TextEditingController(
      text: ref.read(newRequestProvider).address.landmark ?? '',
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final state = ref.watch(newRequestProvider);
    // One booking at a time — the backend answers 409 while a non-terminal
    // request is open, so seal Confirm here too and let the banner explain.
    final hasActiveBooking = ref.watch(patientActiveRequestProvider) != null;

    final ready = state.selectedService != null &&
        !state.address.isEmpty &&
        state.paymentMethod != null &&
        (state.timing == RequestTiming.asSoonAsPossible ||
            state.scheduledAt != null) &&
        !state.isSubmitting &&
        !hasActiveBooking;

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        children: [
          BookingFlowHeader(
            title: 'Checkout',
            subtitle: state.selectedService?.title,
            step: BookingStep.checkout,
            onBack: () => Navigator.of(context).maybePop(),
            onStepTapped: (step) {
              // Only completed steps are tappable. Summary is one pop back;
              // Service is the shell route this whole flow was pushed from.
              final nav = Navigator.of(context);
              if (step == BookingStep.service) {
                nav.popUntil((r) => r.isFirst);
              } else {
                nav.maybePop();
              }
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const CheckoutSectionLabel('Care location'),
                const SizedBox(height: 8),
                _AddressCard(
                  address: state.address,
                  onChange: _pickAddress,
                ),
                const SizedBox(height: 10),
                _InstructionsField(controller: _instructionsController),
                const SizedBox(height: 20),
                const CheckoutSectionLabel('Service timing'),
                const SizedBox(height: 8),
                _TimingOptions(
                  timing: state.timing,
                  scheduledAt: state.scheduledAt,
                  onAsap: () => ref
                      .read(newRequestProvider.notifier)
                      .setTiming(RequestTiming.asSoonAsPossible),
                  onSchedule: _pickSchedule,
                ),
                const SizedBox(height: 20),
                const CheckoutSectionLabel('Payment method'),
                const SizedBox(height: 8),
                _PaymentTile(
                  method: state.paymentMethod,
                  onTap: _pickPaymentMethod,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: c.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Nothing is charged now. We save this method for the '
                        'advance deposit your care team sets after their call.',
                        style: MtTextStyles.bodySm.copyWith(color: c.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const CheckoutSectionLabel('Order summary'),
                const SizedBox(height: 8),
                const _OrderSummaryCard(),
                const SizedBox(height: 12),
                const FreeSubmissionNotice(),
              ],
            ),
          ),
          CheckoutActionBar(
            totalLabel: 'Total Due Now',
            total: BookingPriceBreakdown.dueNow,
            totalNote: 'Fee & deposit finalized after your care team calls you',
            // Says both things that matter before the tap: this places the
            // request, and it costs nothing.
            ctaLabel: BookingPriceBreakdown.ctaLabel,
            ctaIcon: Icons.check_circle_outline_rounded,
            isLoading: state.isSubmitting,
            loadingLabel: 'Placing request…',
            onPressed: ready ? _confirm : null,
            banner: hasActiveBooking
                ? const ActiveBookingBanner()
                : (state.validationError != null
                    ? _InlineError(message: state.validationError!)
                    : null),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pickers

  Future<void> _pickAddress() async {
    final picked = await showSelectAddressSheet(context);
    if (picked == null || !mounted) return;
    ref.read(newRequestProvider.notifier).applyAddress(_toRequestAddress(picked));
    // The saved address carries its own landmark line; mirror it into the
    // instructions field so the visible text and the stored value agree.
    final landmark = picked.landmarkInstructions.trim();
    _instructionsController.text = landmark;
    _instructionsController.selection =
        TextSelection.collapsed(offset: landmark.length);
  }

  /// Same mapping the New Request form uses, so a booking assembled here is
  /// indistinguishable from one assembled there.
  static RequestAddress _toRequestAddress(SavedAddress a) => RequestAddress(
        line1: a.flatFloorHolding,
        areaCityZip: a.fullAddressText,
        label: a.label,
        landmark: a.landmarkInstructions.trim().isEmpty
            ? null
            : a.landmarkInstructions.trim(),
        latitude: a.latitude,
        longitude: a.longitude,
      );

  Future<void> _pickSchedule() async {
    final state = ref.read(newRequestProvider);
    final now = DateTime.now();
    final initial = state.scheduledAt ?? now.add(const Duration(hours: 4));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    ref.read(newRequestProvider.notifier).setScheduledAt(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
  }

  Future<void> _pickPaymentMethod() async {
    final current = ref.read(newRequestProvider).paymentMethod;
    final picked =
        await showSelectPaymentMethodSheet(context, selected: current);
    // `null` = dismissed. Keep whatever was already chosen.
    if (picked == null || !mounted) return;
    ref.read(newRequestProvider.notifier).setPaymentMethod(picked);
  }

  // --------------------------------------------------------------- submission

  Future<void> _confirm() async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.appColors.danger;

    // Flush the instructions field before submitting — a patient who types
    // and taps Confirm without unfocusing must not lose the entrance detail.
    final typed = _instructionsController.text.trim();
    ref
        .read(newRequestProvider.notifier)
        .setLandmark(typed.isEmpty ? null : typed);

    final id = await ref.read(newRequestProvider.notifier).submit();
    if (!mounted) return;

    if (id == null) {
      final postState = ref.read(newRequestProvider);
      final err = postState.validationError;
      if (err != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  postState.cachedLocally ? Icons.cloud_off : Icons.error_outline,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(err)),
              ],
            ),
            backgroundColor: dangerColor,
            duration: Duration(seconds: postState.cachedLocally ? 5 : 4),
          ),
        );
      }
      return;
    }

    ref.read(newRequestProvider.notifier).clearSubmissionStatus();

    // PHASE 1 ends here. The request is placed, free, and already in the
    // admin's review queue — there is no payment sheet to open, because there
    // is nothing to pay. The deposit does not exist until the care team calls
    // and sets it; the patient is prompted for it from Activities at that
    // point (Phase 3).
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.appColors.positive,
        content: const Text(
          'Request placed — no payment needed. Our care team will call you '
          'shortly.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    // Unwind the checkout stack back to the shell, then land the patient on
    // Activities → Active Care where the new booking is waiting.
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.goToActivities(sub: PatientActivitiesTab.activeCare);
  }
}

// ─── Address ────────────────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final RequestAddress address;
  final VoidCallback onChange;

  const _AddressCard({required this.address, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    if (address.isEmpty) {
      return InkWell(
        onTap: onChange,
        borderRadius: BorderRadius.circular(16),
        child: CheckoutCard(
          borderColor: c.brand,
          child: Row(
            children: [
              _Glyph(icon: Icons.add_location_alt_outlined, tint: c.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add your care address',
                        style: MtTextStyles.labelLg.copyWith(color: c.title)),
                    const SizedBox(height: 2),
                    Text('Where should the clinician visit?',
                        style: MtTextStyles.bodySm.copyWith(color: c.body)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      );
    }

    final detail = [
      if (address.line1.trim().isNotEmpty) address.line1.trim(),
      if (address.areaCityZip.trim().isNotEmpty) address.areaCityZip.trim(),
    ].join(', ');

    return CheckoutCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(icon: Icons.location_on, tint: c.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (address.label.trim().isEmpty ? 'Home' : address.label)
                        .toUpperCase(),
                    style: MtTextStyles.labelSm.copyWith(color: c.brand),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: MtTextStyles.bodyMd.copyWith(color: c.title),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: c.brand,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: Text('Change', style: MtTextStyles.labelLg),
          ),
        ],
      ),
    );
  }
}

class _InstructionsField extends ConsumerWidget {
  final TextEditingController controller;
  const _InstructionsField({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return CheckoutCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.notes_rounded, size: 20, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: MtTextStyles.bodyMd.copyWith(color: c.title),
              onChanged: (v) {
                final trimmed = v.trim();
                ref
                    .read(newRequestProvider.notifier)
                    .setLandmark(trimmed.isEmpty ? null : trimmed);
              },
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: 'Instructions for clinician (Optional: Floor, '
                    'Flat No, or entrance details)',
                hintStyle: MtTextStyles.bodyMd.copyWith(color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Timing ─────────────────────────────────────────────────────────────────

class _TimingOptions extends StatelessWidget {
  final RequestTiming timing;
  final DateTime? scheduledAt;
  final VoidCallback onAsap;
  final VoidCallback onSchedule;

  const _TimingOptions({
    required this.timing,
    required this.scheduledAt,
    required this.onAsap,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final asap = timing == RequestTiming.asSoonAsPossible;
    final scheduledLabel = scheduledAt == null
        ? 'Select a time slot'
        : DateFormat('EEE d MMM · h:mm a').format(scheduledAt!);
    return Column(
      children: [
        _RadioRow(
          leading: '⚡',
          title: 'Urgent / ASAP Visit',
          subtitle: 'Dispatched as soon as a provider is assigned',
          selected: asap,
          onTap: onAsap,
        ),
        const SizedBox(height: 10),
        _RadioRow(
          leading: '🕒',
          title: 'Scheduled Visit',
          subtitle: scheduledLabel,
          selected: !asap,
          onTap: onSchedule,
          // Once scheduled, tapping the row again re-opens the picker.
          trailing: !asap
              ? Text(
                  'Change',
                  style: MtTextStyles.labelMd
                      .copyWith(color: context.appColors.brand),
                )
              : null,
        ),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _RadioRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? c.brand.withValues(alpha: 0.07) : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? c.brand : c.cardBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(leading, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: MtTextStyles.labelLg.copyWith(color: c.title)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.bodySm.copyWith(color: c.muted)),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? c.brand : c.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Payment ────────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final BookingPaymentMethod? method;
  final VoidCallback onTap;

  const _PaymentTile({required this.method, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    if (method == null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DottedPlaceholder(
          child: Row(
            children: [
              _Glyph(icon: Icons.add_card_rounded, tint: c.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add a payment method',
                  style: MtTextStyles.labelLg.copyWith(color: c.brand),
                ),
              ),
              Icon(Icons.chevron_right, color: c.brand),
            ],
          ),
        ),
      );
    }

    final m = method!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: CheckoutCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: m.tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: m.tint.withValues(alpha: 0.35)),
              ),
              child: m.icon != null
                  ? Icon(m.icon, color: m.tint, size: 22)
                  : Text(
                      m.glyph,
                      style: MtTextStyles.labelLg.copyWith(
                        color: m.tint,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.label,
                      style: MtTextStyles.labelLg.copyWith(color: c.title)),
                  const SizedBox(height: 2),
                  Text(m.subtitle,
                      style: MtTextStyles.bodySm.copyWith(color: c.muted)),
                ],
              ),
            ),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: c.brand,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
              ),
              child: Text('Change', style: MtTextStyles.labelLg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed-outline slot for the "nothing chosen yet" states.
class DottedPlaceholder extends StatelessWidget {
  final Widget child;
  const DottedPlaceholder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.brand.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.brand.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

// ─── Summary + misc ─────────────────────────────────────────────────────────

/// Zero-upfront order summary: an explicit "pending" for everything that is
/// not priced yet, and ৳0 to pay. No VAT or service-fee arithmetic — there is
/// no service price to apply it to until Care Management sets the fee.
class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return CheckoutCard(
      child: Column(
        children: [
          PriceRow(
            label: 'Service Fee',
            value: BookingPriceBreakdown.pendingFeeLabel,
            valueColor: c.warning,
          ),
          const SizedBox(height: 12),
          PriceRow(
            label: 'Required Advance Deposit',
            value: BookingPriceBreakdown.pendingDepositLabel,
            valueColor: c.warning,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: c.cardBorder),
          const SizedBox(height: 12),
          PriceRow(
            label: 'Total Due Now',
            value: money(BookingPriceBreakdown.dueNow),
            emphasize: true,
            valueColor: c.positive,
          ),
        ],
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _Glyph({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: tint, size: 20),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.dangerBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: MtTextStyles.bodySm.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}
