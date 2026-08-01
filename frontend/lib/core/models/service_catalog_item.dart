import 'package:equatable/equatable.dart';

import 'provider_type.dart';

enum ServiceCatalogStatus { active, inactive }

class ServiceCatalogItem extends Equatable {
  final String id;
  final String title;
  final double price;
  final String description;
  final String category;

  /// Who attends this service — the role every booking made from it inherits,
  /// and therefore what the patient's tracker calls them ("Nurse On the Way"
  /// vs "Doctor On the Way").
  ///
  /// Null when the service has never been tagged. The API infers a type from
  /// the title/category for its own responses, but the admin console must be
  /// able to see that nothing is actually stored — otherwise an inferred guess
  /// is indistinguishable from a deliberate choice. [providerTypeSource] says
  /// which of the two the current value is.
  final ProviderType? providerType;

  /// `'assigned'` (stored), `'inferred'` (derived from the title/category by
  /// the API) or `'none'`. Server-supplied; read-only.
  final String providerTypeSource;

  final String? duration;
  final String? imageUrl;
  final ServiceCatalogStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServiceCatalogItem({
    required this.id,
    required this.title,
    required this.price,
    this.description = '',
    this.category = '',
    this.providerType,
    this.providerTypeSource = 'none',
    this.duration,
    this.imageUrl,
    this.status = ServiceCatalogStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == ServiceCatalogStatus.active;

  ServiceCatalogItem copyWith({
    String? id,
    String? title,
    double? price,
    String? description,
    String? category,
    ProviderType? providerType,
    String? providerTypeSource,
    String? duration,
    String? imageUrl,
    ServiceCatalogStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceCatalogItem(
      id: id ?? this.id,
      title: title ?? this.title,
      price: price ?? this.price,
      description: description ?? this.description,
      category: category ?? this.category,
      providerType: providerType ?? this.providerType,
      providerTypeSource: providerTypeSource ?? this.providerTypeSource,
      duration: duration ?? this.duration,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Total-function parser: every field is coerced, never cast.
  ///
  /// The catalog is read by every patient on the Home screen, and the rows come
  /// from a deliberately loose Mongoose schema (`category` has no `enum`, and
  /// `normalizeServiceCategory` only runs on the write path in
  /// routes/services.js) — so a migration script, a legacy row, or a hand-rolled
  /// curl can put a number where a String is expected. The previous
  /// implementation used `as String` / `as num?`, which meant ONE malformed
  /// document threw a TypeError that aborted the whole `.map()` and blanked the
  /// section for every user. Nothing here can throw: unparseable values fall
  /// back to a sane default and the row still renders.
  factory ServiceCatalogItem.fromJson(Map<String, dynamic> json) {
    return ServiceCatalogItem(
      id: _str(json['id'] ?? json['_id']),
      title: _str(json['title']),
      price: _price(json['price']),
      description: _str(json['description']),
      category: _str(json['category']),
      providerType: ProviderTypeX.tryFromWire(_nullableStr(json['provider_type'])),
      providerTypeSource: _str(json['provider_type_source'], fallback: 'none'),
      duration: _nullableStr(json['duration']),
      imageUrl: _nullableStr(json['imageUrl'] ?? json['image_url']),
      status: _parseStatus(json['status']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  /// Any scalar → String. Maps/Lists are rejected rather than stringified into
  /// `{a: b}` prose that would land on screen.
  static String _str(dynamic raw, {String fallback = ''}) {
    if (raw == null || raw is Map || raw is Iterable) return fallback;
    final s = raw.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  /// Same coercion, but blank/absent collapses to null so callers can use
  /// `?? ` and null-aware widgets instead of testing for the empty string.
  static String? _nullableStr(dynamic raw) {
    final s = _str(raw);
    return s.isEmpty ? null : s;
  }

  /// Price arrives as a `Number` from Mongo, but seed scripts and multipart
  /// form round-trips have both been observed to store it as a String
  /// (`"1200"`, `"1,200"`, `"৳1200"`). Accept all of them; anything that still
  /// won't parse — or is negative/NaN/Infinity — becomes 0, which the card
  /// renders as a free/"—" price rather than crashing the list.
  static double _price(dynamic raw) {
    double? parsed;
    if (raw is num) {
      parsed = raw.toDouble();
    } else if (raw is String) {
      // Strip grouping separators, currency symbols and whitespace, keeping
      // digits, a decimal point and a leading sign.
      final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
      parsed = double.tryParse(cleaned);
    }
    if (parsed == null || !parsed.isFinite || parsed < 0) return 0;
    return parsed;
  }

  static DateTime _parseDate(dynamic raw) {
    if (raw is DateTime) return raw;
    // Mongo `$date` epoch-millis shape, and plain numeric timestamps.
    if (raw is num) {
      final ms = raw.toInt();
      if (ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final s = _nullableStr(raw);
    if (s != null) {
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  /// Case- and whitespace-insensitive so `"Inactive"` / `" inactive "` are not
  /// silently promoted to active — an admin-disabled service leaking back onto
  /// the patient Home is a product bug, not just a cosmetic one.
  static ServiceCatalogStatus _parseStatus(dynamic raw) {
    final s = _str(raw).toLowerCase();
    if (s == ServiceCatalogStatus.inactive.name) {
      return ServiceCatalogStatus.inactive;
    }
    return ServiceCatalogStatus.active;
  }

  @override
  List<Object?> get props => [
        id,
        title,
        price,
        description,
        category,
        providerType,
        providerTypeSource,
        duration,
        imageUrl,
        status,
        createdAt,
        updatedAt,
      ];
}
