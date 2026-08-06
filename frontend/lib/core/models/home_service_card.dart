import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import 'service_catalog_item.dart';
import 'service_category.dart';

final NumberFormat _moneyFmt = NumberFormat('#,###', 'en_US');

/// One card in the Care Services block.
///
/// The block has two possible sources — the live `/api/services` catalog, or a
/// curated `CARE_SERVICES` section an admin built in the CMS — and the API
/// projects both onto this single shape (see `fromCatalog` / `fromCuratedSection`
/// in backend/src/routes/homeData.js). That is deliberate: the adaptive layout
/// engine renders three layouts, and having it also branch on where a card came
/// from would multiply into six paths that drift apart.
///
/// [fromCatalog] builds the same shape client-side, for the fallback path where
/// `/api/home-data` is unreachable and Home degrades to the plain catalog.
class HomeServiceCard extends Equatable {
  /// Stable key for the card. `svc_<serviceId>` for catalog-sourced cards, the
  /// admin's `itemId` for curated ones.
  final String itemId;

  /// The catalog service this card books. Null on a curated card the admin
  /// linked nowhere — those render but don't open the booking flow prefilled.
  final String? serviceId;

  /// The Home pill this card hides behind. Null ⇒ untagged: visible under
  /// "All" and nowhere else.
  final String? categoryId;
  final String? categorySlug;

  /// Every pill this card belongs under — a service can now be assigned to
  /// several in the CMS ("Post-op" *and* "Doctor in Home"). [categorySlug] is
  /// this list's first entry, kept as a scalar because it is what the badge and
  /// the pre-multi-assignment filter follow.
  ///
  /// Empty ⇒ untagged. Filter through [matchesCategorySlug] rather than
  /// reading either field directly, so a payload from a backend that predates
  /// the list still matches on the scalar.
  final List<String> categorySlugs;

  /// True when this service can be dispatched as an urgent/same-day visit —
  /// the admin's toggle, not an inference. Backs the "Urgent" sub-filter.
  final bool isUrgentAvailable;

  /// Average of the patient feedback left on this service, and how many
  /// reviews it came from. `0` / `0` means nobody has rated it yet — the API
  /// computes both from real bookings and never invents a default.
  final double rating;
  final int ratingCount;

  final String titleEn;
  final String? titleBn;
  final String? subtitleEn;
  final String? subtitleBn;

  /// Numeric price in BDT. Null when a curated card's price tag is words
  /// ("Free") — [priceLabel] then falls back to [priceTag] verbatim.
  final double? price;

  /// The admin's freeform price tag, when the card came from the CMS.
  final String? priceTag;

  /// The capsule floating on the card image. The API already applies the
  /// legacy fallback (a card saved before `badgeText` existed spent `subtitle`
  /// on the capsule), so this is the badge as it should render.
  final String? badgeText;

  final String? imageUrl;

  const HomeServiceCard({
    required this.itemId,
    this.serviceId,
    this.categoryId,
    this.categorySlug,
    this.categorySlugs = const [],
    this.isUrgentAvailable = false,
    this.rating = 0,
    this.ratingCount = 0,
    required this.titleEn,
    this.titleBn,
    this.subtitleEn,
    this.subtitleBn,
    this.price,
    this.priceTag,
    this.badgeText,
    this.imageUrl,
  });

  /// True when this card belongs under the [selectedSlug] pill.
  ///
  /// Checks the whole [categorySlugs] set, falling back to the scalar
  /// [categorySlug] so a payload from a backend that predates multi-assignment
  /// still filters. `all` (and a blank selection) match everything, untagged
  /// cards included.
  bool matchesCategorySlug(String selectedSlug) {
    if (categorySlugs.isEmpty) {
      return serviceMatchesCategorySlug(categorySlug, selectedSlug);
    }
    return serviceMatchesAnyCategorySlug(categorySlugs, selectedSlug);
  }

  /// The rating as it appears on a card, e.g. `4.8`. Null while unrated, so
  /// the star row is omitted rather than printing a hollow `0.0`.
  String? get ratingLabel =>
      (rating > 0 && ratingCount > 0) ? rating.toStringAsFixed(1) : null;

  /// The card title, with its Bengali counterpart on a second line when the
  /// admin supplied one. There is no app-wide locale switch, so both scripts
  /// show at once — the same treatment section headers give `titleBn`.
  String get title => _joinBilingual(titleEn, titleBn);

  /// The description line, bilingual on the same terms as [title]. Null when
  /// neither script has content, so the card keeps its silhouette.
  String? get description {
    final en = subtitleEn?.trim();
    final bn = subtitleBn?.trim();
    if (en == null || en.isEmpty) return (bn == null || bn.isEmpty) ? null : bn;
    return _joinBilingual(en, bn);
  }

  /// Price as it appears on the card, e.g. `৳ 1,500`.
  ///
  /// A numeric price always wins so catalog and curated cards read identically
  /// down a rail; a non-numeric tag ("Free") passes through verbatim; neither
  /// ⇒ null and the price line is omitted.
  String? get priceLabel {
    final p = price;
    if (p != null && p > 0) return '৳ ${_moneyFmt.format(p.round())}';
    final tag = priceTag?.trim();
    return (tag == null || tag.isEmpty) ? null : tag;
  }

  /// True when tapping this card can prefill the booking form.
  bool get isBookable => (serviceId ?? '').isNotEmpty;

  static String _joinBilingual(String en, String? bn) {
    final b = bn?.trim();
    return (b == null || b.isEmpty) ? en : '$en\n$b';
  }

  /// Total-function parser: every field is coerced, never cast, for the same
  /// reason [ServiceCatalogItem.fromJson] is — this feeds the first screen
  /// every patient sees, and one malformed row must not blank the block.
  factory HomeServiceCard.fromJson(Map<String, dynamic> json) {
    dynamic pick(String camel, String snake) => json[camel] ?? json[snake];
    // Resolved once and used for both fields, so the model's own invariant —
    // "[categorySlug] is [categorySlugs]'s first entry" — holds no matter what
    // the wire sent. Reading the two independently let a payload carrying only
    // the list arrive with a null scalar, which anything still filtering on the
    // scalar would have read as untagged.
    final slugs = _slugs(
      pick('categorySlugs', 'category_slugs'),
      pick('categorySlug', 'category_slug'),
    );
    return HomeServiceCard(
      itemId: _str(pick('itemId', 'item_id')),
      serviceId: _nullableStr(pick('serviceId', 'service_id')),
      categoryId: _nullableStr(pick('categoryId', 'category_id')),
      categorySlug: slugs.isEmpty ? null : slugs.first,
      categorySlugs: slugs,
      isUrgentAvailable:
          pick('isUrgentAvailable', 'is_urgent_available') == true,
      rating: _price(json['rating']) ?? 0,
      ratingCount: _count(pick('ratingCount', 'rating_count')),
      titleEn: _str(pick('titleEn', 'title_en')),
      titleBn: _nullableStr(pick('titleBn', 'title_bn')),
      subtitleEn: _nullableStr(pick('subtitleEn', 'subtitle_en')),
      subtitleBn: _nullableStr(pick('subtitleBn', 'subtitle_bn')),
      price: _price(json['price']),
      priceTag: _nullableStr(pick('priceTag', 'price_tag')),
      badgeText: _nullableStr(pick('badgeText', 'badge_text')),
      imageUrl: _nullableStr(pick('imageUrl', 'image_url')),
    );
  }

  /// Projects a catalog service onto a card, mirroring the API's `fromCatalog`.
  ///
  /// Used only on the fallback path (`/api/home-data` unreachable), which is
  /// why the slug is resolved locally through [categorySlugFor] rather than
  /// read off the wire — and why the badge falls back to the canonical label:
  /// with no category documents loaded there is no admin-given pill name to
  /// use.
  factory HomeServiceCard.fromCatalog(ServiceCatalogItem item) {
    // The API resolves the pill set for its own responses; here it is rebuilt
    // client-side from whatever `/api/services` sent — the explicit slugs when
    // the backend supports them, and the legacy free-text fold when it doesn't.
    final slugs = item.categorySlugs.isNotEmpty
        ? item.categorySlugs
        : [
            if (categorySlugFor(item.category).isNotEmpty)
              categorySlugFor(item.category),
          ];
    return HomeServiceCard(
      itemId: 'svc_${item.id}',
      serviceId: item.id,
      categorySlug: slugs.isEmpty ? null : slugs.first,
      categorySlugs: slugs,
      isUrgentAvailable: item.isUrgentAvailable,
      rating: item.rating,
      ratingCount: item.ratingCount,
      titleEn: item.title,
      subtitleEn: item.description.isEmpty ? null : item.description,
      price: item.price,
      // Shown as stored, so an admin sees on Home exactly what they typed.
      badgeText: item.category.isEmpty ? null : item.category,
      imageUrl: item.imageUrl,
    );
  }

  static String _str(dynamic raw, {String fallback = ''}) {
    if (raw == null || raw is Map || raw is Iterable) return fallback;
    final s = raw.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static String? _nullableStr(dynamic raw) {
    final s = _str(raw);
    return s.isEmpty ? null : s;
  }

  /// The pill set, degrading to the scalar slug when the API predates the list.
  /// Duplicates and blanks are dropped so a filter never double-counts a card.
  static List<String> _slugs(dynamic raw, dynamic scalar) {
    if (raw is Iterable) {
      final out = <String>[];
      for (final entry in raw) {
        final s = _str(entry);
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
      if (out.isNotEmpty) return List.unmodifiable(out);
    }
    final single = _nullableStr(scalar);
    return single == null ? const [] : List.unmodifiable([single]);
  }

  /// Non-negative integer count; anything unparseable is 0 (= "unrated"),
  /// which reads as an absent rating rather than a broken one.
  static int _count(dynamic raw) {
    if (raw is num) {
      final n = raw.toInt();
      return n > 0 ? n : 0;
    }
    final parsed = int.tryParse(_str(raw)) ?? 0;
    return parsed > 0 ? parsed : 0;
  }

  /// Accepts the `Number` Mongo stores and the String a seed script or
  /// multipart round trip has been observed to leave behind ("1,200", "৳1200").
  static double? _price(dynamic raw) {
    double? parsed;
    if (raw is num) {
      parsed = raw.toDouble();
    } else if (raw is String) {
      parsed = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    }
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  @override
  List<Object?> get props => [
        itemId,
        serviceId,
        categoryId,
        categorySlug,
        categorySlugs,
        isUrgentAvailable,
        rating,
        ratingCount,
        titleEn,
        titleBn,
        subtitleEn,
        subtitleBn,
        price,
        priceTag,
        badgeText,
        imageUrl,
      ];
}
