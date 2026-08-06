import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_skeleton.dart';
import '../../../auth/auth_provider.dart';
import '../../admin_providers.dart';

/// Neutral indigo accent for the booking-review surface — deliberately NOT
/// the orange brand, per the two-phase-invoice design language.
const Color _kAccent = Color(0xFF4F46E5);

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

/// PHASE 2 QUEUE — freshly placed requests awaiting the admin's review call.
///
/// These patients paid nothing to book and are waiting on a phone call that
/// produces two numbers: the total service fee and the advance deposit. This
/// is the queue the whole zero-upfront flow depends on being worked promptly —
/// nothing moves until an admin calls.
///
/// `pending` is the frontend-normalized form of the backend's `submitted`
/// (see `normalizeAdminStatus`).
final bookingReviewQueueProvider = Provider<List<AdminCareRequest>>((ref) {
  final async = ref.watch(adminRequestsProvider);
  return async.maybeWhen(
    data: (list) =>
        list.where((r) => r.status == 'pending').toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
});

/// Badge count for the sidebar.
final bookingReviewCountProvider = Provider<int>(
  (ref) => ref.watch(bookingReviewQueueProvider).length,
);

/// PHASE 2, QUOTED — bookings where the admin already set the fee + deposit
/// and the ball is now in the PATIENT's court. Surfaced separately so the
/// primary queue stays a to-do list rather than a mixed bag: nothing here
/// needs an admin action, but the amounts remain editable (a second call, a
/// revised quote) until the money lands.
final awaitingDepositQueueProvider = Provider<List<AdminCareRequest>>((ref) {
  final async = ref.watch(adminRequestsProvider);
  return async.maybeWhen(
    data: (list) => list
        .where((r) => r.status == 'deposit_required')
        .toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
});

/// LEGACY — pay-before-dispatch bookings from the retired flow, still
/// re-priceable so in-flight documents can be corrected.
final awaitingPaymentQueueProvider = Provider<List<AdminCareRequest>>((ref) {
  final async = ref.watch(adminRequestsProvider);
  return async.maybeWhen(
    data: (list) => list
        .where((r) => r.status == 'amount_assigned_awaiting_final_payment')
        .toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
});

class AdminBookingReviewPage extends ConsumerWidget {
  const AdminBookingReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminRequestsProvider);
    final queue = ref.watch(bookingReviewQueueProvider);
    final quoted = ref.watch(awaitingDepositQueueProvider);
    final priced = ref.watch(awaitingPaymentQueueProvider);

    return Container(
      color: MtColors.bg,
      child: async.when(
        loading: () => const _LoadingList(),
        error: (e, _) => _ErrorBlock(
          message: e.toString(),
          onRetry: () => ref.invalidate(adminRequestsProvider),
        ),
        data: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(count: queue.length),
              const SizedBox(height: 20),
              if (queue.isEmpty)
                const _EmptyQueue()
              else
                _BookingCard(
                  requests: queue,
                  isReprice: false,
                ),
              if (quoted.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text('Quoted — awaiting the deposit', style: MtTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  'You have set the fee and deposit for these; the patient '
                  'has been notified and now has to pay. No action needed '
                  'unless a second call changes the numbers. No provider can '
                  'be dispatched until the deposit clears.',
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 16),
                _BookingCard(requests: quoted, isReprice: true),
              ],
              if (priced.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text('Legacy: awaiting payment', style: MtTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  'Older bookings that still pay before dispatch. Edit the '
                  'fee to correct it and re-notify the client. New bookings '
                  'pay a deposit up front and the balance after the visit.',
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 16),
                _BookingCard(requests: priced, isReprice: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Booking review', style: MtTextStyles.h2),
              const SizedBox(height: 4),
              Text(
                'Free requests awaiting your review call. Phone the patient, '
                'assess the case, then set the service fee and the advance '
                'deposit that confirms their visit.',
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
          ),
          child: Text(
            '$count awaiting',
            style: MtTextStyles.labelMd.copyWith(
              color: _kAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The rounded list card wrapping a set of booking rows. Shared by both the
/// deposit-review queue (`isReprice: false`) and the priced-awaiting-payment
/// list (`isReprice: true`).
class _BookingCard extends StatelessWidget {
  final List<AdminCareRequest> requests;
  final bool isReprice;
  const _BookingCard({required this.requests, required this.isReprice});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          for (int i = 0; i < requests.length; i++) ...[
            _BookingRow(request: requests[i], isReprice: isReprice),
            if (i != requests.length - 1)
              const Divider(height: 1, color: MtColors.line),
          ],
        ],
      ),
    );
  }
}

class _BookingRow extends ConsumerWidget {
  final AdminCareRequest request;
  final bool isReprice;
  const _BookingRow({required this.request, this.isReprice = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openReview(context, ref, request, isReprice: isReprice),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _initials(request.patientName),
                  style: MtTextStyles.labelLg.copyWith(color: _kAccent),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.patientName.isEmpty
                          ? 'Patient'
                          : request.patientName,
                      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.location.isEmpty
                          ? '—'
                          : request.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusPill(
                    isReprice: isReprice,
                    priced: (request.adjustedPrice ?? 0) > 0,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        isReprice ? 'Edit fee' : 'Set fee',
                        style: MtTextStyles.labelMd.copyWith(color: _kAccent),
                      ),
                      Icon(isReprice ? Icons.edit_outlined : Icons.chevron_right,
                          size: isReprice ? 15 : 18, color: _kAccent),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isReprice;
  final bool priced;
  const _StatusPill({required this.isReprice, this.priced = false});

  @override
  Widget build(BuildContext context) {
    // Review rows read "DEPOSIT PAID" (green) until a fee is saved, then
    // "PRICED — ASSIGN TEAM" (indigo); legacy already-priced rows read
    // "AWAITING PAYMENT" (amber) so the sections are visually distinct.
    final color = isReprice
        ? const Color(0xFFB45309)
        : (priced ? _kAccent : MtColors.completed);
    final bg = isReprice
        ? const Color(0xFFFDF0DC)
        : (priced
            ? _kAccent.withValues(alpha: 0.12)
            : MtColors.completedBg);
    final label = isReprice
        ? 'AWAITING PAYMENT'
        : (priced ? 'PRICED — ASSIGN TEAM' : 'DEPOSIT PAID');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: MtTextStyles.labelSm.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openReview(
  BuildContext context,
  WidgetRef ref,
  AdminCareRequest request, {
  bool isReprice = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BookingReviewDialog(request: request, isReprice: isReprice),
  );
}

class _BookingReviewDialog extends ConsumerStatefulWidget {
  final AdminCareRequest request;
  final bool isReprice;
  const _BookingReviewDialog({required this.request, this.isReprice = false});

  @override
  ConsumerState<_BookingReviewDialog> createState() =>
      _BookingReviewDialogState();
}

class _BookingReviewDialogState extends ConsumerState<_BookingReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _feeCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _noteCtrl.text = widget.request.adminNote ?? '';
    // On a re-price, seed the fee with the currently-assigned amount when the
    // feed carries it (falls back to empty otherwise; the admin re-confirms).
    final assigned = widget.request.adjustedPrice;
    if (widget.isReprice && assigned != null && assigned > 0) {
      _feeCtrl.text = assigned.round().toString();
    }
    // Seed the deposit with any standing quote, so reopening a booking
    // mid-Phase-2 shows what the patient was already asked for rather than a
    // blank field the admin might refill with a different number.
    final quoted = widget.request.requiredDeposit;
    if (quoted != null && quoted > 0) {
      _depositCtrl.text = quoted.round().toString();
    }
    _feeCtrl.addListener(_recompute);
    _depositCtrl.addListener(_recompute);
    _discountCtrl.addListener(_recompute);
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    _depositCtrl.dispose();
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _recompute() => setState(() {});

  double get _fee => double.tryParse(_feeCtrl.text.trim()) ?? 0;
  double get _depositInput => double.tryParse(_depositCtrl.text.trim()) ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;

  /// What this booking ACTUALLY paid, off the row — never the platform's
  /// configured default. The backend computes the balance as
  /// `fee − deposit_amount − discount`, so any other figure here would preview
  /// a total the server then refuses.
  double get _deposit => widget.request.depositAmount;

  /// PHASE 2 vs PHASE 3 — the switch this dialog branches on.
  ///
  /// Before any deposit is collected the admin is running the review call and
  /// must commit BOTH numbers through `set-deposit`. Afterwards the fee is a
  /// correction, and `set-price` leaves the collected deposit alone.
  bool get _isDepositPhase => _deposit <= 0;

  /// The deposit that applies to the outstanding preview: what was collected
  /// if anything was, otherwise what is being quoted right now.
  double get _effectiveDeposit => _isDepositPhase ? _depositInput : _deposit;

  double get _outstanding {
    final owed = _fee - _effectiveDeposit - _discount;
    return owed < 0 ? 0 : owed;
  }

  Future<void> _call() => _launch('tel:${_phoneDigits()}');
  Future<void> _text() => _launch('sms:${_phoneDigits()}');

  String _phoneDigits() =>
      (widget.request.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _launch(String uri) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_phoneDigits().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No phone number on file for this client.')),
      );
      return;
    }
    try {
      final ok = await launchUrl(Uri.parse(uri));
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the dialer.')),
      );
    }
  }

  Future<void> _finalize() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final dio = ref.read(dioClientProvider);
    try {
      if (_isDepositPhase) {
        // PHASE 2 — commit the fee AND the deposit together, which moves the
        // booking to `deposit_required` and prompts the patient to pay.
        await dio.adminSetBookingDeposit(
          widget.request.id,
          totalServiceFee: _fee,
          requiredDeposit: _depositInput,
          adjustedDiscount: _discount,
          adminNote:
              _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      } else {
        // PHASE 3+ — a fee correction on a booking whose deposit is already
        // collected. Leaves the deposit untouched and prompts nobody.
        await dio.adminSetBookingPrice(
          widget.request.id,
          finalServiceFee: _fee,
          adjustedDiscount: _discount,
          adminNote:
              _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }
      // Re-read the shared care-requests feed so the queue + counts refresh.
      ref.invalidate(adminRequestsProvider);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isDepositPhase
                ? 'Deposit of ${_money(_depositInput)} requested — '
                    '${widget.request.patientName} has been notified '
                    '(${_money(_outstanding)} due after the visit).'
                : 'Fee updated — ${widget.request.patientName} re-notified '
                    '(outstanding ${_money(_outstanding)}).',
          ),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.isReprice
                              ? 'Update invoice'
                              : 'Finalise invoice', style: MtTextStyles.h3),
                          const SizedBox(height: 2),
                          Text(
                            'Booking #${r.id}',
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: MtColors.ink3),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailBlock(request: r),
                const SizedBox(height: 20),
                // Quick-action contact row.
                Row(
                  children: [
                    Expanded(
                      child: _ContactButton(
                        icon: Icons.call,
                        label: 'Call client',
                        onTap: _call,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ContactButton(
                        icon: Icons.sms_outlined,
                        label: 'Text details',
                        onTap: _text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _Label('Total service fee (৳)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _feeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _fieldDecoration('e.g. 2500'),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter a fee greater than 0';
                    if (n - _effectiveDeposit - _discount < 0) {
                      return _effectiveDeposit > 0
                          ? 'Fee must cover the '
                              '${_money(_effectiveDeposit)} deposit + discount'
                          : 'Fee must cover the discount';
                    }
                    return null;
                  },
                ),
                // PHASE 2 — the advance deposit. Editable only until money
                // lands: once a deposit is PAID, changing what was asked for
                // would move the goalposts under a patient who already settled
                // it, so the field disappears and the invoice preview below
                // states the collected amount instead.
                if (_isDepositPhase) ...[
                  const SizedBox(height: 16),
                  _Label('Required advance deposit (৳)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _depositCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: _fieldDecoration('e.g. 500'),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) {
                        return 'Enter the deposit that confirms this visit';
                      }
                      if (n > _fee) {
                        return 'Deposit cannot exceed the total service fee';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The patient pays this to confirm the visit; it is '
                    'deducted from their final bill. No provider can be '
                    'dispatched until it clears.',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                ],
                const SizedBox(height: 16),
                _Label('Promotional discount (৳, optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _discountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _fieldDecoration('0'),
                ),
                const SizedBox(height: 16),
                _Label('Call summary / notes (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  decoration:
                      _fieldDecoration('Summary of your onboarding call…'),
                ),
                const SizedBox(height: 20),
                _InvoicePreview(
                  fee: _fee,
                  deposit: _effectiveDeposit,
                  depositPaid: !_isDepositPhase,
                  discount: _discount,
                  outstanding: _outstanding,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
                  ),
                ],
                const SizedBox(height: 22),
                MtButton(
                  label: widget.isReprice
                      ? 'Update Fee & Re-notify Client'
                      : 'Save Final Price',
                  onPressed: _finalize,
                  isLoading: _busy,
                  leadingIcon: Icons.check_circle_outline,
                  backgroundColor: MtColors.completed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final AdminCareRequest request;
  const _DetailBlock({required this.request});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Client', request.patientName.isEmpty ? '—' : request.patientName),
      ('Phone', request.phone?.isNotEmpty == true ? request.phone! : '—'),
      ('Service', request.serviceName),
      ('Location', request.location.isEmpty ? '—' : request.location),
      if ((request.notes ?? '').isNotEmpty) ('Condition', request.notes!),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      row.$1,
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style:
                          MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
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

class _InvoicePreview extends StatelessWidget {
  final double fee;

  /// The deposit that applies: what was COLLECTED once [depositPaid], and what
  /// the admin is currently quoting before then. 0 hides the line entirely
  /// rather than showing "- ৳0".
  final double deposit;

  /// Whether [deposit] is money in hand or a figure still being asked for.
  /// Only the wording changes — the arithmetic is identical, which is the
  /// point: the admin previews the same balance either way.
  final bool depositPaid;
  final double discount;
  final double outstanding;

  const _InvoicePreview({
    required this.fee,
    required this.deposit,
    required this.depositPaid,
    required this.discount,
    required this.outstanding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          _row('Total service fee', _money(fee), MtColors.ink),
          if (deposit > 0) ...[
            const SizedBox(height: 8),
            _row(
              depositPaid
                  ? 'Advance deposit (paid)'
                  : 'Advance deposit (requested)',
              '- ${_money(deposit)}',
              depositPaid ? MtColors.completed : MtColors.ink,
            ),
          ],
          if (discount > 0) ...[
            const SizedBox(height: 8),
            _row('Discount applied', '- ${_money(discount)}',
                MtColors.completed),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: MtColors.line),
          ),
          _row('Remaining after visit', _money(outstanding), _kAccent,
              emphasize: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor,
      {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: (emphasize ? MtTextStyles.labelLg : MtTextStyles.bodyMd)
              .copyWith(color: emphasize ? MtColors.ink : MtColors.ink2),
        ),
        Text(
          value,
          style: (emphasize ? MtTextStyles.h3 : MtTextStyles.labelMd)
              .copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _kAccent),
              const SizedBox(width: 8),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(color: _kAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: MtTextStyles.sectionLabel
          .copyWith(color: MtColors.ink3, letterSpacing: 0.8),
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MtColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MtColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _kAccent, width: 1.5),
    ),
  );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

// ===========================================================================
// Loading / empty / error
// ===========================================================================

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MtSkeleton.line(width: 200, height: 24),
          const SizedBox(height: 20),
          MtSkeleton.box(height: 88, radius: 12),
          const SizedBox(height: 12),
          MtSkeleton.box(height: 88, radius: 12),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40),
      child: MtEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No bookings to price',
        subtitle:
            'Deposit-paid bookings awaiting a final service fee will appear here.',
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MtEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load bookings',
        subtitle: message,
        actionLabel: 'Retry',
        onAction: onRetry,
      ),
    );
  }
}
