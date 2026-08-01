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

/// Fixed slot-confirmation deposit (kept in lockstep with the backend).
const double _kDeposit = 100;

/// Neutral indigo accent for the booking-review surface — deliberately NOT
/// the orange brand, per the two-phase-invoice design language.
const Color _kAccent = Color(0xFF4F46E5);

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

/// The admin triage queue: bookings whose ৳100 deposit has cleared and are
/// awaiting a final service fee. Filtered off the shared care-requests feed.
final bookingReviewQueueProvider = Provider<List<AdminCareRequest>>((ref) {
  final async = ref.watch(adminRequestsProvider);
  return async.maybeWhen(
    data: (list) => list
        .where((r) => r.status == 'deposit_paid_admin_reviewing')
        .toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
});

/// Badge count for the sidebar.
final bookingReviewCountProvider = Provider<int>(
  (ref) => ref.watch(bookingReviewQueueProvider).length,
);

/// Already-priced bookings still awaiting the patient's balance payment. The
/// admin can RE-price these (the backend accepts a second set-price and
/// re-notifies the patient) — surfaced as an "Edit fee" section below the
/// primary review queue.
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
              if (priced.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text('Legacy: awaiting payment', style: MtTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  'Older bookings that still pay before dispatch. Edit the '
                  'fee to correct it and re-notify the client. New bookings '
                  'stay in the review queue and pay after the visit.',
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
                'Deposit-paid bookings awaiting a final service fee. Contact '
                'the client, then finalise the invoice.',
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
    _feeCtrl.addListener(_recompute);
    _discountCtrl.addListener(_recompute);
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _recompute() => setState(() {});

  double get _fee => double.tryParse(_feeCtrl.text.trim()) ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _outstanding {
    final owed = _fee - _kDeposit - _discount;
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
    try {
      await ref.read(dioClientProvider).adminSetBookingPrice(
            widget.request.id,
            finalServiceFee: _fee,
            adjustedDiscount: _discount,
            adminNote: _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
          );
      // Re-read the shared care-requests feed so the queue + counts refresh.
      ref.invalidate(adminRequestsProvider);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isReprice
                ? 'Fee updated — ${widget.request.patientName} re-notified '
                    '(outstanding ${_money(_outstanding)}).'
                : 'Price saved (outstanding ${_money(_outstanding)} due after '
                    'the visit). Assign a team to dispatch this booking.',
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
                _Label('Base service fee (৳)'),
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
                    if (n - _kDeposit - _discount < 0) {
                      return 'Fee must cover the ৳100 deposit + discount';
                    }
                    return null;
                  },
                ),
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
  final double discount;
  final double outstanding;

  const _InvoicePreview({
    required this.fee,
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
          _row('Base service fee', _money(fee), MtColors.ink),
          const SizedBox(height: 8),
          _row('Confirmation deposit (deducted)', '- ${_money(_kDeposit)}',
              MtColors.completed),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            _row('Discount applied', '- ${_money(discount)}',
                MtColors.completed),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: MtColors.line),
          ),
          _row('Total outstanding', _money(outstanding), _kAccent,
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
