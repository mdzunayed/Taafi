import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/provider_cash_ledger.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_providers.dart';
import '../../util/ledger_printer.dart';
import 'admin_table_chrome.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';
final _handoverDateFmt = DateFormat('MMM d, y · h:mm a');

/// Provider Cash Clearance Terminal — the admin-side reconciliation surface
/// for physical cash doctors/nurses collect at the door (CASH_TO_PROVIDER
/// settlements). Reads the outstanding-cash ledger via [cashInHandProvider]
/// and lets an admin "receive" that cash, which zeroes the provider's
/// `cash_in_hand` and appends an immutable CashHandoverLog on the backend.
class AdminCashClearancePage extends ConsumerWidget {
  const AdminCashClearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashInHandProvider);
    return AdminListScaffold(
      title: 'Provider Cash Clearance',
      subtitle:
          'Physical cash held by field doctors & nurses, awaiting handover to the office',
      onRefresh: () => ref.read(cashInHandProvider.notifier).refresh(),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.read(cashInHandProvider.notifier).refresh(),
        ),
        data: (summary) => _ClearanceView(summary: summary),
      ),
    );
  }
}

class _ClearanceView extends StatelessWidget {
  final CashInHandSummary summary;
  const _ClearanceView({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Summary cards ────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Total cash in field',
                value: _money(summary.totalCashInField),
                icon: Icons.account_balance_wallet_outlined,
                accent: MtColors.brand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Collected today',
                value: _money(summary.collectedToday),
                icon: Icons.check_circle_outline,
                accent: MtColors.completed,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Outstanding providers',
                value: summary.outstandingProvidersCount.toString(),
                icon: Icons.people_outline,
                accent: MtColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (summary.providers.isEmpty)
          const AdminEmptyState(
            icon: Icons.savings_outlined,
            title: 'All ledgers are clear',
            subtitle:
                'No field provider is currently holding un-remitted cash.',
          )
        else
          AdminCard(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(MtColors.brandSofter),
                headingTextStyle: MtTextStyles.labelSm.copyWith(
                  color: MtColors.ink3,
                  letterSpacing: 0.8,
                ),
                dataRowMinHeight: 60,
                dataRowMaxHeight: 72,
                columns: const [
                  DataColumn(label: Text('PROVIDER')),
                  DataColumn(label: Text('ROLE')),
                  DataColumn(label: Text('CONTACT')),
                  DataColumn(label: Text('LAST COLLECTION')),
                  DataColumn(label: Text('UNSETTLED CASH'), numeric: true),
                  DataColumn(label: Text('ACTION')),
                ],
                rows: [
                  for (final p in summary.providers)
                    DataRow(cells: [
                      DataCell(Text(p.name,
                          style: MtTextStyles.labelMd
                              .copyWith(color: MtColors.ink))),
                      DataCell(_RolePill(role: p.role)),
                      DataCell(_ContactCell(phone: p.phone)),
                      DataCell(Text(
                          p.lastCollectionAt == null
                              ? '—'
                              : _handoverDateFmt.format(
                                  p.lastCollectionAt!.toLocal()),
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink2))),
                      DataCell(Text(_money(p.cashInHand),
                          style: MtTextStyles.h3.copyWith(
                            color: MtColors.brand,
                            fontWeight: FontWeight.w800,
                          ))),
                      DataCell(_CollectButton(entry: p)),
                    ]),
                ],
              ),
            ),
          ),
      ],
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.h1
                        .copyWith(color: MtColors.ink, fontSize: 24)),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 0.8,
                    )),
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
    final color = isNurse ? const Color(0xFF7C3AED) : MtColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isNurse ? 'Nurse' : 'Doctor',
        style: MtTextStyles.labelSm.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ContactCell extends StatelessWidget {
  final String phone;
  const _ContactCell({required this.phone});

  Future<void> _launch(String uri) async {
    try {
      await launchUrl(Uri.parse(uri));
    } catch (_) {/* no dialer on desktop web — silent no-op */}
  }

  @override
  Widget build(BuildContext context) {
    if (phone.isEmpty) {
      return Text('—', style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(phone,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Call',
          visualDensity: VisualDensity.compact,
          onPressed: () => _launch('tel:$phone'),
          icon: const Icon(Icons.call, size: 16, color: MtColors.completed),
        ),
        IconButton(
          tooltip: 'SMS',
          visualDensity: VisualDensity.compact,
          onPressed: () => _launch('sms:$phone'),
          icon: const Icon(Icons.sms_outlined, size: 16, color: MtColors.ink3),
        ),
      ],
    );
  }
}

class _CollectButton extends ConsumerWidget {
  final ProviderCashLedgerEntry entry;
  const _CollectButton({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _openSettleModal(context, ref, entry),
      icon: const Icon(Icons.payments_outlined, size: 16),
      label: Text('Collect Cash',
          style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: MtColors.brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

Future<void> _openSettleModal(
  BuildContext context,
  WidgetRef ref,
  ProviderCashLedgerEntry entry,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _SettleCashModal(entry: entry, ref: ref),
  );
}

class _SettleCashModal extends StatefulWidget {
  final ProviderCashLedgerEntry entry;
  final WidgetRef ref;
  const _SettleCashModal({required this.entry, required this.ref});

  @override
  State<_SettleCashModal> createState() => _SettleCashModalState();
}

class _SettleCashModalState extends State<_SettleCashModal> {
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the full held balance — the common case is a clean handover.
    _amountCtrl = TextEditingController(
      text: widget.entry.cashInHand.toStringAsFixed(0),
    );
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _collected => double.tryParse(_amountCtrl.text.trim()) ?? 0;
  double get _discrepancy => widget.entry.cashInHand - _collected;

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result =
          await widget.ref.read(cashInHandProvider.notifier).settleProviderCash(
                providerId: widget.entry.accountId,
                amountCollected: _collected,
                adminNotes: _notesCtrl.text.trim(),
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showReceiptDialog(context, widget.entry, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: MtColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Receive cash from ${e.name}',
                        style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Held balance banner.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CASH HELD ON LEDGER',
                        style: MtTextStyles.labelSm.copyWith(
                          color: MtColors.ink3,
                          letterSpacing: 0.8,
                        )),
                    const SizedBox(height: 4),
                    Text(_money(e.cashInHand),
                        style: MtTextStyles.h1.copyWith(
                          color: MtColors.brand,
                          fontSize: 30,
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Physical cash received',
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
              const SizedBox(height: 6),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  prefixText: '৳ ',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              // Live discrepancy hint.
              if (_discrepancy.abs() >= 0.01)
                Row(
                  children: [
                    Icon(
                      _discrepancy > 0
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 16,
                      color: _discrepancy > 0
                          ? MtColors.rejected
                          : MtColors.ink3,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _discrepancy > 0
                            ? 'Short by ${_money(_discrepancy)} — recorded as a discrepancy.'
                            : 'Over by ${_money(-_discrepancy)} — recorded as a discrepancy.',
                        style: MtTextStyles.bodySm.copyWith(
                          color: _discrepancy > 0
                              ? MtColors.rejected
                              : MtColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Admin notes (optional)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.rejected)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting || _collected < 0 ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MtColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Confirm Handover & Zero Ledger',
                          style: MtTextStyles.labelLg
                              .copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showReceiptDialog(
  BuildContext context,
  ProviderCashLedgerEntry entry,
  CashSettlementResult result,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle,
                  color: MtColors.completed, size: 44),
              const SizedBox(height: 12),
              Text('Handover recorded',
                  textAlign: TextAlign.center,
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 6),
              Text('${entry.name}’s ledger is now settled to ৳0.',
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              const SizedBox(height: 18),
              _ReceiptRow(label: 'Receipt', value: result.receiptId),
              _ReceiptRow(
                  label: 'Expected', value: _money(result.expectedAmount)),
              _ReceiptRow(
                  label: 'Collected', value: _money(result.amountCollected)),
              if (result.discrepancy.abs() >= 0.01)
                _ReceiptRow(
                  label: 'Discrepancy',
                  value: _money(result.discrepancy),
                  emphasize: true,
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (ledgerPrintingSupported)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => printLedgerDocument(
                            _buildReceiptHtml(entry, result)),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: Text('Print', style: MtTextStyles.labelMd),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MtColors.ink,
                          side: const BorderSide(color: MtColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  if (ledgerPrintingSupported) const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MtColors.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Done',
                          style: MtTextStyles.labelLg
                              .copyWith(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.6,
              )),
          Text(value,
              style: MtTextStyles.labelMd.copyWith(
                color: emphasize ? MtColors.rejected : MtColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

/// Self-printing HTML handover receipt, reusing the ledger printer plumbing.
String _buildReceiptHtml(
  ProviderCashLedgerEntry entry,
  CashSettlementResult result,
) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final generated = _handoverDateFmt.format(DateTime.now());
  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Taafi — Cash Handover Receipt</title>
<style>
  * { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; }
  body { color: #0F172A; margin: 32px; max-width: 480px; }
  .head { border-bottom: 2px solid #EA580C; padding-bottom: 12px; margin-bottom: 20px; }
  h1 { font-size: 20px; margin: 0; }
  .muted { color: #64748B; font-size: 12px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; margin-top: 8px; }
  td { padding: 8px 4px; border-bottom: 1px solid #F1F5F9; }
  td.k { color: #64748B; text-transform: uppercase; font-size: 11px; letter-spacing: .5px; }
  td.v { text-align: right; font-weight: 600; }
  @media print { body { margin: 0; } }
</style></head>
<body>
  <div class="head"><h1>Taafi — Cash Handover Receipt</h1>
    <div class="muted">Generated $generated</div></div>
  <table>
    <tr><td class="k">Receipt</td><td class="v">${esc(result.receiptId)}</td></tr>
    <tr><td class="k">Provider</td><td class="v">${esc(entry.name)} (${esc(entry.role)})</td></tr>
    <tr><td class="k">Contact</td><td class="v">${esc(entry.phone)}</td></tr>
    <tr><td class="k">Expected balance</td><td class="v">৳${_moneyFmt.format(result.expectedAmount.round())}</td></tr>
    <tr><td class="k">Cash received</td><td class="v">৳${_moneyFmt.format(result.amountCollected.round())}</td></tr>
    <tr><td class="k">Discrepancy</td><td class="v">৳${_moneyFmt.format(result.discrepancy.round())}</td></tr>
    <tr><td class="k">Ledger after</td><td class="v">৳0</td></tr>
  </table>
  <script>window.addEventListener('load', function(){ setTimeout(function(){ window.focus(); window.print(); }, 150); });</script>
</body></html>''';
}
