import 'package:equatable/equatable.dart';

/// Provider wallet models, mirroring the backend ledger
/// (`models/Wallet.js`, `models/WalletTransaction.js`, `models/PayoutRequest.js`).
///
/// Balances are `num` and always BDT — the server rounds every amount before
/// it goes on the wire, so the client never does currency arithmetic beyond
/// formatting.

// ── Wallet balances ─────────────────────────────────────────────────────────

/// The four balances behind the Wallet page's overview cards.
class ProviderWallet extends Equatable {
  /// Funds the provider can withdraw right now. Can legitimately be NEGATIVE:
  /// a cash visit debits the platform's commission from here, and a provider
  /// who has only ever worked cash visits has no digital credit to absorb it.
  final num digitalBalance;

  /// Company cash the provider is physically carrying from door-step
  /// collections. Not withdrawable — it's already in their pocket.
  final num cashInHand;

  /// Lifetime post-commission earnings. Monotonic; a payout never reduces it.
  final num totalEarned;

  /// Lifetime total of approved payouts.
  final num totalWithdrawn;

  /// True while `cashInHand` sits above the platform's ceiling. Blocks
  /// withdrawals until an admin records a cash handover.
  final bool isPayoutLocked;

  final String currency;

  const ProviderWallet({
    this.digitalBalance = 0,
    this.cashInHand = 0,
    this.totalEarned = 0,
    this.totalWithdrawn = 0,
    this.isPayoutLocked = false,
    this.currency = 'BDT',
  });

  static const empty = ProviderWallet();

  factory ProviderWallet.fromJson(Map<String, dynamic> json) {
    return ProviderWallet(
      digitalBalance: (json['digitalBalance'] as num?) ?? 0,
      cashInHand: (json['cashInHand'] as num?) ?? 0,
      totalEarned: (json['totalEarned'] as num?) ?? 0,
      totalWithdrawn: (json['totalWithdrawn'] as num?) ?? 0,
      isPayoutLocked: (json['isPayoutLocked'] as bool?) ?? false,
      currency: (json['currency'] ?? 'BDT').toString(),
    );
  }

  @override
  List<Object?> get props => [
        digitalBalance,
        cashInHand,
        totalEarned,
        totalWithdrawn,
        isPayoutLocked,
        currency,
      ];
}

/// Platform-configured thresholds the Wallet page reads rather than
/// re-deriving. Sourced from the admin Settings singleton.
class WalletLimits extends Equatable {
  final num cashInHandLimit;
  final num minWithdrawal;
  final num commissionPercent;
  final bool isOverCashLimit;

  const WalletLimits({
    this.cashInHandLimit = 5000,
    this.minWithdrawal = 100,
    this.commissionPercent = 20,
    this.isOverCashLimit = false,
  });

  static const empty = WalletLimits();

  factory WalletLimits.fromJson(Map<String, dynamic> json) {
    return WalletLimits(
      cashInHandLimit: (json['cashInHandLimit'] as num?) ?? 5000,
      minWithdrawal: (json['minWithdrawal'] as num?) ?? 100,
      commissionPercent: (json['commissionPercent'] as num?) ?? 20,
      isOverCashLimit: (json['isOverCashLimit'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props =>
      [cashInHandLimit, minWithdrawal, commissionPercent, isOverCashLimit];
}

/// The provider's saved payout destination, used to prefill the withdrawal
/// sheet. `accountNumber` arrives already masked from the server.
class SavedPayoutDetails extends Equatable {
  final String? method;
  final String accountNumber;
  final String accountNumberLast4;
  final String accountName;
  final String bankName;
  final String branch;

  const SavedPayoutDetails({
    this.method,
    this.accountNumber = '',
    this.accountNumberLast4 = '',
    this.accountName = '',
    this.bankName = '',
    this.branch = '',
  });

  static const empty = SavedPayoutDetails();

  bool get hasDestination => accountNumberLast4.isNotEmpty;

  factory SavedPayoutDetails.fromJson(Map<String, dynamic> json) {
    return SavedPayoutDetails(
      method: json['method']?.toString(),
      accountNumber: (json['accountNumber'] ?? '').toString(),
      accountNumberLast4: (json['accountNumberLast4'] ?? '').toString(),
      accountName: (json['accountName'] ?? '').toString(),
      bankName: (json['bankName'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
        method,
        accountNumber,
        accountNumberLast4,
        accountName,
        bankName,
        branch,
      ];
}

// ── Ledger transactions ─────────────────────────────────────────────────────

/// One row of the append-only wallet ledger. `direction` drives the green
/// `+` / red `−` badge; `ledger` distinguishes a cash movement from a
/// withdrawable-funds movement.
class WalletTransaction extends Equatable {
  final String id;

  /// One of VISIT_EARNING, CASH_COLLECTION, COMMISSION_DEBIT, PAYOUT_HOLD,
  /// PAYOUT_PAID, PAYOUT_REVERSAL, CASH_CLEARANCE.
  final String type;

  /// CREDIT | DEBIT | NONE.
  final String direction;

  /// digital | cash | none.
  final String ledger;

  /// Always positive — `direction` carries the sign.
  final num amount;
  final num? balanceAfter;
  final String bookingId;
  final String patientName;
  final String careType;
  final String description;
  final String referenceId;
  final DateTime? createdAt;

  /// Commission arithmetic frozen at settlement, for the breakdown line.
  final num grossAmount;
  final num commissionPercent;
  final num platformFee;
  final num providerNet;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.direction,
    required this.ledger,
    required this.amount,
    this.balanceAfter,
    this.bookingId = '',
    this.patientName = '',
    this.careType = '',
    this.description = '',
    this.referenceId = '',
    this.createdAt,
    this.grossAmount = 0,
    this.commissionPercent = 0,
    this.platformFee = 0,
    this.providerNet = 0,
  });

  bool get isCredit => direction == 'CREDIT';
  bool get isDebit => direction == 'DEBIT';
  bool get isCashLedger => ledger == 'cash';

  /// True when this row carries a real commission split worth rendering.
  bool get hasBreakdown => grossAmount > 0 && commissionPercent > 0;

  /// Short booking reference for the history card ("#a1b2c3").
  String get shortBookingRef =>
      bookingId.length >= 6 ? '#${bookingId.substring(bookingId.length - 6)}' : '';

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final b = (json['breakdown'] is Map)
        ? Map<String, dynamic>.from(json['breakdown'] as Map)
        : const <String, dynamic>{};
    return WalletTransaction(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      direction: (json['direction'] ?? 'NONE').toString(),
      ledger: (json['ledger'] ?? 'digital').toString(),
      amount: (json['amount'] as num?) ?? 0,
      balanceAfter: json['balanceAfter'] as num?,
      bookingId: (json['bookingId'] ?? '').toString(),
      patientName: (json['patientName'] ?? '').toString(),
      careType: (json['careType'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      referenceId: (json['referenceId'] ?? '').toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      grossAmount: (b['grossAmount'] as num?) ?? 0,
      commissionPercent: (b['commissionPercent'] as num?) ?? 0,
      platformFee: (b['platformFee'] as num?) ?? 0,
      providerNet: (b['providerNet'] as num?) ?? 0,
    );
  }

  /// Human label for the history card title.
  String get typeLabel {
    switch (type) {
      case 'VISIT_EARNING':
        return 'Visit earnings';
      case 'CASH_COLLECTION':
        return 'Cash collected';
      case 'COMMISSION_DEBIT':
        return 'Platform commission';
      case 'PAYOUT_HOLD':
        return 'Withdrawal requested';
      case 'PAYOUT_PAID':
        return 'Withdrawal paid';
      case 'PAYOUT_REVERSAL':
        return 'Withdrawal refunded';
      case 'CASH_CLEARANCE':
        return 'Cash handed over';
      default:
        return type;
    }
  }

  @override
  List<Object?> get props => [id, type, direction, ledger, amount, createdAt];
}

// ── Payout requests ─────────────────────────────────────────────────────────

/// A withdrawal request. Shared by the provider's own history and the admin
/// approval queue — the admin list additionally carries the provider identity
/// fields, which are empty strings on the provider's own rows.
class PayoutRequestModel extends Equatable {
  final String id;
  final String providerAccountId;
  final String providerName;
  final String providerRole;
  final String providerPhone;
  final num amount;

  /// bKash | Nagad | Bank.
  final String method;
  final String accountNumber;
  final String accountName;
  final String bankName;
  final String branch;

  /// PENDING | APPROVED | REJECTED.
  final String status;
  final String referenceId;
  final String rejectionReason;
  final DateTime? requestedAt;
  final DateTime? processedAt;

  const PayoutRequestModel({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    this.providerAccountId = '',
    this.providerName = '',
    this.providerRole = '',
    this.providerPhone = '',
    this.accountNumber = '',
    this.accountName = '',
    this.bankName = '',
    this.branch = '',
    this.referenceId = '',
    this.rejectionReason = '',
    this.requestedAt,
    this.processedAt,
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
  bool get isNurse => providerRole == 'nurse';

  /// Destination line for the admin table ("bKash · 01711111111", or the
  /// bank name + branch for a bank transfer).
  String get destinationLabel {
    if (method == 'Bank') {
      final parts = [
        if (bankName.isNotEmpty) bankName,
        if (branch.isNotEmpty) branch,
        if (accountNumber.isNotEmpty) accountNumber,
      ];
      return parts.isEmpty ? 'Bank transfer' : parts.join(' · ');
    }
    return accountNumber.isEmpty ? method : '$method · $accountNumber';
  }

  factory PayoutRequestModel.fromJson(Map<String, dynamic> json) {
    final d = (json['accountDetails'] is Map)
        ? Map<String, dynamic>.from(json['accountDetails'] as Map)
        : const <String, dynamic>{};
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return PayoutRequestModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      providerAccountId: (json['providerAccountId'] ?? '').toString(),
      providerName: (json['providerName'] ?? '').toString(),
      providerRole: (json['providerRole'] ?? '').toString(),
      providerPhone: (json['providerPhone'] ?? '').toString(),
      amount: (json['amount'] as num?) ?? 0,
      method: (json['method'] ?? '').toString(),
      accountNumber: (d['accountNumber'] ?? '').toString(),
      accountName: (d['accountName'] ?? '').toString(),
      bankName: (d['bankName'] ?? '').toString(),
      branch: (d['branch'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      referenceId: (json['referenceId'] ?? '').toString(),
      rejectionReason: (json['rejectionReason'] ?? '').toString(),
      requestedAt: parse(json['requestedAt']),
      processedAt: parse(json['processedAt']),
    );
  }

  @override
  List<Object?> get props =>
      [id, amount, method, status, referenceId, rejectionReason, processedAt];
}

// ── Aggregate page payloads ─────────────────────────────────────────────────

/// Everything `GET /api/provider/wallet` returns — one round trip backs the
/// whole overview section of the Wallet page.
class ProviderWalletSnapshot extends Equatable {
  final ProviderWallet wallet;
  final WalletLimits limits;
  final SavedPayoutDetails payoutDetails;

  /// Server-authored explanation of why withdrawals are blocked. Empty when
  /// they aren't — the UI renders it verbatim rather than re-deriving the rule.
  final String lockReason;
  final PayoutRequestModel? pendingRequest;

  const ProviderWalletSnapshot({
    this.wallet = ProviderWallet.empty,
    this.limits = WalletLimits.empty,
    this.payoutDetails = SavedPayoutDetails.empty,
    this.lockReason = '',
    this.pendingRequest,
  });

  static const empty = ProviderWalletSnapshot();

  /// The withdraw button is live only with a positive balance, no lock, and
  /// nothing already in flight.
  bool get canWithdraw =>
      !wallet.isPayoutLocked &&
      pendingRequest == null &&
      wallet.digitalBalance >= limits.minWithdrawal;

  factory ProviderWalletSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> sub(String key) => (json[key] is Map)
        ? Map<String, dynamic>.from(json[key] as Map)
        : const <String, dynamic>{};
    final pending = json['pendingRequest'];
    return ProviderWalletSnapshot(
      wallet: ProviderWallet.fromJson(sub('wallet')),
      limits: WalletLimits.fromJson(sub('limits')),
      payoutDetails: SavedPayoutDetails.fromJson(sub('payoutDetails')),
      lockReason: (json['lockReason'] ?? '').toString(),
      pendingRequest: pending is Map
          ? PayoutRequestModel.fromJson(Map<String, dynamic>.from(pending))
          : null,
    );
  }

  @override
  List<Object?> get props =>
      [wallet, limits, payoutDetails, lockReason, pendingRequest];
}

/// The admin withdrawal queue: rows plus the pending rollups the console's
/// summary cards and sidebar badge render.
class PayoutQueue extends Equatable {
  final List<PayoutRequestModel> items;
  final int pendingCount;
  final num pendingTotal;

  const PayoutQueue({
    this.items = const [],
    this.pendingCount = 0,
    this.pendingTotal = 0,
  });

  static const empty = PayoutQueue();

  factory PayoutQueue.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PayoutQueue(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((e) =>
                  PayoutRequestModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      pendingTotal: (json['pendingTotal'] as num?) ?? 0,
    );
  }

  @override
  List<Object?> get props => [items, pendingCount, pendingTotal];
}
