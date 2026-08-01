import 'package:equatable/equatable.dart';

/// One doctor/nurse currently holding un-remitted physical cash, as returned
/// by `GET /api/admin/finance/cash-in-hand`. Mirrors the backend row shape
/// (`controllers/adminFinanceController.js`).
class ProviderCashLedgerEntry extends Equatable {
  final String accountId;
  final String name;

  /// `'doctor'` or `'nurse'` (lowercase, matching the DB role enum).
  final String role;
  final String phone;

  /// Outstanding cash (৳) sitting on this provider's ledger.
  final double cashInHand;
  final DateTime? lastCollectionAt;

  const ProviderCashLedgerEntry({
    required this.accountId,
    required this.name,
    required this.role,
    required this.phone,
    required this.cashInHand,
    this.lastCollectionAt,
  });

  bool get isNurse => role == 'nurse';

  factory ProviderCashLedgerEntry.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return ProviderCashLedgerEntry(
      accountId: (json['accountId'] ?? json['account_id'] ?? '').toString(),
      name: (json['name'] ?? 'Unknown provider').toString(),
      role: (json['role'] ?? 'doctor').toString(),
      phone: (json['phone'] ?? '').toString(),
      cashInHand:
          (json['cashInHand'] ?? json['cash_in_hand'] ?? 0).toDouble(),
      lastCollectionAt:
          parseDate(json['lastCollectionAt'] ?? json['last_collection_at']),
    );
  }

  @override
  List<Object?> get props =>
      [accountId, name, role, phone, cashInHand, lastCollectionAt];
}

/// The full Cash Clearance summary: the outstanding-provider rows plus the
/// three field-wide rollups the terminal's summary cards render.
class CashInHandSummary extends Equatable {
  final List<ProviderCashLedgerEntry> providers;
  final double totalCashInField;
  final double collectedToday;
  final int outstandingProvidersCount;

  const CashInHandSummary({
    required this.providers,
    required this.totalCashInField,
    required this.collectedToday,
    required this.outstandingProvidersCount,
  });

  static const empty = CashInHandSummary(
    providers: [],
    totalCashInField: 0,
    collectedToday: 0,
    outstandingProvidersCount: 0,
  );

  factory CashInHandSummary.fromJson(Map<String, dynamic> json) {
    final rawList = json['providers'];
    final providers = <ProviderCashLedgerEntry>[];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map) {
          providers.add(
            ProviderCashLedgerEntry.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return CashInHandSummary(
      providers: providers,
      totalCashInField: (json['totalCashInField'] ?? 0).toDouble(),
      collectedToday: (json['collectedToday'] ?? 0).toDouble(),
      outstandingProvidersCount:
          (json['outstandingProvidersCount'] ?? providers.length) as int,
    );
  }

  @override
  List<Object?> get props => [
        providers,
        totalCashInField,
        collectedToday,
        outstandingProvidersCount,
      ];
}

/// Result of a settle-provider-cash call — carries the generated receipt id
/// so the terminal can show/print a handover receipt.
class CashSettlementResult {
  final String receiptId;
  final String providerId;
  final double amountCollected;
  final double expectedAmount;
  final double discrepancy;

  const CashSettlementResult({
    required this.receiptId,
    required this.providerId,
    required this.amountCollected,
    required this.expectedAmount,
    required this.discrepancy,
  });

  factory CashSettlementResult.fromJson(Map<String, dynamic> json) {
    final log = (json['log'] is Map)
        ? Map<String, dynamic>.from(json['log'] as Map)
        : const <String, dynamic>{};
    final provider = (json['provider'] is Map)
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : const <String, dynamic>{};
    return CashSettlementResult(
      receiptId: (json['receiptId'] ?? log['receipt_id'] ?? '').toString(),
      providerId:
          (provider['accountId'] ?? log['provider_account_id'] ?? '').toString(),
      amountCollected: (log['amount_collected'] ?? 0).toDouble(),
      expectedAmount: (log['expected_amount'] ?? 0).toDouble(),
      discrepancy: (log['discrepancy'] ?? 0).toDouble(),
    );
  }
}
