import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/hex_color.dart';

/// Trimmed non-empty string, else null — used when reading optional hex tokens.
String? _optStr(dynamic v) =>
    (v is String && v.trim().isNotEmpty) ? v.trim() : null;

/// Optional per-card color overrides ("micro-branding"), mirroring the backend
/// `contentData[].cardStyles`. Raw `#RRGGBB` hex **strings** are stored and
/// parsed lazily (same pattern as [PromoBanner.gradientColors]); a null token
/// means "use the app's theme fallback". Card bg + accent are Light/Dark pairs;
/// tag colors are single values used in both themes.
@immutable
class CardStyleTokens extends Equatable {
  final String? cardBgLight;
  final String? cardBgDark;
  final String? accentColorLight;
  final String? accentColorDark;
  final String? tagBgColor;
  final String? tagTextColor;

  const CardStyleTokens({
    this.cardBgLight,
    this.cardBgDark,
    this.accentColorLight,
    this.accentColorDark,
    this.tagBgColor,
    this.tagTextColor,
  });

  /// Resolved card background for the ambient brightness, or null (fall back).
  Color? cardBg(bool dark) => hexToColor(dark ? cardBgDark : cardBgLight);

  /// Resolved accent (["+" button] + card glow) for the brightness, or null.
  Color? accent(bool dark) => hexToColor(dark ? accentColorDark : accentColorLight);

  Color? get tagBg => hexToColor(tagBgColor);
  Color? get tagText => hexToColor(tagTextColor);

  /// True when no override is set — used to drop the object entirely.
  bool get isEmpty =>
      cardBgLight == null &&
      cardBgDark == null &&
      accentColorLight == null &&
      accentColorDark == null &&
      tagBgColor == null &&
      tagTextColor == null;

  factory CardStyleTokens.fromJson(Map<String, dynamic> json) => CardStyleTokens(
        cardBgLight: _optStr(json['cardBgLight']),
        cardBgDark: _optStr(json['cardBgDark']),
        accentColorLight: _optStr(json['accentColorLight']),
        accentColorDark: _optStr(json['accentColorDark']),
        tagBgColor: _optStr(json['tagBgColor']),
        tagTextColor: _optStr(json['tagTextColor']),
      );

  Map<String, dynamic> toJson() => {
        'cardBgLight': cardBgLight,
        'cardBgDark': cardBgDark,
        'accentColorLight': accentColorLight,
        'accentColorDark': accentColorDark,
        'tagBgColor': tagBgColor,
        'tagTextColor': tagTextColor,
      };

  @override
  List<Object?> get props => [
        cardBgLight,
        cardBgDark,
        accentColorLight,
        accentColorDark,
        tagBgColor,
        tagTextColor,
      ];
}

/// Optional section-container color overrides, mirroring the backend
/// `styleTokens`. Same store-hex / parse-lazily / null-means-fallback contract
/// as [CardStyleTokens].
@immutable
class SectionStyleTokens extends Equatable {
  final String? titleColorLight;
  final String? titleColorDark;
  final String? sectionBackgroundColor;

  const SectionStyleTokens({
    this.titleColorLight,
    this.titleColorDark,
    this.sectionBackgroundColor,
  });

  /// Resolved header-title color for the ambient brightness, or null.
  Color? title(bool dark) => hexToColor(dark ? titleColorDark : titleColorLight);

  /// Resolved section background, or null (no background painted).
  Color? get background => hexToColor(sectionBackgroundColor);

  bool get isEmpty =>
      titleColorLight == null &&
      titleColorDark == null &&
      sectionBackgroundColor == null;

  factory SectionStyleTokens.fromJson(Map<String, dynamic> json) =>
      SectionStyleTokens(
        titleColorLight: _optStr(json['titleColorLight']),
        titleColorDark: _optStr(json['titleColorDark']),
        sectionBackgroundColor: _optStr(json['sectionBackgroundColor']),
      );

  Map<String, dynamic> toJson() => {
        'titleColorLight': titleColorLight,
        'titleColorDark': titleColorDark,
        'sectionBackgroundColor': sectionBackgroundColor,
      };

  @override
  List<Object?> get props =>
      [titleColorLight, titleColorDark, sectionBackgroundColor];
}

/// How a section arranges its cards. Mirrors the backend
/// `DynamicSection.layoutType` enum.
///
/// Orthogonal to [HomeSection.uiTemplate], which says what a *card* looks
/// like; this says how the cards are arranged. Only the reserved
/// `CARE_SERVICES` section reads it today — its renderer is the adaptive
/// layout engine in `care_services_section.dart` — and it is what the admin's
/// layout selector writes.
enum HomeLayoutType { grid2Col, carousel, list }

extension HomeLayoutTypeX on HomeLayoutType {
  String get wire => switch (this) {
        HomeLayoutType.grid2Col => 'GRID_2_COL',
        HomeLayoutType.carousel => 'CAROUSEL',
        HomeLayoutType.list => 'LIST',
      };

  /// Admin-facing name in the CMS layout selector.
  String get label => switch (this) {
        HomeLayoutType.grid2Col => '2-column grid',
        HomeLayoutType.carousel => 'Horizontal carousel',
        HomeLayoutType.list => 'Full-width list',
      };

  /// One-line description under the label in the selector.
  String get description => switch (this) {
        HomeLayoutType.grid2Col => 'Side-by-side card grid, two per row.',
        HomeLayoutType.carousel => 'Swipeable horizontal card rail.',
        HomeLayoutType.list => 'Vertical stack of full-width rows.',
      };

  /// An unknown wire value falls back to the carousel — the layout Care
  /// Services rendered before it was configurable, so a backend that ships a
  /// fourth layout before the app knows it degrades to today's screen rather
  /// than to an empty one.
  static HomeLayoutType fromWire(String? raw) => switch (raw) {
        'GRID_2_COL' => HomeLayoutType.grid2Col,
        'LIST' => HomeLayoutType.list,
        _ => HomeLayoutType.carousel,
      };
}

/// What a tap on a [HomeSectionItem] does. Mirrors the backend
/// `contentData[].targetType` enum (and [BannerActionType]'s role for promo
/// banners): only the field matching the type carries a value.
enum HomeItemTargetType { service, customRoute, externalUrl, none }

extension HomeItemTargetTypeX on HomeItemTargetType {
  String get wire => switch (this) {
        HomeItemTargetType.service => 'SERVICE',
        HomeItemTargetType.customRoute => 'CUSTOM_ROUTE',
        HomeItemTargetType.externalUrl => 'EXTERNAL_URL',
        HomeItemTargetType.none => 'NONE',
      };

  /// Admin-facing label for the CMS target dropdown.
  String get label => switch (this) {
        HomeItemTargetType.service => 'Service — opens booking prefilled',
        HomeItemTargetType.customRoute => 'In-app route',
        HomeItemTargetType.externalUrl => 'External link',
        HomeItemTargetType.none => 'Nothing (display only)',
      };

  static HomeItemTargetType fromWire(String? raw) => switch (raw) {
        'SERVICE' => HomeItemTargetType.service,
        'CUSTOM_ROUTE' => HomeItemTargetType.customRoute,
        'EXTERNAL_URL' => HomeItemTargetType.externalUrl,
        _ => HomeItemTargetType.none,
      };
}

/// Lightweight snapshot of an item's linked catalog service, taken from the
/// backend's populated `contentData[].serviceId` (see the
/// `ITEM_SERVICE_POPULATE` select in `homeSections.js`). Enough for the
/// patient app to prefill the booking form on tap without a second
/// `/api/services` round trip — the same contract as [BannerTargetService].
class LinkedService extends Equatable {
  final String id;
  final String title;
  final double price;
  final String category;
  final String? imageUrl;

  /// `active` / `inactive` — an inactive link is flagged in the admin CMS.
  final String status;

  const LinkedService({
    required this.id,
    required this.title,
    required this.price,
    this.category = '',
    this.imageUrl,
    this.status = 'active',
  });

  bool get isActive => status == 'active';

  factory LinkedService.fromJson(Map<String, dynamic> json) => LinkedService(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        title: (json['title'] ?? '') as String,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        category: (json['category'] ?? '') as String,
        imageUrl: json['imageUrl'] as String?,
        status: (json['status'] ?? 'active') as String,
      );

  @override
  List<Object?> get props => [id, title, price, category, imageUrl, status];
}

/// One content element inside a [HomeSection] (an avatar, product card,
/// grid tile, or banner slide depending on the section's template).
///
/// Mirrors the backend `DynamicSection.contentData[]` embedded doc
/// (camelCase keys). [toJson] exists because sections are saved back with
/// a whole-array `contentData` replace.
class HomeSectionItem extends Equatable {
  /// Client-generated stable key; also drives the uploaded image public_id.
  final String itemId;
  final String title;
  final String? subtitle;

  /// Bengali counterparts of [title] / [subtitle]. The app has no locale
  /// switch, so these render as a secondary line beside the English text
  /// (matching the section title); null ⇒ English alone.
  final String? titleBn;
  final String? subtitleBn;

  final String imageUrl;
  final String? priceTag;

  /// The capsule floating on the card image ("Popular", "New").
  ///
  /// Cards saved before this field existed have none, and the renderer falls
  /// back to [subtitle] for them — which is what that slot used to hold. Read
  /// [badgeLabel] / [descriptionLine] rather than these two fields directly.
  final String? badgeText;

  /// Per-card visibility. The public feed already omits hidden cards, so this
  /// is only ever false in the admin console.
  final bool isActive;

  /// Which Home filter pill this card belongs under; null ⇒ untagged, so the
  /// card only appears under the implicit "All" pill.
  final String? categoryId;

  /// The tagged category's slug, resolved server-side. Null when untagged, or
  /// when the tag points at a category that has since been deleted — the id
  /// still round-trips so the CMS doesn't silently drop it on the next save.
  final String? categorySlug;

  // --- Tap target -------------------------------------------------------

  /// What tapping this card does. [HomeItemTargetType.service] is the headline
  /// case: it launches the New Care Request flow with [serviceId] already
  /// selected (see `dynamic_route_dispatcher.dart`).
  final HomeItemTargetType targetType;

  /// Linked catalog service id, set when [targetType] is
  /// [HomeItemTargetType.service].
  final String? serviceId;

  /// In-app route for [HomeItemTargetType.customRoute] (e.g.
  /// `activities:tracking`) or the address for
  /// [HomeItemTargetType.externalUrl].
  final String customRoute;

  /// Populated snapshot of [serviceId], when the backend resolved it. Lets the
  /// tap prefill the booking form even before `/api/services` has loaded.
  final LinkedService? linkedService;

  /// Legacy mirror of the resolved target, e.g. `service:<id>`,
  /// `activities:tracking`, `https://…`. Older app builds navigate off this;
  /// the backend keeps it in sync on every write. Unknown values no-op.
  final String? navigationRoute;
  final Map<String, String> routeArguments;

  /// Optional per-card color overrides; null when the card uses theme defaults.
  final CardStyleTokens? cardStyles;

  const HomeSectionItem({
    required this.itemId,
    required this.title,
    this.subtitle,
    this.titleBn,
    this.subtitleBn,
    required this.imageUrl,
    this.priceTag,
    this.badgeText,
    this.isActive = true,
    this.categoryId,
    this.categorySlug,
    this.targetType = HomeItemTargetType.none,
    this.serviceId,
    this.customRoute = '',
    this.linkedService,
    this.navigationRoute,
    this.routeArguments = const {},
    this.cardStyles,
  });

  /// True when the card links to a bookable service — the tap that opens the
  /// booking wizard pre-selected.
  bool get linksToService =>
      targetType == HomeItemTargetType.service &&
      (serviceId != null && serviceId!.isNotEmpty);

  /// What belongs in the card's floating capsule.
  ///
  /// Falls back to [subtitle] because that is the slot the capsule used before
  /// [badgeText] existed — without the fallback, every card saved under the old
  /// CMS would silently lose its badge on upgrade.
  String? get badgeLabel {
    final badge = badgeText?.trim();
    if (badge != null && badge.isNotEmpty) return badge;
    return _blankToNull(subtitle);
  }

  /// What belongs on the card's description line: [subtitle], but only once
  /// [badgeText] has claimed the capsule. On a legacy card [subtitle] is still
  /// the badge, so this stays null and the card renders exactly as before.
  String? get descriptionLine {
    final badge = badgeText?.trim();
    if (badge == null || badge.isEmpty) return null;
    return _blankToNull(subtitle);
  }

  static String? _blankToNull(String? v) {
    final s = v?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Reads a reference field that may arrive as a bare id or a populated
  /// object, returning the id either way. Blank ⇒ null (unset).
  static String? _idOf(dynamic raw) {
    if (raw == null) return null;
    final id = raw is Map ? (raw['id'] ?? raw['_id'])?.toString() : raw.toString();
    return (id == null || id.trim().isEmpty) ? null : id.trim();
  }

  HomeSectionItem copyWith({
    String? itemId,
    String? title,
    String? subtitle,
    String? titleBn,
    String? subtitleBn,
    String? imageUrl,
    String? priceTag,
    String? badgeText,
    bool? isActive,
    String? categoryId,
    String? categorySlug,
    HomeItemTargetType? targetType,
    String? serviceId,
    String? customRoute,
    LinkedService? linkedService,
    String? navigationRoute,
    Map<String, String>? routeArguments,
    CardStyleTokens? cardStyles,
  }) {
    return HomeSectionItem(
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      titleBn: titleBn ?? this.titleBn,
      subtitleBn: subtitleBn ?? this.subtitleBn,
      imageUrl: imageUrl ?? this.imageUrl,
      priceTag: priceTag ?? this.priceTag,
      badgeText: badgeText ?? this.badgeText,
      isActive: isActive ?? this.isActive,
      categoryId: categoryId ?? this.categoryId,
      categorySlug: categorySlug ?? this.categorySlug,
      targetType: targetType ?? this.targetType,
      serviceId: serviceId ?? this.serviceId,
      customRoute: customRoute ?? this.customRoute,
      linkedService: linkedService ?? this.linkedService,
      navigationRoute: navigationRoute ?? this.navigationRoute,
      routeArguments: routeArguments ?? this.routeArguments,
      cardStyles: cardStyles ?? this.cardStyles,
    );
  }

  factory HomeSectionItem.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['routeArguments'];
    final args = <String, String>{};
    if (rawArgs is Map) {
      rawArgs.forEach((k, v) {
        if (v != null) args[k.toString()] = v.toString();
      });
    }
    final rawStyles = json['cardStyles'];
    final styles = rawStyles is Map
        ? CardStyleTokens.fromJson(Map<String, dynamic>.from(rawStyles))
        : null;
    final rawService = json['serviceId'];
    // The backend sends `serviceId` as a plain id string plus a populated
    // `service` snapshot, but tolerate a populated object on `serviceId` too.
    final serviceId = rawService is Map
        ? (rawService['id'] ?? rawService['_id'])?.toString()
        : rawService?.toString();
    final rawSnapshot = json['service'] ?? (rawService is Map ? rawService : null);
    final route = json['navigationRoute'] as String?;
    return HomeSectionItem(
      itemId: (json['itemId'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      subtitle: json['subtitle'] as String?,
      titleBn: json['titleBn'] as String?,
      subtitleBn: json['subtitleBn'] as String?,
      imageUrl: (json['imageUrl'] ?? '') as String,
      priceTag: json['priceTag'] as String?,
      badgeText: json['badgeText'] as String?,
      // Absent from a backend predating per-card visibility ⇒ visible.
      isActive: json['isActive'] as bool? ?? true,
      // The backend flattens `categoryId` to a plain id and puts the resolved
      // snapshot on `category`; tolerate a populated object here too, the same
      // way `serviceId` above does.
      categoryId: _idOf(json['categoryId']),
      categorySlug: (json['categorySlug'] as String?) ??
          (json['category'] is Map ? json['category']['slug'] as String? : null),
      targetType: _resolveTargetType(json['targetType'] as String?, serviceId, route),
      serviceId: (serviceId != null && serviceId.isNotEmpty) ? serviceId : null,
      customRoute: (json['customRoute'] ?? '') as String,
      linkedService: rawSnapshot is Map
          ? LinkedService.fromJson(Map<String, dynamic>.from(rawSnapshot))
          : null,
      navigationRoute: route,
      routeArguments: args,
      cardStyles: (styles != null && !styles.isEmpty) ? styles : null,
    );
  }

  /// Client-side mirror of the backend's `normalizeTarget` fallback: a section
  /// saved before target linking shipped (or served by an older backend) has
  /// no `targetType`, so the legacy route string decides. Keeps those cards
  /// navigating exactly as they did.
  static HomeItemTargetType _resolveTargetType(
    String? raw,
    String? serviceId,
    String? route,
  ) {
    final declared = HomeItemTargetTypeX.fromWire(raw);
    if (raw != null && !(declared == HomeItemTargetType.service &&
        (serviceId == null || serviceId.isEmpty))) {
      return declared;
    }
    final r = route?.trim() ?? '';
    if (r.startsWith('http://') || r.startsWith('https://')) {
      return HomeItemTargetType.externalUrl;
    }
    if (r.startsWith('service:')) return HomeItemTargetType.service;
    return r.isEmpty ? HomeItemTargetType.none : HomeItemTargetType.customRoute;
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'subtitle': subtitle,
        'titleBn': titleBn,
        'subtitleBn': subtitleBn,
        'imageUrl': imageUrl,
        'priceTag': priceTag,
        'badgeText': badgeText,
        'isActive': isActive,
        'categoryId': categoryId,
        'targetType': targetType.wire,
        'serviceId': serviceId,
        'customRoute': customRoute,
        // Sent for backends predating structured targets; the current one
        // recomputes it from the fields above.
        'navigationRoute': navigationRoute,
        'routeArguments': routeArguments,
        if (cardStyles != null) 'cardStyles': cardStyles!.toJson(),
      };

  @override
  List<Object?> get props => [
        itemId,
        title,
        subtitle,
        titleBn,
        subtitleBn,
        imageUrl,
        priceTag,
        badgeText,
        isActive,
        categoryId,
        categorySlug,
        targetType,
        serviceId,
        customRoute,
        linkedService,
        navigationRoute,
        routeArguments,
        cardStyles,
      ];
}

/// An admin-managed dynamic section rendered on the patient Home below the
/// fixed Banners + Care Services blocks.
///
/// Mirrors the backend `DynamicSection` document (camelCase keys + `id` via
/// its `toJSON` transform). [uiTemplate] is kept as a raw string — not an
/// enum — so a future backend can ship new template values without breaking
/// this client; the renderer skips anything not in [supportedTemplates].
class HomeSection extends Equatable {
  final String id;
  final String sectionKey;
  final String titleEn;
  final String? titleBn;
  final String uiTemplate;

  /// How this section arranges its cards. Read by the Care Services block
  /// only; the templated sections below it ignore it (see [HomeLayoutType]).
  final HomeLayoutType layoutType;

  /// Ascending display order below the fixed blocks — lower shows first.
  final int orderIndex;
  final bool isActive;
  final List<HomeSectionItem> contentData;

  /// Optional section-container color overrides; null when using theme defaults.
  final SectionStyleTokens? styleTokens;
  final DateTime? createdAt;

  const HomeSection({
    required this.id,
    required this.sectionKey,
    required this.titleEn,
    this.titleBn,
    required this.uiTemplate,
    this.layoutType = HomeLayoutType.carousel,
    this.orderIndex = 0,
    this.isActive = true,
    this.contentData = const [],
    this.styleTokens,
    this.createdAt,
  });

  /// The one `sectionKey` the app treats specially: it is the Care Services
  /// block on Home, so its `layoutType` drives the adaptive layout engine and
  /// the generic dynamic-sections renderer skips it (it would otherwise draw
  /// the block a second time).
  ///
  /// MIRROR: `CARE_SERVICES_KEY` in backend/src/routes/homeSections.js.
  static const String careServicesKey = 'CARE_SERVICES';

  /// True for the reserved Care Services section.
  bool get isCareServices => sectionKey == careServicesKey;

  static const templateHorizontalRoundAvatar = 'HORIZONTAL_ROUND_AVATAR';
  static const templateHorizontalProductCard = 'HORIZONTAL_PRODUCT_CARD';
  static const templateGrid2x2Tiles = 'GRID_2X2_TILES';
  static const templateSingleWideBanner = 'SINGLE_WIDE_BANNER';

  /// Every template this app version knows how to render.
  static const supportedTemplates = {
    templateHorizontalRoundAvatar,
    templateHorizontalProductCard,
    templateGrid2x2Tiles,
    templateSingleWideBanner,
  };

  HomeSection copyWith({
    String? id,
    String? sectionKey,
    String? titleEn,
    String? titleBn,
    String? uiTemplate,
    HomeLayoutType? layoutType,
    int? orderIndex,
    bool? isActive,
    List<HomeSectionItem>? contentData,
    SectionStyleTokens? styleTokens,
    DateTime? createdAt,
  }) {
    return HomeSection(
      id: id ?? this.id,
      sectionKey: sectionKey ?? this.sectionKey,
      titleEn: titleEn ?? this.titleEn,
      titleBn: titleBn ?? this.titleBn,
      uiTemplate: uiTemplate ?? this.uiTemplate,
      layoutType: layoutType ?? this.layoutType,
      orderIndex: orderIndex ?? this.orderIndex,
      isActive: isActive ?? this.isActive,
      contentData: contentData ?? this.contentData,
      styleTokens: styleTokens ?? this.styleTokens,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['contentData'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) =>
                HomeSectionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <HomeSectionItem>[];
    final rawStyles = json['styleTokens'];
    final styles = rawStyles is Map
        ? SectionStyleTokens.fromJson(Map<String, dynamic>.from(rawStyles))
        : null;
    return HomeSection(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      sectionKey: (json['sectionKey'] ?? '') as String,
      titleEn: (json['titleEn'] ?? '') as String,
      titleBn: json['titleBn'] as String?,
      uiTemplate: (json['uiTemplate'] ?? '') as String,
      layoutType: HomeLayoutTypeX.fromWire(json['layoutType'] as String?),
      orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      contentData: items,
      styleTokens: (styles != null && !styles.isEmpty) ? styles : null,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  /// Serialized for POST/PUT bodies — omits `id`/`createdAt` (server-owned).
  Map<String, dynamic> toJson() => {
        'sectionKey': sectionKey,
        'titleEn': titleEn,
        'titleBn': titleBn,
        'uiTemplate': uiTemplate,
        'layoutType': layoutType.wire,
        'orderIndex': orderIndex,
        'isActive': isActive,
        'contentData': contentData.map((e) => e.toJson()).toList(),
        if (styleTokens != null) 'styleTokens': styleTokens!.toJson(),
      };

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        sectionKey,
        titleEn,
        titleBn,
        uiTemplate,
        layoutType,
        orderIndex,
        isActive,
        contentData,
        styleTokens,
        createdAt,
      ];
}
