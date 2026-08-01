import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_providers.dart';
import '../../util/ledger_printer.dart';
import 'admin_table_chrome.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';
final _rangeFmt = DateFormat('MMM d, y');

class BillingTab extends ConsumerWidget {
  const BillingTab({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final current = ref.read(billingRangeProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: current,
      helpText: 'Filter ledger by date range',
    );
    if (picked != null) {
      ref.read(billingRangeProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminBillingProvider);
    final range = ref.watch(billingRangeProvider);
    return AdminListScaffold(
      title: 'Billing',
      subtitle: 'Completed care requests and their final settlement price',
      onRefresh: () async {
        ref.invalidate(adminBillingProvider);
        await ref.read(adminBillingProvider.future);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date-range + print toolbar ───────────────────────────────
          Row(
            children: [
              _DateRangeButton(
                range: range,
                onTap: () => _pickRange(context, ref),
                onClear: range == null
                    ? null
                    : () => ref.read(billingRangeProvider.notifier).state =
                        null,
              ),
              const Spacer(),
              if (ledgerPrintingSupported)
                _PrintButton(
                  onTap: () {
                    final rows = async.valueOrNull ?? const [];
                    if (rows.isEmpty) return;
                    printLedgerDocument(_buildLedgerHtml(rows, range));
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MtErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(adminBillingProvider),
            ),
            data: (rows) => rows.isEmpty
                ? const AdminEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No completed visits in range',
                    subtitle:
                        'Adjust the date range, or wait for doctors to complete visits.',
                  )
                : _BillingView(rows: rows),
          ),
        ],
      ),
    );
  }
}

/// Builds a clean, self-contained, self-printing HTML invoice/ledger summary
/// from the visible rows. The embedded script fires `window.print()` on load
/// (see [printLedgerDocument]).
String _buildLedgerHtml(List<AdminCareRequest> rows, DateTimeRange? range) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final total = rows.fold<double>(
      0, (sum, r) => sum + (r.adjustedPrice ?? r.patientOffer));
  final period = range == null
      ? 'All time'
      : '${_rangeFmt.format(range.start)} — ${_rangeFmt.format(range.end)}';
  final generated = DateFormat('MMM d, y · h:mm a').format(DateTime.now());

  final body = StringBuffer();
  for (final r in rows) {
    body.write(
      '<tr>'
      '<td>${esc(r.id)}</td>'
      '<td>${esc(r.patientName)}</td>'
      '<td>${esc(r.serviceName)}</td>'
      '<td>${esc(r.assignedDoctorName ?? '—')}</td>'
      '<td class="num">৳${_moneyFmt.format((r.adjustedPrice ?? r.patientOffer).round())}</td>'
      '<td>${esc(_rangeFmt.format(r.createdAt))}</td>'
      '</tr>',
    );
  }

  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Taafi — Ledger Summary</title>
<style>
  * { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; }
  body { color: #0F172A; margin: 32px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start;
          border-bottom: 2px solid #EA580C; padding-bottom: 12px; margin-bottom: 20px; }
  h1 { font-size: 20px; margin: 0; }
  .muted { color: #64748B; font-size: 12px; }
  .totals { display: flex; gap: 24px; margin: 16px 0 24px; }
  .totals div { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px;
                padding: 12px 16px; }
  .totals .v { font-size: 18px; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th { text-align: left; color: #64748B; text-transform: uppercase; font-size: 10px;
       letter-spacing: .5px; border-bottom: 1px solid #E2E8F0; padding: 8px 6px; }
  td { padding: 8px 6px; border-bottom: 1px solid #F1F5F9; }
  td.num, th.num { text-align: right; }
  @media print { body { margin: 0; } }
</style></head>
<body>
  <div class="head">
    <div><h1>Taafi — Ledger Summary</h1>
      <div class="muted">Period: $period</div></div>
    <div class="muted">Generated $generated</div>
  </div>
  <div class="totals">
    <div><div class="muted">COMPLETED VISITS</div><div class="v">${rows.length}</div></div>
    <div><div class="muted">TOTAL SETTLED</div><div class="v">৳${_moneyFmt.format(total.round())}</div></div>
    <div><div class="muted">AVERAGE TICKET</div><div class="v">৳${_moneyFmt.format(rows.isEmpty ? 0 : (total / rows.length).round())}</div></div>
  </div>
  <table>
    <thead><tr><th>Request</th><th>Patient</th><th>Service</th><th>Doctor</th>
      <th class="num">Final price</th><th>Completed</th></tr></thead>
    <tbody>$body</tbody>
  </table>
  <script>window.addEventListener('load', function(){ setTimeout(function(){ window.focus(); window.print(); }, 150); });</script>
</body></html>''';
}

class _DateRangeButton extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DateRangeButton({
    required this.range,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = range == null
        ? 'Date to Date Filter'
        : '${_rangeFmt.format(range!.start)} → ${_rangeFmt.format(range!.end)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(label, style: MtTextStyles.labelMd),
          style: OutlinedButton.styleFrom(
            foregroundColor: range == null ? MtColors.ink : MtColors.brand,
            side: BorderSide(
                color: range == null ? MtColors.line : MtColors.brand),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Clear range',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18, color: MtColors.ink3),
          ),
        ],
      ],
    );
  }
}

class _PrintButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PrintButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.print_outlined, size: 18),
      label: Text('Print Ledger Summary',
          style: MtTextStyles.labelLg.copyWith(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: MtColors.ink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _BillingView extends StatelessWidget {
  final List<AdminCareRequest> rows;
  const _BillingView({required this.rows});

  @override
  Widget build(BuildContext context) {
    // Quick totals strip across the top — admins read these before
    // scrolling the table to see the period's settlement at a glance.
    final total = rows.fold<double>(
      0,
      (sum, r) => sum + (r.adjustedPrice ?? r.patientOffer),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(label: 'Completed visits', value: rows.length.toString())),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(label: 'Total settled', value: _money(total))),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Average ticket',
                value: rows.isEmpty
                    ? _money(0)
                    : _money(total / rows.length),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
              dataRowMinHeight: 56,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('REQUEST')),
                DataColumn(label: Text('PATIENT')),
                DataColumn(label: Text('SERVICE')),
                DataColumn(label: Text('DOCTOR')),
                DataColumn(label: Text('FINAL PRICE'), numeric: true),
                DataColumn(label: Text('COMPLETED')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(Text(r.id,
                        style: MtTextStyles.labelMd
                            .copyWith(color: MtColors.ink))),
                    DataCell(Text(r.patientName,
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.ink2))),
                    DataCell(Text(r.serviceName,
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.ink2))),
                    DataCell(Text(r.assignedDoctorName ?? '—',
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.ink2))),
                    DataCell(Text(
                        _money(r.adjustedPrice ?? r.patientOffer),
                        style: MtTextStyles.labelMd
                            .copyWith(color: MtColors.brand))),
                    DataCell(Text(adminTableDate.format(r.createdAt),
                        style: MtTextStyles.bodyMd
                            .copyWith(color: MtColors.ink2))),
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
  const _SummaryCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: MtTextStyles.h1
                  .copyWith(color: MtColors.ink, fontSize: 24)),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.8,
              )),
        ],
      ),
    );
  }
}
