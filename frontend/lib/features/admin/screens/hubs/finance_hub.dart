import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin_nav.dart';
import '../../admin_providers.dart';
import '../tabs/admin_cash_clearance_page.dart';
import '../tabs/admin_finance_page.dart';
import '../tabs/billing_tab.dart';
import 'hub_scaffold.dart';

/// Money in one place: the completed-care ledger, the un-remitted cash
/// terminal, and the provider withdrawal queue.
///
/// These three were adjacent sidebar entries that an admin works as a single
/// end-of-day pass, so the hand-off between them (a payout can't be approved
/// before the provider's cash is cleared) is now a tab switch rather than a
/// navigation.
class FinanceHub extends ConsumerWidget {
  const FinanceHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(financeTabProvider);
    final cashOutstanding = ref.watch(cashInHandProvider).maybeWhen(
          data: (s) => s.outstandingProvidersCount,
          orElse: () => 0,
        );
    final pendingPayouts = ref.watch(payoutRequestsProvider).maybeWhen(
          data: (q) => q.pendingCount,
          orElse: () => 0,
        );

    return HubScaffold<FinanceTab>(
      selected: selected,
      onSelect: (tab) => ref.read(financeTabProvider.notifier).state = tab,
      tabs: [
        HubTab(
          value: FinanceTab.billing,
          label: FinanceTab.billing.label,
          icon: Icons.receipt_long_outlined,
        ),
        HubTab(
          value: FinanceTab.cashClearance,
          label: FinanceTab.cashClearance.label,
          icon: Icons.account_balance_wallet_outlined,
          count: cashOutstanding,
        ),
        HubTab(
          value: FinanceTab.payouts,
          label: FinanceTab.payouts.label,
          icon: Icons.payments_outlined,
          count: pendingPayouts,
        ),
      ],
      body: switch (selected) {
        FinanceTab.billing => const BillingTab(),
        FinanceTab.cashClearance => const AdminCashClearancePage(),
        FinanceTab.payouts => const AdminFinancePage(),
      },
    );
  }
}
