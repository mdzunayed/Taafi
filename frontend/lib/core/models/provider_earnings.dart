import 'package:equatable/equatable.dart';

/// One settled-or-pending payout row in the provider earnings ledger,
/// mapping to a completed patient dispatch ticket (CareRequest).
class ProviderPayoutItem extends Equatable {
  final String id;
  final String patientName;
  final String careType;
  final DateTime? completedAt;
  final num amount;

  /// `true` once `payment.released_at` is stamped server-side; `false`
  /// while the visit is completed but the payout is still processing.
  final bool settled;

  const ProviderPayoutItem({
    required this.id,
    required this.patientName,
    required this.careType,
    required this.completedAt,
    required this.amount,
    required this.settled,
  });

  factory ProviderPayoutItem.fromJson(Map<String, dynamic> json) {
    final rawDate = json['completed_at'];
    return ProviderPayoutItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      patientName: (json['patient_name'] ?? '').toString(),
      careType: (json['care_type'] ?? '').toString(),
      completedAt:
          rawDate == null ? null : DateTime.tryParse(rawDate.toString()),
      amount: (json['amount'] as num?) ?? 0,
      settled: (json['settled'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props =>
      [id, patientName, careType, completedAt, amount, settled];
}

/// Provider earnings ledger returned by `GET /api/provider/earnings` —
/// settled vs pending totals plus the itemized payout history.
class ProviderEarnings extends Equatable {
  final num totalSettled;
  final num totalPending;

  /// Company cash the provider is physically holding from door-step CASH
  /// settlements (credited by the collect-cash flow). Backs the nurse
  /// workspace's "Cash in Hand" ledger card.
  final num cashInHand;
  final String currency;
  final List<ProviderPayoutItem> items;

  const ProviderEarnings({
    this.totalSettled = 0,
    this.totalPending = 0,
    this.cashInHand = 0,
    this.currency = 'BDT',
    this.items = const [],
  });

  static const empty = ProviderEarnings();

  factory ProviderEarnings.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ProviderEarnings(
      totalSettled: (json['total_settled'] as num?) ?? 0,
      totalPending: (json['total_pending'] as num?) ?? 0,
      cashInHand: (json['cash_in_hand'] as num?) ?? 0,
      currency: (json['currency'] ?? 'BDT').toString(),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) =>
                  ProviderPayoutItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props =>
      [totalSettled, totalPending, cashInHand, currency, items];
}
