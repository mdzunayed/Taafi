import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/hex_color.dart';

/// Marker used by [PromoBanner.copyWith] to distinguish "leave unchanged"
/// from "explicitly set to null" on nullable target fields.
const _sentinel = Object();

/// What happens when the patient taps a banner's CTA button. Mirrors the
/// backend `PromoBanner.actionType` enum exactly (see `PromoBanner.js`).
enum BannerActionType {
  /// Open a specific catalog service (`targetServiceId`).
  service,

  /// Open the catalog filtered to a category (`targetCategoryId`).
  category,

  /// Launch an external browser tab (`targetUrl`).
  externalUrl,

  /// Jump into the booking flow with `promoCode` pre-applied.
  promoCode,

  /// Display-only — the button renders but does nothing on tap.
  none,
}

extension BannerActionTypeX on BannerActionType {
  /// The exact wire value the backend enum expects/emits.
  String get wireValue {
    switch (this) {
      case BannerActionType.service:
        return 'SERVICE';
      case BannerActionType.category:
        return 'CATEGORY';
      case BannerActionType.externalUrl:
        return 'EXTERNAL_URL';
      case BannerActionType.promoCode:
        return 'PROMO_CODE';
      case BannerActionType.none:
        return 'NONE';
    }
  }

  static BannerActionType fromWire(String? raw) {
    switch (raw) {
      case 'CATEGORY':
        return BannerActionType.category;
      case 'EXTERNAL_URL':
        return BannerActionType.externalUrl;
      case 'PROMO_CODE':
        return BannerActionType.promoCode;
      case 'NONE':
        return BannerActionType.none;
      case 'SERVICE':
      default:
        return BannerActionType.service;
    }
  }
}

/// Lightweight snapshot of the [BannerActionType.service] target, taken from
/// the backend's populated `targetServiceId` (id/title/price/category/
/// imageUrl only — see `Service.js` + the `TARGET_SERVICE_POPULATE` select in
/// `promoBanners.js`). Enough for the patient app to render a service card or
/// prefill the booking flow without a second `/api/services` round trip.
class BannerTargetService extends Equatable {
  final String id;
  final String title;
  final double price;
  final String category;
  final String? imageUrl;

  const BannerTargetService({
    required this.id,
    required this.title,
    required this.price,
    this.category = '',
    this.imageUrl,
  });

  factory BannerTargetService.fromJson(Map<String, dynamic> json) {
    return BannerTargetService(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      category: (json['category'] ?? '') as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, title, price, category, imageUrl];
}

/// A single admin-managed marketing banner shown in the patient Home slider.
///
/// Mirrors the backend `PromoBanner` document (which emits camelCase keys +
/// an `id` via its `toJSON` transform), so [fromJson] reads keys directly.
class PromoBanner extends Equatable {
  final String id;
  final String tagText;
  final String title;
  final String buttonText;
  final String? imageUrl;

  /// HEX stops driving the card gradient, e.g. `['#4C1D95', '#8B5CF6']`.
  final List<String> gradientColors;

  /// Ascending display order in the slider — lower shows first.
  final int priorityOrder;
  final bool isActive;
  final DateTime? createdAt;

  // --- CTA deep-link destination ---------------------------------------
  final BannerActionType actionType;

  /// Raw id of the [BannerActionType.service] target, if any.
  final String? targetServiceId;

  /// Populated snapshot of [targetServiceId] — present whenever the backend
  /// resolved it (see `TARGET_SERVICE_POPULATE` in `promoBanners.js`), null
  /// if the target service was deleted/unset.
  final BannerTargetService? targetService;

  /// Free-text `Service.category` value for [BannerActionType.category].
  final String? targetCategoryId;

  /// Destination for [BannerActionType.externalUrl].
  final String targetUrl;

  /// Code to pre-apply for [BannerActionType.promoCode].
  final String promoCode;

  const PromoBanner({
    required this.id,
    required this.tagText,
    required this.title,
    required this.buttonText,
    this.imageUrl,
    this.gradientColors = const ['#4C1D95', '#8B5CF6'],
    this.priorityOrder = 0,
    this.isActive = true,
    this.createdAt,
    this.actionType = BannerActionType.service,
    this.targetServiceId,
    this.targetService,
    this.targetCategoryId,
    this.targetUrl = '',
    this.promoCode = '',
  });

  /// The gradient stops parsed into [Color]s, ready for a `LinearGradient`.
  /// Always returns at least two colors so a gradient can be built safely.
  List<Color> get gradient {
    final parsed = gradientColors
        .map(hexToColor)
        .whereType<Color>()
        .toList();
    if (parsed.isEmpty) {
      return const [Color(0xFF4C1D95), Color(0xFF8B5CF6)];
    }
    if (parsed.length == 1) return [parsed.first, parsed.first];
    return parsed;
  }

  PromoBanner copyWith({
    String? id,
    String? tagText,
    String? title,
    String? buttonText,
    String? imageUrl,
    List<String>? gradientColors,
    int? priorityOrder,
    bool? isActive,
    DateTime? createdAt,
    BannerActionType? actionType,
    Object? targetServiceId = _sentinel,
    Object? targetService = _sentinel,
    Object? targetCategoryId = _sentinel,
    String? targetUrl,
    String? promoCode,
  }) {
    return PromoBanner(
      id: id ?? this.id,
      tagText: tagText ?? this.tagText,
      title: title ?? this.title,
      buttonText: buttonText ?? this.buttonText,
      imageUrl: imageUrl ?? this.imageUrl,
      gradientColors: gradientColors ?? this.gradientColors,
      priorityOrder: priorityOrder ?? this.priorityOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      actionType: actionType ?? this.actionType,
      // These three go through a sentinel (rather than plain `??`) because
      // switching action type in the admin form must be able to *clear* a
      // previous target back to null, not just leave it untouched.
      targetServiceId: identical(targetServiceId, _sentinel)
          ? this.targetServiceId
          : targetServiceId as String?,
      targetService: identical(targetService, _sentinel)
          ? this.targetService
          : targetService as BannerTargetService?,
      targetCategoryId: identical(targetCategoryId, _sentinel)
          ? this.targetCategoryId
          : targetCategoryId as String?,
      targetUrl: targetUrl ?? this.targetUrl,
      promoCode: promoCode ?? this.promoCode,
    );
  }

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    final rawColors = json['gradientColors'];
    final colors = rawColors is List
        ? rawColors.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];

    // `targetServiceId` arrives populated (a Map) when the backend resolved
    // it, a bare id string when it's unpopulated/null-ish, or absent on
    // banners created before this field shipped.
    final rawTarget = json['targetServiceId'];
    String? targetServiceId;
    BannerTargetService? targetService;
    if (rawTarget is Map) {
      targetService =
          BannerTargetService.fromJson(Map<String, dynamic>.from(rawTarget));
      targetServiceId = targetService.id;
    } else if (rawTarget is String && rawTarget.isNotEmpty) {
      targetServiceId = rawTarget;
    }

    return PromoBanner(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      tagText: (json['tagText'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      buttonText: (json['buttonText'] ?? '') as String,
      imageUrl: json['imageUrl'] as String?,
      gradientColors:
          colors.isNotEmpty ? colors : const ['#4C1D95', '#8B5CF6'],
      priorityOrder: (json['priorityOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _parseDate(json['createdAt']),
      actionType: BannerActionTypeX.fromWire(json['actionType'] as String?),
      targetServiceId: targetServiceId,
      targetService: targetService,
      targetCategoryId: json['targetCategoryId'] as String?,
      targetUrl: (json['targetUrl'] ?? '') as String,
      promoCode: (json['promoCode'] ?? '') as String,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        tagText,
        title,
        buttonText,
        imageUrl,
        gradientColors,
        priorityOrder,
        isActive,
        createdAt,
        actionType,
        targetServiceId,
        targetService,
        targetCategoryId,
        targetUrl,
        promoCode,
      ];
}
