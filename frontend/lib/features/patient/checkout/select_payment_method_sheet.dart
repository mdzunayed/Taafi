import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import 'booking_payment_method.dart';

/// Opens the payment-rail picker. Returns the confirmed
/// [BookingPaymentMethod], or `null` when the patient backs out — callers
/// must treat `null` as "leave the current selection alone" rather than as a
/// clear, so dismissing the sheet never wipes a rail they already chose.
Future<BookingPaymentMethod?> showSelectPaymentMethodSheet(
  BuildContext context, {
  BookingPaymentMethod? selected,
}) {
  return showModalBottomSheet<BookingPaymentMethod>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SelectPaymentMethodSheet(initial: selected),
  );
}

/// Single-select list of the local rails (bKash, Nagad, Rocket, upay), cards
/// and cash-on-service, with a sticky Confirm that returns the choice to the
/// Checkout screen.
///
/// Selection is local to the sheet until Confirm is pressed — tapping around
/// to compare options must not mutate the booking behind the sheet.
class SelectPaymentMethodSheet extends StatefulWidget {
  final BookingPaymentMethod? initial;

  const SelectPaymentMethodSheet({super.key, this.initial});

  @override
  State<SelectPaymentMethodSheet> createState() =>
      _SelectPaymentMethodSheetState();
}

class _SelectPaymentMethodSheetState extends State<SelectPaymentMethodSheet> {
  late BookingPaymentMethod? _selected = widget.initial;

  static const _mfs = [
    BookingPaymentMethod.bkash,
    BookingPaymentMethod.nagad,
    BookingPaymentMethod.rocket,
    BookingPaymentMethod.upay,
  ];

  // Cards only. Cash is deliberately absent: this sheet pays the
  // booking deposit, and the deposit is what unlocks Care Management's
  // review, so it has to clear online before anyone is dispatched. The cash
  // option belongs to the REMAINING balance and is offered later, on the
  // invoice, once the fee is known.
  static const _other = [BookingPaymentMethod.card];

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select payment method',
                          style: MtTextStyles.h3.copyWith(color: c.title)),
                      const SizedBox(height: 2),
                      Text(
                        'Deposit must be paid online to confirm request '
                        'submission.',
                        style: MtTextStyles.bodySm.copyWith(color: c.body),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: c.muted),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                _GroupLabel('Mobile financial services'),
                const SizedBox(height: 8),
                for (final m in _mfs) ...[
                  _PaymentTile(
                    method: m,
                    selected: _selected == m,
                    onTap: () => _select(m),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                _GroupLabel('Cards'),
                const SizedBox(height: 8),
                for (final m in _other) ...[
                  _PaymentTile(
                    method: m,
                    selected: _selected == m,
                    onTap: () => _select(m),
                  ),
                  const SizedBox(height: 10),
                ],
                const Padding(
                  padding: EdgeInsets.only(top: 2, bottom: 6),
                  child: _CashLaterNotice(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.cardBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(_selected);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    disabledBackgroundColor: c.surfaceHi,
                    disabledForegroundColor: c.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _selected == null
                        ? 'Choose a method'
                        : 'Confirm ${_selected!.label}',
                    style: MtTextStyles.labelLg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _select(BookingPaymentMethod m) {
    HapticFeedback.selectionClick();
    setState(() => _selected = m);
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: MtTextStyles.sectionLabel.copyWith(color: context.appColors.muted),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final BookingPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentTile({
    required this.method,
    required this.selected,
    required this.onTap,
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
          padding: const EdgeInsets.all(12),
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
              _RailBadge(method: method),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(method.label,
                        style: MtTextStyles.labelLg.copyWith(color: c.title)),
                    const SizedBox(height: 2),
                    Text(method.subtitle,
                        style: MtTextStyles.bodySm.copyWith(color: c.muted)),
                  ],
                ),
              ),
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

/// Tinted monogram tile standing in for the rail's logo (no gateway
/// trademarks ship in `assets/`).
class _RailBadge extends StatelessWidget {
  final BookingPaymentMethod method;
  const _RailBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final tint = method.tint;
    final icon = method.icon;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: icon != null
          ? Icon(icon, color: tint, size: 22)
          : Text(
              method.glyph,
              style: MtTextStyles.labelLg.copyWith(
                color: tint,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
    );
  }
}

/// Explains where cash *did* go, so its absence reads as a policy rather
/// than a missing feature.
///
/// Names no amount on purpose: at this point in the flow no deposit exists yet
/// (the care team sets it after the review call), and quoting a figure here
/// would contradict the ৳0 the patient is looking at on the same screen.
class _CashLaterNotice extends StatelessWidget {
  const _CashLaterNotice();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceHi,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.payments_outlined, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prefer cash? Placing this request is free. If our care team '
              'sets an advance deposit after their call, it must be paid '
              'online to confirm your visit — but you can then choose to pay '
              'the remaining balance in cash to your clinician.',
              style: MtTextStyles.bodySm.copyWith(color: c.body),
            ),
          ),
        ],
      ),
    );
  }
}
