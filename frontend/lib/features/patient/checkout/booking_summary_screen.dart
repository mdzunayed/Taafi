import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../new_request/new_request_notifier.dart';
import '../new_request/new_request_state.dart';
import '../screens/booking_flow_pages.dart' show money;
import 'booking_checkout_screen.dart';
import 'booking_pricing.dart';
import 'widgets/booking_stepper.dart';
import 'widgets/checkout_primitives.dart';

/// Step 2 of the care checkout — the care summary.
///
/// Under zero-upfront booking there is no cart to total up: the patient is
/// confirming *what care they asked for*, not assembling a bill. There is no
/// money on this screen at all. Both the service fee and the advance deposit
/// are set later by Care Management after they review the case and call, so
/// both are shown as explicitly pending rather than guessed at, and the total
/// due now is ৳0.
class BookingSummaryScreen extends ConsumerWidget {
  const BookingSummaryScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
        builder: (_) => const BookingSummaryScreen(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final state = ref.watch(newRequestProvider);
    final service = state.selectedService;

    // Defensive: the service step is the only way in, but an auto-dispose of
    // the form (app resumed onto a cold provider) would strand this screen
    // with nothing to summarise.
    if (service == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: Column(
          children: [
            BookingFlowHeader(
              title: 'Care Summary',
              step: BookingStep.summary,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Your booking session expired. Please choose a service '
                    'again.',
                    textAlign: TextAlign.center,
                    style: MtTextStyles.bodyMd.copyWith(color: c.body),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        children: [
          BookingFlowHeader(
            title: 'Care Summary',
            subtitle: service.title,
            step: BookingStep.summary,
            onBack: () => Navigator.of(context).maybePop(),
            onStepTapped: (_) => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const CheckoutSectionLabel('Your care session'),
                const SizedBox(height: 8),
                _SelectedServiceCard(state: state),
                const SizedBox(height: 20),
                const CheckoutSectionLabel('Bill details'),
                const SizedBox(height: 8),
                const _ZeroCostBillCard(),
                const SizedBox(height: 12),
                const FreeSubmissionNotice(),
              ],
            ),
          ),
          CheckoutActionBar(
            totalLabel: 'Total due now',
            total: BookingPriceBreakdown.dueNow,
            totalNote: 'Nothing to pay today · fee & deposit set after review',
            ctaLabel: 'Review payment and address',
            ctaIcon: Icons.arrow_forward_rounded,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(BookingCheckoutScreen.route());
            },
          ),
        ],
      ),
    );
  }
}

// ─── Selected service ───────────────────────────────────────────────────────

class _SelectedServiceCard extends StatelessWidget {
  final NewRequestState state;
  const _SelectedServiceCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final service = state.selectedService!;
    final recipient = state.careRecipient;

    return CheckoutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.medical_services_outlined,
                    color: c.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: MtTextStyles.labelLg.copyWith(
                        color: c.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // No catalog price is shown. Prices here would be a
                    // quote, and Taafi does not quote before the review call.
                    Text(
                      'Price: To be finalized by Admin',
                      style: MtTextStyles.bodySm.copyWith(color: c.body),
                    ),
                    if (service.duration?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 13, color: c.muted),
                          const SizedBox(width: 4),
                          Text(
                            service.duration!.trim(),
                            style:
                                MtTextStyles.bodySm.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (recipient != null || state.documents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.cardBorder),
            const SizedBox(height: 12),
          ],
          if (recipient != null)
            _MetaRow(
              icon: Icons.person_outline,
              label: 'For',
              value: recipient.relationship.trim().isEmpty
                  ? recipient.name
                  : '${recipient.name} · ${recipient.relationship}',
            ),
          if (state.documents.isNotEmpty) ...[
            if (recipient != null) const SizedBox(height: 8),
            _MetaRow(
              icon: Icons.attach_file,
              label: 'Documents',
              value: state.documents.length == 1
                  ? state.documents.single.name
                  : '${state.documents.length} files attached',
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Icon(icon, size: 16, color: c.muted),
        const SizedBox(width: 8),
        Text('$label: ', style: MtTextStyles.bodySm.copyWith(color: c.muted)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.bodySm.copyWith(color: c.title),
          ),
        ),
      ],
    );
  }
}

// ─── Bill ───────────────────────────────────────────────────────────────────

/// The whole bill under zero-upfront booking: two explicitly pending lines
/// (the service fee and the advance deposit), and a total due now of ৳0.
///
/// Neither pending line shows a number, and that is the point. Both are
/// per-case decisions the care team makes on the review call, so any figure
/// rendered here would be a quote the platform has not made.
class _ZeroCostBillCard extends StatelessWidget {
  const _ZeroCostBillCard();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return CheckoutCard(
      child: Column(
        children: [
          PriceRow(
            label: 'Service Fee',
            note: 'Set by our care team after reviewing your case',
            value: BookingPriceBreakdown.pendingFeeLabel,
            valueColor: c.warning,
          ),
          const SizedBox(height: 12),
          PriceRow(
            label: 'Required Advance Deposit',
            note: 'Confirms your visit once the care team calls you',
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

/// The zero-cost booking policy, stated in the patient's own terms on both
/// screens where they meet it.
///
/// Deliberately prominent and deliberately shared: "you pay nothing today, and
/// here is what happens instead" is the single fact that makes the rest of the
/// flow legible, and the summary and checkout screens must not word it
/// differently.
class FreeSubmissionNotice extends StatelessWidget {
  const FreeSubmissionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.infoBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: c.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Free Request Submission',
                  style: MtTextStyles.labelLg.copyWith(color: c.title),
                ),
                const SizedBox(height: 4),
                Text(
                  'Place your request without paying anything today. Our care '
                  'team will call you to discuss your medical needs and set '
                  'the required advance deposit to confirm your visit.',
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
