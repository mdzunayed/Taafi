import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_models.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../auth/auth_provider.dart';
import '../admin_providers.dart';

/// Fixed ৳100 slot-confirmation deposit. Deducted from the final bill so the
/// outstanding balance shown in the drawer mirrors what the patient will owe
/// after the visit completes (pay-after-service). Kept in lockstep with the
/// backend `DEPOSIT_AMOUNT` constant in `routes/admin.js`.
const double _kDepositAmount = 100;

/// Dropdown sentinel for "price the booking but don't dispatch a provider
/// yet". Distinct from a real provider key so we can branch the submit path
/// onto the silent set-price endpoint instead of assign.
const String _assignLaterKey = '__assign_later__';

/// Frontend-normalized statuses (see `normalizeAdminStatus`) from which an
/// admin can still price + assign a team. `deposit_paid_admin_reviewing` is
/// the normal post-deposit triage state; `pending` (legacy `submitted`) and
/// `approved` (legacy `approved`/`assigned`) remain re-priceable /
/// re-assignable, matching the backend `ASSIGNABLE` guard.
const Set<String> _triageableStatuses = {
  'deposit_paid_admin_reviewing',
  'pending',
  'approved',
};

/// Right-aligned 500-wide slide-over showing the full triage view for a
/// single [AdminCareRequest]. Used by both the Review Queue and Overview tabs
/// so the experience stays identical regardless of entry point.
///
/// For bookings still in triage (deposit paid, awaiting review) it exposes an
/// inline billing + assignment console: set the final service fee, watch the
/// remaining balance auto-compute against the ৳100 deposit, pick an on-duty
/// doctor or nurse, and dispatch — all without leaving the drawer. The
/// full-width dual-list match-maker is still one tap away via [onAssignTeam].
///
/// Call via [showTriageSlideOver] — that helper wires up [showModalBottomSheet]
/// with the correct `isScrollControlled` and transparent backdrop so the
/// slide-over animates in from the right edge.
class TriageSlideOver extends ConsumerStatefulWidget {
  final AdminCareRequest request;

  /// Opens the full-screen dual-list Assign Team surface. Kept as a secondary
  /// "advanced" path — the inline console covers the common case.
  final VoidCallback onAssignTeam;

  const TriageSlideOver({
    super.key,
    required this.request,
    required this.onAssignTeam,
  });

  @override
  ConsumerState<TriageSlideOver> createState() => _TriageSlideOverState();
}

class _TriageSlideOverState extends ConsumerState<TriageSlideOver> {
  late final TextEditingController _feeController;

  /// Live parse of the fee field, used to drive the remaining-balance readout
  /// and gate the submit button as the admin types.
  double? _fee;

  /// Selected provider dropdown key: `doctor:<id>`, `nurse:<id>`, or
  /// [_assignLaterKey]. Defaults to assign-later so a price-only save is the
  /// zero-selection outcome.
  String _selectedProviderKey = _assignLaterKey;

  bool _submitting = false;

  AdminCareRequest get request => widget.request;

  bool get _canTriage => _triageableStatuses.contains(request.status);

  /// Whether a ৳100 deposit is actually on file — true for the post-deposit
  /// review state. Legacy `pending`/`approved` rows predate the deposit gate.
  bool get _hasDeposit => request.status == 'deposit_paid_admin_reviewing';

  double get _deposit => _hasDeposit ? _kDepositAmount : 0;

  @override
  void initState() {
    super.initState();
    // Prefill from any fee the admin already saved (`final_price` →
    // adjustedPrice) so it isn't retyped; stays editable for a correction.
    final saved = request.adjustedPrice;
    _fee = (saved != null && saved > 0) ? saved : null;
    _feeController = TextEditingController(
      text: _fee == null ? '' : _trimAmount(_fee!),
    );
  }

  @override
  void dispose() {
    _feeController.dispose();
    super.dispose();
  }

  static String _trimAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double get _remainingDue {
    final fee = _fee ?? 0;
    final due = fee - _deposit;
    return due < 0 ? 0 : due;
  }

  // ── Submit paths ──────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final fee = _fee;
    if (fee == null || fee <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter a service fee greater than ৳0 first.'),
          backgroundColor: MtColors.rejected,
        ),
      );
      return;
    }
    // Mirror the backend guard: fee must at least cover the deposit so the
    // outstanding balance can never go negative.
    if (fee < _deposit) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'The fee must be at least the ৳${_trimAmount(_deposit)} deposit already paid.',
          ),
          backgroundColor: MtColors.rejected,
        ),
      );
      return;
    }

    final assignLater = _selectedProviderKey == _assignLaterKey;

    setState(() => _submitting = true);
    final dio = ref.read(dioClientProvider);
    try {
      if (assignLater) {
        // Silent invoice update — no status change, no patient pay-prompt.
        // The booking stays in review until a team is assigned.
        await dio.adminSetBookingPrice(request.id, finalServiceFee: fee);
      } else {
        final picked = _resolveSelectedProvider();
        await dio.assignTeam(
          request.id,
          picked.role == 'doctor' ? picked.id : null,
          doctorName: picked.role == 'doctor' ? picked.name : null,
          nurseId: picked.role == 'nurse' ? picked.id : null,
          nurseName: picked.role == 'nurse' ? picked.name : null,
          finalPrice: fee,
        );
      }

      // Refresh the admin queues so the row moves out of "review" (assigned)
      // or reflects the corrected fee (price-only).
      ref.invalidate(adminRequestsProvider);
      ref.invalidate(availableDoctorsProvider(request.id));
      ref.invalidate(availableNursesProvider(request.id));

      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            assignLater
                ? 'Fee saved for ${request.id} — booking still in review.'
                : 'Fee set & team assigned for ${request.id}.',
          ),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not submit: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    }
  }

  /// Resolves the currently-selected dropdown key back to the provider's id,
  /// display name, and role by reading the loaded rosters.
  _PickedProvider _resolveSelectedProvider() {
    final parts = _selectedProviderKey.split(':');
    final role = parts.first;
    final id = parts.length > 1 ? parts.sublist(1).join(':') : '';
    if (role == 'doctor') {
      final docs =
          ref.read(availableDoctorsProvider(request.id)).valueOrNull ??
              const <AvailableDoctor>[];
      final match = docs.where((d) => d.id == id);
      final name = match.isNotEmpty ? match.first.name : null;
      return _PickedProvider(role: 'doctor', id: id, name: name);
    }
    final nurses =
        ref.read(availableNursesProvider(request.id)).valueOrNull ??
            const <AvailableNurse>[];
    final match = nurses.where((n) => n.id == id);
    final name = match.isNotEmpty ? match.first.name : null;
    return _PickedProvider(role: 'nurse', id: id, name: name);
  }

  // ── Reject / cancel (unchanged behavior) ────────────────────────────────────

  Future<void> _confirmReject() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject request ${request.id}?', style: MtTextStyles.h3),
        content: Text(
          'The patient will be notified. Any escrowed payment will be refunded within 24 hours.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep request', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: Text('Reject', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(adminRequestsProvider.notifier)
          .bulkUpdateStatus({request.id}, 'rejected');
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Request ${request.id} rejected'),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not reject: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    }
  }

  Future<void> _confirmCancel() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel booking ${request.id}?', style: MtTextStyles.h3),
        content: Text(
          'The booking will be cancelled, any assigned team released, and the '
          'patient notified. This cannot be undone.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep booking', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: Text('Cancel booking', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(adminRequestsProvider.notifier).cancelBooking(request.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Booking ${request.id} cancelled'),
          backgroundColor: MtColors.completed,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not cancel: $e'),
          backgroundColor: MtColors.rejected,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = request.status == 'pending';
    const terminal = {'completed', 'cancelled', 'rejected'};
    final canCancel = !isPending && !terminal.contains(request.status);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 500,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: MtColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Triage request', style: MtTextStyles.h2),
                        Text(request.id,
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3)),
                      ],
                    ),
                  ),
                  _StatusBadge(status: request.status),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PATIENT', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(
                      '${request.patientName} (${request.patientAge}${request.patientGender ?? ''})',
                      style: MtTextStyles.labelLg,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.phone ?? 'No phone provided',
                      style: MtTextStyles.bodyMd,
                    ),
                    const SizedBox(height: 16),

                    if (request.patientHistory != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: MtColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MtColors.line),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.history,
                                color: MtColors.ink3, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Medical history',
                                      style: MtTextStyles.labelMd),
                                  const SizedBox(height: 4),
                                  Text(
                                    request.patientHistory ?? '',
                                    style: MtTextStyles.bodySm,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Text('SERVICE DETAILS', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(request.serviceName, style: MtTextStyles.labelLg),
                    if (request.surgeryDetails != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Surgery: ${request.surgeryDetails}',
                        style:
                            MtTextStyles.bodyMd.copyWith(color: MtColors.brand),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text('Duration: ${request.durationHours} hours',
                        style: MtTextStyles.bodyMd),
                    const SizedBox(height: 4),
                    Text(
                      'Scheduled: ${request.scheduledTime != null ? request.scheduledTime!.toLocal().toString().split('.')[0] : 'ASAP'}',
                      style: MtTextStyles.bodyMd,
                    ),
                    const SizedBox(height: 24),

                    Text('LOCATION', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 8),
                    Text(request.location, style: MtTextStyles.labelLg),
                    const SizedBox(height: 12),
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: MtColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MtColors.line),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.map,
                            size: 48,
                            color: MtColors.ink3.withValues(alpha: 0.5),
                          ),
                          if (request.latitude != null)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${request.latitude?.toStringAsFixed(4)}, ${request.longitude?.toStringAsFixed(4)}',
                                  style: MtTextStyles.labelSm
                                      .copyWith(fontSize: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (request.notes != null && request.notes!.isNotEmpty) ...[
                      Text('NOTES', style: MtTextStyles.sectionLabel),
                      const SizedBox(height: 8),
                      Text(request.notes ?? '', style: MtTextStyles.bodyMd),
                      const SizedBox(height: 24),
                    ],

                    // ── Inline billing + assignment console ────────────────
                    if (_canTriage) _buildTriageConsole(),
                  ],
                ),
              ),
            ),

            // Footer / Actions
            _buildFooter(
              isPending: isPending,
              canCancel: canCancel,
            ),
          ],
        ),
      ),
    );
  }

  // ── Triage console (pricing + assignment) ───────────────────────────────────

  Widget _buildTriageConsole() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: MtColors.line, height: 1),
        const SizedBox(height: 20),
        Text('SET FEE & ASSIGN', style: MtTextStyles.sectionLabel),
        const SizedBox(height: 12),

        // Deposit confirmation chip.
        if (_hasDeposit) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MtColors.completedBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: MtColors.completed.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded,
                    size: 16, color: MtColors.completed),
                const SizedBox(width: 6),
                Text(
                  '৳${_trimAmount(_kDepositAmount)} Deposit Confirmed',
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.completed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Total service fee.
        Text('Total Service Fee', style: MtTextStyles.labelMd),
        const SizedBox(height: 6),
        TextField(
          controller: _feeController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            TextInputFormatter.withFunction((oldV, newV) =>
                newV.text.split('.').length > 2 ? oldV : newV),
          ],
          onChanged: (raw) {
            final parsed = double.tryParse(raw.trim());
            setState(() {
              _fee = (parsed == null || parsed <= 0) ? null : parsed;
            });
          },
          decoration: InputDecoration(
            hintText: 'e.g. 1500',
            prefixText: '৳ ',
            isDense: true,
            filled: true,
            fillColor: MtColors.surface,
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
              borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Auto-computed invoice breakdown.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MtColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MtColors.line),
          ),
          child: Column(
            children: [
              _InvoiceLine(
                label: 'Total service fee',
                value: '৳${_trimAmount(_fee ?? 0)}',
              ),
              if (_hasDeposit) ...[
                const SizedBox(height: 6),
                _InvoiceLine(
                  label: 'Deposit paid',
                  value: '− ৳${_trimAmount(_deposit)}',
                  valueColor: MtColors.completed,
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: MtColors.line, height: 1),
              ),
              _InvoiceLine(
                label: 'Remaining due (after service)',
                value: '৳${_trimAmount(_remainingDue)}',
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Provider assignment selector.
        Text('Assign On-Duty Provider', style: MtTextStyles.labelMd),
        const SizedBox(height: 6),
        _ProviderDropdown(
          requestId: request.id,
          value: _selectedProviderKey,
          onChanged: _submitting
              ? null
              : (key) => setState(
                  () => _selectedProviderKey = key ?? _assignLaterKey),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _submitting ? null : widget.onAssignTeam,
            style: TextButton.styleFrom(
              foregroundColor: MtColors.brand,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.groups_2_outlined, size: 18),
            label: Text('Open full match-maker (doctor + nurse)',
                style: MtTextStyles.labelMd),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Footer action bar ───────────────────────────────────────────────────────

  Widget _buildFooter({required bool isPending, required bool canCancel}) {
    final assignLater = _selectedProviderKey == _assignLaterKey;
    final feeReady = _fee != null && _fee! > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary triage action — only when the booking is still priceable.
          if (_canTriage) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_submitting || !feeReady) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MtColors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        assignLater
                            ? Icons.save_outlined
                            : Icons.send_rounded,
                        size: 18,
                      ),
                label: Text(
                  _submitting
                      ? 'Processing…'
                      : assignLater
                          ? 'Save Fee (Assign Later)'
                          : 'Confirm Fee & Assign Doctor',
                  style: MtTextStyles.labelLg.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Secondary row: Close + destructive actions.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Close'),
                ),
              ),
              if (isPending) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : _confirmReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MtColors.rejected,
                      side: const BorderSide(color: MtColors.rejected),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
              if (canCancel) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : _confirmCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MtColors.rejected,
                      side: const BorderSide(color: MtColors.rejected),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel booking'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One `label ........ value` row inside the auto-computed invoice card.
class _InvoiceLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  const _InvoiceLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasize
        ? MtTextStyles.labelMd.copyWith(fontWeight: FontWeight.w700)
        : MtTextStyles.bodyMd.copyWith(color: MtColors.ink2);
    final valueStyle = (emphasize
            ? MtTextStyles.labelLg
            : MtTextStyles.labelMd)
        .copyWith(
      color: valueColor ?? MtColors.ink,
      fontWeight: FontWeight.w700,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: labelStyle)),
        const SizedBox(width: 12),
        Text(value, style: valueStyle),
      ],
    );
  }
}

/// Dropdown that lists on-duty doctors + nurses (via the existing
/// `availableDoctorsProvider` / `availableNursesProvider`, backed by
/// `GET /admin/requests/:id/doctors|nurses`) plus an "Assign later" option.
class _ProviderDropdown extends ConsumerWidget {
  final String requestId;
  final String value;
  final ValueChanged<String?>? onChanged;

  const _ProviderDropdown({
    required this.requestId,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorsAsync = ref.watch(availableDoctorsProvider(requestId));
    final nursesAsync = ref.watch(availableNursesProvider(requestId));
    final loading = doctorsAsync.isLoading || nursesAsync.isLoading;

    final doctors = doctorsAsync.valueOrNull ?? const <AvailableDoctor>[];
    final nurses = nursesAsync.valueOrNull ?? const <AvailableNurse>[];

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: _assignLaterKey,
        child: Text(
          'Assign later (price only)',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
      ),
      for (final d in doctors)
        DropdownMenuItem(
          value: 'doctor:${d.id}',
          child: Text(
            'Dr. ${_stripDr(d.name)}'
            '${d.specialization.isNotEmpty ? ' · ${d.specialization}' : ''}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      for (final n in nurses)
        DropdownMenuItem(
          value: 'nurse:${n.id}',
          child: Text(
            'Nurse ${_stripDr(n.name)}'
            '${n.nursingSpecialty.isNotEmpty ? ' · ${n.nursingSpecialty}' : ''}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    // Guard against a stale selection (roster refetched, provider went
    // offline) so the dropdown never asserts on a missing value.
    final safeValue =
        items.any((i) => i.value == value) ? value : _assignLaterKey;

    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: MtColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }

  static String _stripDr(String name) =>
      name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '').trim();
}

/// Convenience helper so callers don't have to remember the right
/// `showModalBottomSheet` config to make the slide-over render as a
/// right-edge drawer.
Future<void> showTriageSlideOver(
  BuildContext context, {
  required AdminCareRequest request,
  required VoidCallback onAssignTeam,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TriageSlideOver(
      request: request,
      onAssignTeam: onAssignTeam,
    ),
  );
}

/// Resolved provider selection extracted from the dropdown key at submit time.
class _PickedProvider {
  final String role; // 'doctor' | 'nurse'
  final String id;
  final String? name;

  const _PickedProvider({required this.role, required this.id, this.name});
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color sColor;
    Color sBgColor;
    final label = status.replaceAll('_', ' ').toUpperCase();
    switch (status) {
      case 'pending':
        sColor = MtColors.brand;
        sBgColor = MtColors.brandSoft;
        break;
      case 'deposit_paid_admin_reviewing':
        sColor = const Color(0xFFB45309);
        sBgColor = const Color(0xFFFEF3C7);
        break;
      case 'approved':
        sColor = const Color(0xFF059669);
        sBgColor = const Color(0xFFDCF3E7);
        break;
      case 'rejected':
        sColor = MtColors.rejected;
        sBgColor = const Color(0xFFFEE2E2);
        break;
      case 'cancelled':
        sColor = MtColors.rejected;
        sBgColor = const Color(0xFFFEE2E2);
        break;
      default:
        sColor = MtColors.ink3;
        sBgColor = MtColors.line;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: sBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: sColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: MtTextStyles.labelSm
                .copyWith(color: sColor, fontSize: 9, height: 1.1),
          ),
        ],
      ),
    );
  }
}
