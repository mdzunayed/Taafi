import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/patient_history_item.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';

final _historyMoneyFmt = NumberFormat('#,###', 'en_US');
String _historyMoney(num n) => '৳${_historyMoneyFmt.format(n.round())}';

/// Past terminal-status requests for the signed-in patient. Backed by
/// `GET /patient/requests/history?account_id=`. Uses
/// [FutureProvider.autoDispose] (not an AsyncNotifier) because the
/// History screen has no in-screen mutations — pull-to-refresh just
/// invalidates the provider.
final patientHistoryProvider =
    FutureProvider.autoDispose<List<PatientHistoryItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).getPatientHistory(user.id);
});

class PatientHistoryScreen extends ConsumerWidget {
  const PatientHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientHistoryProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MtColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Past requests', style: MtTextStyles.h3),
      ),
      body: RefreshIndicator(
        color: MtColors.brand,
        onRefresh: () async {
          // ignore: unused_result
          ref.invalidate(patientHistoryProvider);
          await ref.read(patientHistoryProvider.future);
        },
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: MtColors.brand),
          ),
          error: (e, _) => _HistoryError(
            message: e.toString(),
            onRetry: () => ref.invalidate(patientHistoryProvider),
          ),
          data: (items) => items.isEmpty
              ? const _EmptyHistory()
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _HistoryCard(item: items[i]),
                ),
        ),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _HistoryError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: MtColors.ink3),
            const SizedBox(height: 12),
            Text('Could not load history',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      children: [
        const Icon(Icons.inbox_outlined,
            size: 48, color: MtColors.ink3),
        const SizedBox(height: 12),
        Text('No past requests yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 4),
        Text(
          'Completed or cancelled visits will appear here so you can track your service history.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final PatientHistoryItem item;
  const _HistoryCard({required this.item});

  String get _statusLabel {
    switch (item.status) {
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      case 'rejected':
        return 'REJECTED';
      default:
        return item.status.toUpperCase();
    }
  }

  (Color, Color) get _statusColors {
    switch (item.status) {
      case 'completed':
        return (MtColors.completed, MtColors.completedBg);
      case 'cancelled':
        return (MtColors.ink3, MtColors.bg);
      case 'rejected':
        return (MtColors.rejected, const Color(0xFFFEE2E2));
      default:
        return (MtColors.ink3, MtColors.bg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _statusColors;
    final doctorLabel = item.doctorName ?? 'Unassigned';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.serviceName.isEmpty ? 'Care request' : item.serviceName,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel,
                  style: MtTextStyles.labelSm
                      .copyWith(color: fg, fontSize: 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InitialsAvatar(
                name: doctorLabel.replaceFirst('Dr. ', ''),
                size: 32,
                backgroundColor: MtColors.brandSoft,
                textColor: MtColors.brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorLabel,
                      style: MtTextStyles.labelMd
                          .copyWith(color: MtColors.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('MMM d, y').format(item.createdAt),
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              Text(
                _historyMoney(item.effectivePrice),
                style: MtTextStyles.labelLg.copyWith(color: MtColors.brand),
              ),
            ],
          ),
          if (item.locationText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 14, color: MtColors.ink3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.locationText,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink2),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
