import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/provider_wallet.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_providers.dart';
import 'admin_table_chrome.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';
final _requestedFmt = DateFormat('MMM d, y · h:mm a');

/// Provider Payouts console — the admin approval desk for withdrawal requests
/// filed against a provider's wallet balance.
///
/// The money already left the provider's `digitalBalance` when they requested
/// it (the server holds funds at request time, not approval), so the two
/// actions here mean:
///   • Approve → confirm the transfer actually happened, against a bank/MFS
///     reference. Moves no balance; bumps lifetime `totalWithdrawn`.
///   • Reject  → return the held funds to the provider's available balance.
///
/// The *other* half of the finance desk — reconciling physical cash providers
/// collected at the door — lives on the Cash Clearance page, which predates
/// this one and already does the job. This page links across to it rather
/// than duplicating that table.
class AdminFinancePage extends ConsumerWidget {
  /// Navigates the console to another tab index. Used for the cross-link to
  /// Cash Clearance (tab 14).
  final void Function(int index)? onNavigateTab;

  const AdminFinancePage({super.key, this.onNavigateTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payoutRequestsProvider);
    return AdminListScaffold(
      title: 'Provider Payouts',
      subtitle:
          'Withdrawal requests against provider wallet balances, awaiting approval',
      onRefresh: () => ref.read(payoutRequestsProvider.notifier).refresh(),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.read(payoutRequestsProvider.notifier).refresh(),
        ),
        data: (queue) =>
            _PayoutsView(queue: queue, onNavigateTab: onNavigateTab),
      ),
    );
  }
}

class _PayoutsView extends StatelessWidget {
  final PayoutQueue queue;
  final void Function(int index)? onNavigateTab;

  const _PayoutsView({required this.queue, this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final pending = queue.items.where((p) => p.isPending).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Pending requests',
                value: queue.pendingCount.toString(),
                icon: Icons.hourglass_bottom_outlined,
                accent: MtColors.pending,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Pending payout value',
                value: _money(queue.pendingTotal),
                icon: Icons.account_balance_wallet_outlined,
                accent: MtColors.brand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CashClearanceLink(onNavigateTab: onNavigateTab),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (pending.isEmpty)
          const AdminEmptyState(
            icon: Icons.payments_outlined,
            title: 'No withdrawal requests',
            subtitle:
                'When a doctor or nurse requests a payout, it lands here for approval.',
          )
        else
          AdminCard(
            child: Column(
              children: [
                const _PayoutTableHeader(),
                for (var i = 0; i < pending.length; i++) ...[
                  _PayoutRow(payout: pending[i]),
                  if (i != pending.length - 1)
                    const Divider(height: 1, color: MtColors.line),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Cross-link tile to the pre-existing Cash Clearance terminal (tab 14), so
/// the finance desk reads as one place even though it is two screens.
class _CashClearanceLink extends ConsumerWidget {
  final void Function(int index)? onNavigateTab;
  const _CashClearanceLink({this.onNavigateTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cash = ref.watch(cashInHandProvider).valueOrNull;
    final outstanding = cash?.totalCashInField ?? 0;
    return InkWell(
      onTap: onNavigateTab == null ? null : () => onNavigateTab!(14),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MtColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MtColors.completed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.payments_outlined,
                  size: 20, color: MtColors.completed),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cash in field',
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
                  const SizedBox(height: 4),
                  Text(_money(outstanding),
                      style: MtTextStyles.h3.copyWith(
                        color: MtColors.ink,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: MtColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
                const SizedBox(height: 4),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.h3.copyWith(
                      color: MtColors.ink,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ───────────────────────────────────────────────────────────────────

// Shared flex weights so the header and every row stay in lockstep.
const _kFlexProvider = 3;
const _kFlexAmount = 2;
const _kFlexChannel = 2;
const _kFlexDestination = 4;
const _kFlexRequested = 3;
const _kFlexActions = 3;

class _PayoutTableHeader extends StatelessWidget {
  const _PayoutTableHeader();

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int flex) => Expanded(
          flex: flex,
          child: Text(
            label,
            style: MtTextStyles.sectionLabel
                .copyWith(color: MtColors.ink3, letterSpacing: 0.8),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          cell('PROVIDER', _kFlexProvider),
          cell('AMOUNT', _kFlexAmount),
          cell('CHANNEL', _kFlexChannel),
          cell('ACCOUNT DETAILS', _kFlexDestination),
          cell('REQUESTED', _kFlexRequested),
          cell('', _kFlexActions),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final PayoutRequestModel payout;
  const _PayoutRow({required this.payout});

  @override
  Widget build(BuildContext context) {
    final requested = payout.requestedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Provider + role
          Expanded(
            flex: _kFlexProvider,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payout.providerName.isEmpty
                      ? 'Unknown provider'
                      : payout.providerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                _RolePill(role: payout.providerRole),
              ],
            ),
          ),
          Expanded(
            flex: _kFlexAmount,
            child: Text(
              _money(payout.amount),
              style: MtTextStyles.labelLg.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: _kFlexChannel,
            child: Text(
              payout.method == 'Bank' ? 'Bank transfer' : payout.method,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink),
            ),
          ),
          Expanded(
            flex: _kFlexDestination,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  payout.accountNumber.isEmpty ? '—' : payout.accountNumber,
                  maxLines: 1,
                  style: MtTextStyles.bodySm.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (payout.accountName.isNotEmpty ||
                    payout.bankName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (payout.accountName.isNotEmpty) payout.accountName,
                      if (payout.bankName.isNotEmpty) payout.bankName,
                      if (payout.branch.isNotEmpty) payout.branch,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: _kFlexRequested,
            child: Text(
              requested == null ? '—' : _requestedFmt.format(requested),
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
          ),
          Expanded(
            flex: _kFlexActions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      _openActionDialog(context, payout, approve: false),
                  style: TextButton.styleFrom(
                    foregroundColor: MtColors.rejected,
                  ),
                  child: Text('Reject', style: MtTextStyles.labelMd),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () =>
                      _openActionDialog(context, payout, approve: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: MtColors.completed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Approve',
                    style: MtTextStyles.labelMd.copyWith(color: Colors.white),
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

class _RolePill extends StatelessWidget {
  final String role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final isNurse = role == 'nurse';
    final color = isNurse ? MtColors.violet : MtColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isNurse ? 'NURSE' : 'DOCTOR',
        style: MtTextStyles.labelSm.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Action modals ───────────────────────────────────────────────────────────

/// Opens the shared action dialog. `approve: false` runs the reject path.
/// The dialog reads the notifier itself, so nothing needs threading through.
Future<void> _openActionDialog(
  BuildContext context,
  PayoutRequestModel payout, {
  required bool approve,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PayoutActionDialog(payout: payout, approve: approve),
  );
}

/// One dialog for both terminal actions — they share a shape (confirm the
/// payout, capture one required free-text field, submit) and differ only in
/// wording, colour, and which notifier method runs.
class _PayoutActionDialog extends ConsumerStatefulWidget {
  final PayoutRequestModel payout;
  final bool approve;

  const _PayoutActionDialog({required this.payout, required this.approve});

  @override
  ConsumerState<_PayoutActionDialog> createState() =>
      _PayoutActionDialogState();
}

class _PayoutActionDialogState extends ConsumerState<_PayoutActionDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _approve => widget.approve;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = _approve
            ? 'Enter the bank/MFS transaction reference.'
            : 'Enter a reason — the provider is told why.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final notifier = ref.read(payoutRequestsProvider.notifier);
      if (_approve) {
        await notifier.approve(
          payoutId: widget.payout.id,
          referenceId: value,
        );
      } else {
        await notifier.reject(payoutId: widget.payout.id, reason: value);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _approve
                ? 'Payout of ${_money(widget.payout.amount)} marked paid.'
                : 'Payout rejected — ${_money(widget.payout.amount)} returned '
                    'to the provider.',
          ),
          backgroundColor:
              _approve ? MtColors.completed : MtColors.rejected,
        ),
      );
    } catch (e) {
      // Server messages (e.g. a 409 when another admin already actioned it)
      // are written to be read — surface them verbatim.
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payout;
    final accent = _approve ? MtColors.completed : MtColors.rejected;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        _approve ? 'Approve & mark paid' : 'Reject withdrawal',
        style: MtTextStyles.h3.copyWith(color: MtColors.ink),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Restate exactly what is being actioned — this is money leaving
            // the business, so the confirmation shows the full destination.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MtColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MtColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailLine(
                    label: 'Provider',
                    value: p.providerName.isEmpty
                        ? 'Unknown provider'
                        : '${p.providerName}'
                            '${p.providerPhone.isEmpty ? '' : ' · ${p.providerPhone}'}',
                  ),
                  const SizedBox(height: 6),
                  _DetailLine(label: 'Amount', value: _money(p.amount)),
                  const SizedBox(height: 6),
                  _DetailLine(label: 'Send to', value: p.destinationLabel),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _approve
                  ? 'Enter the bank or MFS transaction reference for the '
                      'transfer you just made.'
                  : 'The held amount goes straight back to the provider’s '
                      'available balance.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: _approve ? 1 : 3,
              decoration: InputDecoration(
                labelText: _approve
                    ? 'Transaction reference'
                    : 'Reason for rejection',
                hintText: _approve ? 'e.g. BKH8X72LM01' : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) {
                if (_approve && !_submitting) _submit();
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MtColors.rejectedBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: MtColors.rejected),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: MtTextStyles.labelMd),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _approve ? 'Confirm payment' : 'Reject request',
                  style: MtTextStyles.labelMd.copyWith(color: Colors.white),
                ),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: MtTextStyles.bodySm.copyWith(
              color: MtColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
