import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/provider_wallet.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../../auth/auth_provider.dart';
import '../providers/nurse_workflow_provider.dart';

/// The provider Wallet — the doctor/nurse view of the commission-split ledger.
///
/// Shared by BOTH provider shells (it replaced the nurse's Earnings tab and is
/// the doctor's new Wallet tab), because a doctor and a nurse have exactly the
/// same relationship to their money: the backend resolves the wallet from the
/// session, so there is nothing role-specific to branch on.
///
/// Three questions, answered top to bottom:
///   1. What can I take out right now?  → the hero card + Withdraw
///   2. What am I carrying / what have I made?  → the two stat cards
///   3. Where did it all come from?  → the transaction history
///
/// Balances refresh off the `wallet_updated` socket signal, so a visit
/// settling or an admin approving a payout moves the numbers immediately.

final _moneyFmt = NumberFormat('#,##0', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

class ProviderWalletPage extends ConsumerWidget {
  const ProviderWalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Any money movement — a visit settling, a withdrawal held, an admin
    // approving/rejecting, cash cleared — re-pulls both halves of the page.
    ref.listen(walletUpdatedSignalProvider, (_, _) {
      ref.invalidate(providerWalletProvider);
      ref.invalidate(walletTransactionsProvider);
    });
    // The legacy cash-clearance signal predates `wallet_updated` and still
    // fires; keep listening so an older server build also zeroes the card.
    ref.listen(cashLedgerClearedSignalProvider, (_, _) {
      ref.invalidate(providerWalletProvider);
      ref.invalidate(walletTransactionsProvider);
    });

    final snapshot = ref.watch(providerWalletProvider);

    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async {
        ref.invalidate(providerWalletProvider);
        ref.invalidate(walletTransactionsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          snapshot.when(
            loading: () => const _WalletOverviewSkeleton(),
            error: (e, _) => _WalletError(
              message: e.toString(),
              onRetry: () => ref.invalidate(providerWalletProvider),
            ),
            data: (snap) => _WalletOverview(snapshot: snap),
          ),
          const SizedBox(height: 22),
          Text(
            'TRANSACTION HISTORY',
            style: MtTextStyles.sectionLabel
                .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
          ),
          const SizedBox(height: 10),
          const _TransactionHistory(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Overview — balances, warnings, and the withdraw entry point
// ═══════════════════════════════════════════════════════════════════════════

class _WalletOverview extends ConsumerWidget {
  final ProviderWalletSnapshot snapshot;
  const _WalletOverview({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = snapshot.wallet;
    final pending = snapshot.pendingRequest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AvailableBalanceCard(snapshot: snapshot),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _WalletStatCard(
                label: 'CASH IN HAND',
                value: _money(w.cashInHand),
                caption: 'Company cash you are holding',
                icon: Icons.payments_outlined,
                accent: snapshot.limits.isOverCashLimit
                    ? context.appColors.warning
                    : MtColors.ink2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WalletStatCard(
                label: 'LIFETIME EARNED',
                value: _money(w.totalEarned),
                caption: '${_money(w.totalWithdrawn)} withdrawn',
                icon: Icons.trending_up_rounded,
                accent: context.appColors.positive,
              ),
            ),
          ],
        ),
        // The server authors the lock explanation; render it verbatim rather
        // than re-deriving the threshold rule on the client.
        if (snapshot.lockReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          _WalletBanner(
            icon: Icons.lock_outline_rounded,
            color: context.appColors.warning,
            background: context.appColors.warningBg,
            title: 'Withdrawals locked',
            body: snapshot.lockReason,
          ),
        ],
        if (pending != null) ...[
          const SizedBox(height: 12),
          _WalletBanner(
            icon: Icons.hourglass_bottom_rounded,
            color: context.appColors.info,
            background: context.appColors.infoBg,
            title: '${_money(pending.amount)} withdrawal pending',
            body:
                'Requested via ${pending.method}. The office will process it '
                'shortly — you can request another once this one is settled.',
          ),
        ],
      ],
    );
  }
}

/// The hero: withdrawable funds and the action that moves them.
class _AvailableBalanceCard extends ConsumerWidget {
  final ProviderWalletSnapshot snapshot;
  const _AvailableBalanceCard({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = snapshot.wallet;
    // A negative balance is a real state (commission owed on cash visits that
    // no digital earning has offset yet), so it gets its own treatment rather
    // than rendering as a confusing "-৳100 available".
    final isNegative = w.digitalBalance < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MtColors.brand, MtColors.brand700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white.withValues(alpha: 0.9), size: 18),
              const SizedBox(width: 8),
              Text(
                'AVAILABLE FOR WITHDRAWAL',
                style: MtTextStyles.sectionLabel.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _money(w.digitalBalance),
            style: MtTextStyles.displayLg.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isNegative
                ? 'Commission owed on cash visits. Your next digital visit '
                    'clears it.'
                : 'Paid out to your bKash, Nagad or bank account',
            style: MtTextStyles.bodySm
                .copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: snapshot.canWithdraw
                  ? () => _openWithdrawSheet(context, ref, snapshot)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: MtColors.brand700,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.north_east_rounded, size: 18),
              label: Text(
                _withdrawLabel(snapshot),
                style: MtTextStyles.labelLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: snapshot.canWithdraw
                      ? MtColors.brand700
                      : Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          if (!snapshot.canWithdraw &&
              snapshot.lockReason.isEmpty &&
              snapshot.pendingRequest == null) ...[
            const SizedBox(height: 8),
            Text(
              'Minimum withdrawal is ${_money(snapshot.limits.minWithdrawal)}.',
              style: MtTextStyles.bodySm
                  .copyWith(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
          // Keep the commission rate visible so the split on each history row
          // is never a surprise.
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'You keep ${100 - snapshot.limits.commissionPercent}% of every visit',
              style: MtTextStyles.labelSm.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _withdrawLabel(ProviderWalletSnapshot snap) {
    if (snap.wallet.isPayoutLocked) return 'Withdrawals locked';
    if (snap.pendingRequest != null) return 'Withdrawal pending';
    return 'Withdraw funds';
  }

  Future<void> _openWithdrawSheet(
    BuildContext context,
    WidgetRef ref,
    ProviderWalletSnapshot snap,
  ) async {
    final requested = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WithdrawSheet(snapshot: snap),
    );
    if (requested == true) {
      ref.invalidate(providerWalletProvider);
      ref.invalidate(walletTransactionsProvider);
    }
  }
}

class _WalletStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;

  const _WalletStatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelSm
                      .copyWith(color: MtColors.ink3, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.h2.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _WalletBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String body;

  const _WalletBanner({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Withdrawal sheet
// ═══════════════════════════════════════════════════════════════════════════

const _kMethods = ['bKash', 'Nagad', 'Bank'];

class _WithdrawSheet extends ConsumerStatefulWidget {
  final ProviderWalletSnapshot snapshot;
  const _WithdrawSheet({required this.snapshot});

  @override
  ConsumerState<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<_WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _accountNumber;
  late final TextEditingController _accountName;
  late final TextEditingController _bankName;
  late final TextEditingController _branch;

  late String _method;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = widget.snapshot.payoutDetails;
    _method = _kMethods.contains(saved.method) ? saved.method! : 'bKash';
    _amount = TextEditingController();
    // The saved account number arrives MASKED, so it can't be prefilled as a
    // real value — the provider re-enters it (or leaves it blank and the
    // server falls back to the stored one). We show the last 4 as a hint.
    _accountNumber = TextEditingController();
    _accountName = TextEditingController(text: saved.accountName);
    _bankName = TextEditingController(text: saved.bankName);
    _branch = TextEditingController(text: saved.branch);
  }

  @override
  void dispose() {
    _amount.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    _bankName.dispose();
    _branch.dispose();
    super.dispose();
  }

  bool get _isBank => _method == 'Bank';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).requestWithdrawal(
            amount: num.parse(_amount.text.trim()),
            method: _method,
            accountNumber: _accountNumber.text.trim(),
            accountName: _accountName.text.trim(),
            bankName: _isBank ? _bankName.text.trim() : null,
            branch: _isBank ? _branch.text.trim() : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal requested. The office will process it shortly.',
          ),
          backgroundColor: context.appColors.positive,
        ),
      );
    } catch (e) {
      // Server messages are written for the provider (insufficient balance, a
      // cash lock, an existing pending request) — surface them as-is.
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final snap = widget.snapshot;
    final saved = snap.payoutDetails;
    final available = snap.wallet.digitalBalance;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: MtColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MtColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Withdraw funds',
                  style: MtTextStyles.h2.copyWith(color: MtColors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_money(available)} available',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
                const SizedBox(height: 18),

                // ── Amount ────────────────────────────────────────────────
                Text(
                  'AMOUNT',
                  style: MtTextStyles.sectionLabel
                      .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: '৳ ',
                    hintText: '0',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: TextButton(
                      onPressed: () => setState(
                        () => _amount.text = available.round().toString(),
                      ),
                      child: const Text('MAX'),
                    ),
                  ),
                  validator: (v) {
                    final parsed = num.tryParse((v ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter an amount to withdraw.';
                    }
                    if (parsed < snap.limits.minWithdrawal) {
                      return 'Minimum withdrawal is '
                          '${_money(snap.limits.minWithdrawal)}.';
                    }
                    if (parsed > available) {
                      return 'You only have ${_money(available)} available.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // ── Method ────────────────────────────────────────────────
                Text(
                  'PAYOUT METHOD',
                  style: MtTextStyles.sectionLabel
                      .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final m in _kMethods) ...[
                      Expanded(
                        child: _MethodChip(
                          label: m == 'Bank' ? 'Bank Transfer' : m,
                          selected: _method == m,
                          onTap: () => setState(() => _method = m),
                        ),
                      ),
                      if (m != _kMethods.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                // ── Destination (fields switch on the method) ─────────────
                Text(
                  _isBank ? 'BANK ACCOUNT' : '$_method ACCOUNT',
                  style: MtTextStyles.sectionLabel
                      .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _accountNumber,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText:
                        _isBank ? 'Account number' : '$_method account number',
                    hintText: saved.hasDestination
                        ? 'Saved: •••• ${saved.accountNumberLast4}'
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) {
                    // Blank is allowed only when the server has a saved
                    // destination it can fall back to.
                    if ((v ?? '').trim().isEmpty && !saved.hasDestination) {
                      return 'Enter the account number to withdraw to.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accountName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Account holder name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_isBank) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bankName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Bank name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter the bank name.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _branch,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.dangerBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: c.danger, size: 18),
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

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: MtColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Request withdrawal',
                            style: MtTextStyles.labelLg.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The amount is held from your balance immediately and paid '
                  'once the office approves it.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? MtColors.brandSofter : MtColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MtColors.brand : MtColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: MtTextStyles.labelMd.copyWith(
              color: selected ? MtColors.brand700 : MtColors.ink2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Transaction history
// ═══════════════════════════════════════════════════════════════════════════

class _TransactionHistory extends ConsumerWidget {
  const _TransactionHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(walletTransactionsProvider);
    return async.when(
      loading: () => ShimmerLoadingPlaceholder(
        child: Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      error: (e, _) => _WalletError(
        message: e.toString(),
        onRetry: () => ref.invalidate(walletTransactionsProvider),
      ),
      data: (items) {
        if (items.isEmpty) return const _EmptyLedger();
        return Container(
          decoration: BoxDecoration(
            color: MtColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MtColors.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _TransactionRow(tx: items[i]),
                if (i != items.length - 1)
                  Divider(height: 1, color: MtColors.line),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    // Credit green / debit red. A PAYOUT_PAID marker moves no balance, so it
    // reads neutral rather than claiming a direction it doesn't have.
    final isNeutral = tx.direction == 'NONE';
    final accent = isNeutral
        ? MtColors.ink3
        : (tx.isCredit ? c.positive : c.danger);
    final accentBg = isNeutral
        ? MtColors.bg
        : (tx.isCredit ? c.positiveBg : c.dangerBg);
    final sign = isNeutral ? '' : (tx.isCredit ? '+' : '−');
    final date = tx.createdAt;
    final dateLabel =
        date == null ? '' : DateFormat('d MMM y · h:mm a').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(tx.type), size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx.typeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.labelMd.copyWith(
                          color: MtColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$sign${_money(tx.amount)}',
                      style: MtTextStyles.labelLg.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  tx.description,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (tx.isCashLedger)
                      _MiniTag(label: 'CASH', color: c.warning),
                    if (tx.shortBookingRef.isNotEmpty)
                      _MiniTag(
                        label: tx.shortBookingRef,
                        color: MtColors.ink3,
                      ),
                    if (tx.patientName.isNotEmpty)
                      _MiniTag(label: tx.patientName, color: MtColors.ink3),
                    if (tx.referenceId.isNotEmpty)
                      _MiniTag(
                        label: 'REF ${tx.referenceId}',
                        color: MtColors.ink3,
                      ),
                  ],
                ),
                // The split, spelled out — the provider can reconcile a
                // payout against the invoice without asking anyone.
                if (tx.hasBreakdown) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_money(tx.grossAmount)} visit  ·  '
                    '−${_money(tx.platformFee)} platform '
                    '(${tx.commissionPercent}%)  ·  '
                    '${_money(tx.providerNet)} yours',
                    style: MtTextStyles.bodySm.copyWith(
                      color: MtColors.ink3,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    dateLabel,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink3, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'VISIT_EARNING':
        return Icons.medical_services_outlined;
      case 'CASH_COLLECTION':
        return Icons.payments_outlined;
      case 'COMMISSION_DEBIT':
        return Icons.percent_rounded;
      case 'PAYOUT_HOLD':
        return Icons.north_east_rounded;
      case 'PAYOUT_PAID':
        return Icons.check_circle_outline_rounded;
      case 'PAYOUT_REVERSAL':
        return Icons.undo_rounded;
      case 'CASH_CLEARANCE':
        return Icons.account_balance_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: MtTextStyles.labelSm.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty / loading / error states
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 30, color: MtColors.ink3),
          const SizedBox(height: 10),
          Text(
            'No transactions yet',
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Your earnings appear here the moment a visit is settled.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _WalletOverviewSkeleton extends StatelessWidget {
  const _WalletOverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerLoadingPlaceholder(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 104,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 104,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _WalletError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: MtColors.rejected, size: 28),
          const SizedBox(height: 8),
          Text(
            "Couldn't load your wallet",
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            message.replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry,
            child: Text('Retry', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
  }
}
