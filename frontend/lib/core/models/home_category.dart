import 'package:equatable/equatable.dart';

import 'service_category.dart';

/// One admin-managed filter pill on the patient Home chip rail.
///
/// Mirrors the backend `Category` document (camelCase keys + `id` via its
/// `toJSON` transform). The rail used to be [kPatientCategoryChips] — a
/// three-entry list compiled into the binary — so adding a category meant
/// shipping a release; these come from `/api/home-data` at runtime.
///
/// [slug] is the join key, not a label: a service's free-text `category` is
/// folded through [categorySlugFor] and compared against it. Renaming a pill
/// therefore never breaks the join, and translating one never could.
class HomeCategory extends Equatable {
  final String id;
  final String nameEn;

  /// Bengali counterpart. There is no app-wide locale switch, so this renders
  /// as a second line inside the pill; null ⇒ English alone.
  final String? nameBn;

  /// One-line blurb the dedicated category view prints under the title
  /// ("Licensed doctors visiting your home for consultations"). Null ⇒ the
  /// header shows the title and the service count alone.
  final String? descriptionEn;
  final String? descriptionBn;

  final String slug;

  /// Optional pill glyph; null ⇒ the label renders alone.
  final String? iconUrl;

  /// Ascending rail order, left to right after the implicit "All" pill.
  final int displayOrder;
  final bool isActive;

  const HomeCategory({
    required this.id,
    required this.nameEn,
    this.nameBn,
    this.descriptionEn,
    this.descriptionBn,
    required this.slug,
    this.iconUrl,
    this.displayOrder = 0,
    this.isActive = true,
  });

  /// The slug of the implicit "All" pill.
  ///
  /// Deliberately not a stored category: the rail always renders it at index 0
  /// (see `CategoryFilterBar`), because a pill an admin can delete is a pill
  /// that can strand a patient in a filtered view with no way back to the full
  /// catalog.
  static const String allSlug = kCategoryAllSlug;

  /// The sentinel pill the rail prepends. [id] is empty — it exists only on
  /// the client.
  ///
  /// [nameBn] is deliberately left null: "All" is the one pill that is not an
  /// admin-authored category, and it reads the same in either script, so the
  /// Bengali second line only made the shortest pill in the rail two lines
  /// tall for nothing.
  static const HomeCategory all = HomeCategory(
    id: '',
    nameEn: 'All',
    slug: allSlug,
    displayOrder: -1,
  );

  bool get isAll => id.isEmpty && slug == allSlug;

  /// The rail the app falls back to when `/api/home-data` is unreachable or
  /// predates categories — the same two chips the compiled list has always
  /// carried, so an old backend or an offline launch degrades to today's
  /// behaviour rather than to a bare "All".
  static List<HomeCategory> get compiledFallback => [
    for (var i = 0; i < kServiceCategories.length; i++)
      HomeCategory(
        id: '',
        nameEn: kServiceCategories[i],
        slug: categorySlugFor(kServiceCategories[i]),
        displayOrder: i,
      ),
  ];

  factory HomeCategory.fromJson(Map<String, dynamic> json) {
    // Tolerates the snake_case spelling of every field: the API emits
    // camelCase like its siblings, but the published schema for this feature
    // is snake_case, so a payload written against it still parses.
    T? pick<T>(String camel, String snake) =>
        (json[camel] ?? json[snake]) as T?;
    final name = _str(pick<dynamic>('nameEn', 'name_en'));
    final slug = _str(pick<dynamic>('slug', 'slug'));
    return HomeCategory(
      id: _str(json['id'] ?? json['_id']),
      nameEn: name,
      nameBn: _nullableStr(pick<dynamic>('nameBn', 'name_bn')),
      descriptionEn: _nullableStr(
        pick<dynamic>('descriptionEn', 'description_en'),
      ),
      descriptionBn: _nullableStr(
        pick<dynamic>('descriptionBn', 'description_bn'),
      ),
      // A category with no slug could never match a service, so derive one
      // from the name rather than leaving the pill permanently empty.
      slug: slug.isNotEmpty ? slug : categorySlugFor(name),
      iconUrl: _nullableStr(pick<dynamic>('iconUrl', 'icon_url')),
      displayOrder:
          (pick<dynamic>('displayOrder', 'display_order') as num?)?.toInt() ??
          0,
      isActive: pick<dynamic>('isActive', 'is_active') as bool? ?? true,
    );
  }

  /// Serialized for POST/PATCH bodies — omits `id` (server-owned).
  Map<String, dynamic> toJson() => {
    'nameEn': nameEn,
    'nameBn': nameBn,
    'descriptionEn': descriptionEn,
    'descriptionBn': descriptionBn,
    'slug': slug,
    'iconUrl': iconUrl,
    'displayOrder': displayOrder,
    'isActive': isActive,
  };

  HomeCategory copyWith({
    String? id,
    String? nameEn,
    String? nameBn,
    String? descriptionEn,
    String? descriptionBn,
    String? slug,
    String? iconUrl,
    int? displayOrder,
    bool? isActive,
  }) {
    return HomeCategory(
      id: id ?? this.id,
      nameEn: nameEn ?? this.nameEn,
      nameBn: nameBn ?? this.nameBn,
      descriptionEn: descriptionEn ?? this.descriptionEn,
      descriptionBn: descriptionBn ?? this.descriptionBn,
      slug: slug ?? this.slug,
      iconUrl: iconUrl ?? this.iconUrl,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Any scalar → String; Maps/Lists are rejected rather than stringified into
  /// `{a: b}` prose that would land on screen. (Same total-function parsing
  /// contract as [ServiceCatalogItem.fromJson].)
  static String _str(dynamic raw, {String fallback = ''}) {
    if (raw == null || raw is Map || raw is Iterable) return fallback;
    final s = raw.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static String? _nullableStr(dynamic raw) {
    final s = _str(raw);
    return s.isEmpty ? null : s;
  }

  @override
  List<Object?> get props => [
    id,
    nameEn,
    nameBn,
    descriptionEn,
    descriptionBn,
    slug,
    iconUrl,
    displayOrder,
    isActive,
  ];
}
