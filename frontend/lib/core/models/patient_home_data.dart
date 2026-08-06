import 'package:equatable/equatable.dart';

import 'home_category.dart';
import 'home_section.dart';
import 'home_service_card.dart';

/// The Care Services block as the CMS defines it: a title, the admin's chosen
/// layout, and the cards to draw.
///
/// [source] says where the cards came from — `CATALOG` (the live
/// `/api/services` list, which is what every deployment gets until an admin
/// curates the section) or `CURATED` (cards built by hand in the CMS). The
/// renderer does not branch on it; it exists so the CMS can tell an operator
/// which of the two is currently on screen.
class CareServicesBlock extends Equatable {
  /// The backing `CARE_SERVICES` section's id, or null when no admin has
  /// touched the layout yet and no document exists.
  final String? id;

  final String titleEn;
  final String? titleBn;
  final HomeLayoutType layoutType;
  final bool isActive;
  final String source;
  final List<HomeServiceCard> services;

  const CareServicesBlock({
    this.id,
    this.titleEn = 'Care services',
    this.titleBn = 'সেবা',
    this.layoutType = HomeLayoutType.carousel,
    this.isActive = true,
    this.source = 'CATALOG',
    this.services = const [],
  });

  bool get isCurated => source == 'CURATED';

  factory CareServicesBlock.fromJson(Map<String, dynamic> json) {
    final raw = json['services'];
    return CareServicesBlock(
      id: (json['id'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['id'] as String,
      titleEn: (json['titleEn'] as String?)?.trim().isNotEmpty == true
          ? json['titleEn'] as String
          : 'Care services',
      titleBn: json['titleBn'] as String?,
      layoutType: HomeLayoutTypeX.fromWire(json['layoutType'] as String?),
      isActive: json['isActive'] as bool? ?? true,
      source: (json['source'] as String?) ?? 'CATALOG',
      services: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => HomeServiceCard.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  CareServicesBlock copyWith({
    HomeLayoutType? layoutType,
    List<HomeServiceCard>? services,
  }) {
    return CareServicesBlock(
      id: id,
      titleEn: titleEn,
      titleBn: titleBn,
      layoutType: layoutType ?? this.layoutType,
      isActive: isActive,
      source: source,
      services: services ?? this.services,
    );
  }

  @override
  List<Object?> get props =>
      [id, titleEn, titleBn, layoutType, isActive, source, services];
}

/// Everything the patient Home screen needs above the support footer, in one
/// document — `GET /api/home-data`.
///
/// Home used to open with three parallel requests, and the chip rail wasn't
/// one of them because it was compiled into the binary. Now that the rail, the
/// Care Services layout, and the cards are all admin-controlled and
/// interdependent (a card's pill has to exist for the filter to mean
/// anything), they are assembled server-side and fetched together — one
/// round trip, and no window where the rail has rendered but the cards it
/// filters have not.
class PatientHomeData extends Equatable {
  final List<HomeCategory> categories;
  final CareServicesBlock careServices;

  /// The admin-managed sections below Care Services. The reserved
  /// `CARE_SERVICES` section is already excluded server-side.
  final List<HomeSection> sections;

  /// True when this came off the wire; false for the degraded value the
  /// repository synthesizes when `/api/home-data` is unreachable or the
  /// backend predates it. The Care Services block then falls back to the live
  /// catalog and the rail to [HomeCategory.compiledFallback].
  final bool isLive;

  const PatientHomeData({
    this.categories = const [],
    this.careServices = const CareServicesBlock(),
    this.sections = const [],
    this.isLive = true,
  });

  /// What Home renders when the aggregate endpoint isn't available: the two
  /// compiled chips and no cards of its own, leaving the existing
  /// `/api/services` + `/api/home-sections` providers to fill the screen.
  static const PatientHomeData fallback = PatientHomeData(isLive: false);

  /// The rail as it should render, "All" excluded — the bar prepends that
  /// itself. Falls back to the compiled chips when the server sent none, so a
  /// deployment that hasn't run `npm run migrate:home-categories` still shows
  /// the rail it had before.
  List<HomeCategory> get railCategories {
    final live = categories.where((c) => c.isActive).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return live.isNotEmpty ? live : HomeCategory.compiledFallback;
  }

  /// The rail pill with this [slug], or null when nothing matches — a pill an
  /// admin has since hidden or deleted, or the implicit "All" sentinel, which
  /// is never stored. Callers treat null as "fall back to the full Home view".
  HomeCategory? categoryBySlug(String slug) {
    if (slug.isEmpty || slug == HomeCategory.allSlug) return null;
    for (final c in railCategories) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  factory PatientHomeData.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final rawSections = json['sections'];
    final rawCare = json['careServices'] ?? json['care_services'];
    return PatientHomeData(
      categories: rawCategories is List
          ? rawCategories
              .whereType<Map>()
              .map((e) => HomeCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      careServices: rawCare is Map
          ? CareServicesBlock.fromJson(Map<String, dynamic>.from(rawCare))
          : const CareServicesBlock(),
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((e) => HomeSection.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [categories, careServices, sections, isLive];
}
