// Covers the dynamic Home chip rail and the adaptive Care Services layout:
//   1. The slug fold that joins a service's free-text `category` to an
//      admin-managed pill. It must keep folding legacy aliases ('Recovery' →
//      'post-op') while NOT erasing categories the compiled alias table has
//      never heard of — an admin can mint 'Nursing' at runtime, and the older
//      `normalizeServiceCategory` would have collapsed it to '' before it ever
//      matched a service.
//   2. The filter itself: "All" matches everything including untagged cards,
//      and an untagged card must not leak into some other pill.
//   3. `layoutType` wire mapping, including the fallback for a layout this app
//      version doesn't know — Care Services must degrade to the carousel it
//      has always rendered, never to an empty block.
//   4. `HomeServiceCard` parsing, which feeds the first screen every patient
//      sees and therefore coerces rather than casts.
//   5. Multi-pill membership (one service can be assigned to several
//      categories in the CMS) and `applyCategoryFilters` — no chip row drives
//      it on the category view any more, but its sort order still has to match
//      the API's `SORTS` table, or the same category would read differently
//      depending on which side sorted it.
//
// MIRROR: backend/tests/homeCategories.test.js pins the same join on the API
// side. Both copies exist because mobile builds are not force-updated and can
// talk to an un-migrated backend.

import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/home_category.dart';
import 'package:taafi/core/models/home_section.dart';
import 'package:taafi/core/models/home_service_card.dart';
import 'package:taafi/core/models/patient_home_data.dart';
import 'package:taafi/core/models/service_catalog_item.dart';
import 'package:taafi/core/models/service_category.dart';
import 'package:taafi/features/patient/screens/widgets/category_selection.dart';
import 'package:taafi/features/patient/screens/widgets/category_services_view.dart';

ServiceCatalogItem catalogItem({
  String id = 's1',
  String title = 'Doctor home visit',
  String category = '',
  double price = 1500,
  String description = '',
}) {
  final now = DateTime.now();
  return ServiceCatalogItem(
    id: id,
    title: title,
    price: price,
    description: description,
    category: category,
    createdAt: now,
    updatedAt: now,
  );
}

HomeServiceCard card({
  String itemId = 'c1',
  List<String> slugs = const [],
  double? price,
  bool urgent = false,
  double rating = 0,
  int ratingCount = 0,
}) {
  return HomeServiceCard(
    itemId: itemId,
    titleEn: itemId,
    categorySlug: slugs.isEmpty ? null : slugs.first,
    categorySlugs: slugs,
    price: price,
    isUrgentAvailable: urgent,
    rating: rating,
    ratingCount: ratingCount,
  );
}

void main() {
  group('categorySlugFor: joining a service to its pill', () {
    test('canonical labels slugify to kebab-case', () {
      expect(categorySlugFor('Post-op'), 'post-op');
      expect(categorySlugFor('Doctor in Home'), 'doctor-in-home');
    });

    test('legacy aliases still fold onto the canonical slug', () {
      // A row stored as 'Recovery' must keep matching the Post-op pill rather
      // than becoming its own orphan slug.
      expect(categorySlugFor('Recovery'), 'post-op');
      expect(categorySlugFor('physiotherapy'), 'post-op');
      expect(categorySlugFor('Consultation'), 'doctor-in-home');
    });

    test('an unrecognised category becomes its own slug, not nothing', () {
      expect(normalizeServiceCategory('Nursing'), '');
      expect(categorySlugFor('Nursing'), 'nursing');
      expect(categorySlugFor('Lab Collection'), 'lab-collection');
    });

    test('blank stays blank — uncategorized belongs to no pill', () {
      expect(categorySlugFor(''), '');
      expect(categorySlugFor('   '), '');
      expect(categorySlugFor(null), '');
    });

    test('case, spacing and punctuation collapse to one slug', () {
      for (final raw in ['Post-op', 'post op', 'POST_OP', '  Post  Op  ']) {
        expect(categorySlugFor(raw), 'post-op', reason: raw);
      }
    });
  });

  group('serviceMatchesCategorySlug', () {
    test('the All pill matches everything, including untagged cards', () {
      expect(serviceMatchesCategorySlug('nursing', HomeCategory.allSlug), isTrue);
      expect(serviceMatchesCategorySlug(null, HomeCategory.allSlug), isTrue);
      expect(serviceMatchesCategorySlug('', HomeCategory.allSlug), isTrue);
    });

    test('a real pill matches only its own slug', () {
      expect(serviceMatchesCategorySlug('nursing', 'nursing'), isTrue);
      expect(serviceMatchesCategorySlug('post-op', 'nursing'), isFalse);
    });

    test('an untagged card never leaks into another pill', () {
      expect(serviceMatchesCategorySlug(null, 'nursing'), isFalse);
      expect(serviceMatchesCategorySlug('', 'nursing'), isFalse);
    });
  });

  group('HomeCategory', () {
    test('the All pill is client-only and identifiable', () {
      expect(HomeCategory.all.isAll, isTrue);
      expect(HomeCategory.all.id, isEmpty);
      // Never sent to the server as a category.
      expect(HomeCategory.compiledFallback.any((c) => c.isAll), isFalse);
    });

    test('the All pill label is English alone', () {
      // The pill renders `nameBn` as a second line when it has one, and the
      // default pill is meant to stay a single short word.
      expect(HomeCategory.all.nameEn, 'All');
      expect(HomeCategory.all.nameBn, isNull);
    });

    test('parses the API camelCase shape', () {
      final c = HomeCategory.fromJson({
        'id': 'c1',
        'nameEn': 'Doctor in Home',
        'nameBn': 'হোম ডাক্তার',
        'slug': 'doctor-in-home',
        'iconUrl': 'https://cdn/doctor.png',
        'displayOrder': 2,
        'isActive': true,
      });
      expect(c.nameEn, 'Doctor in Home');
      expect(c.nameBn, 'হোম ডাক্তার');
      expect(c.slug, 'doctor-in-home');
      expect(c.displayOrder, 2);
    });

    test('also parses the published snake_case shape', () {
      final c = HomeCategory.fromJson({
        '_id': 'c1',
        'name_en': 'Doctor in Home',
        'name_bn': 'হোম ডাক্তার',
        'slug': 'doctor-in-home',
        'icon_url': 'https://cdn/doctor.png',
        'display_order': 2,
        'is_active': false,
      });
      expect(c.nameEn, 'Doctor in Home');
      expect(c.nameBn, 'হোম ডাক্তার');
      expect(c.iconUrl, 'https://cdn/doctor.png');
      expect(c.displayOrder, 2);
      expect(c.isActive, isFalse);
    });

    test('a category with no slug derives one rather than staying unmatchable',
        () {
      final c = HomeCategory.fromJson({'id': 'c1', 'nameEn': 'Home Nursing'});
      expect(c.slug, 'home-nursing');
    });
  });

  group('PatientHomeData.railCategories', () {
    test('hidden pills are dropped and the rest sort by displayOrder', () {
      final data = PatientHomeData(
        categories: [
          const HomeCategory(id: 'b', nameEn: 'B', slug: 'b', displayOrder: 2),
          const HomeCategory(id: 'a', nameEn: 'A', slug: 'a', displayOrder: 1),
          const HomeCategory(
              id: 'x', nameEn: 'X', slug: 'x', displayOrder: 0, isActive: false),
        ],
      );
      expect(data.railCategories.map((c) => c.slug), ['a', 'b']);
    });

    test('no live categories falls back to the compiled chips', () {
      // A deployment that has not run the seed migration must still show the
      // rail it had before, not a bare "All".
      expect(
        const PatientHomeData().railCategories.map((c) => c.slug),
        ['post-op', 'doctor-in-home'],
      );
    });
  });

  group('layoutType', () {
    test('round-trips the three known layouts', () {
      for (final l in HomeLayoutType.values) {
        expect(HomeLayoutTypeX.fromWire(l.wire), l);
      }
    });

    test('an unknown layout degrades to the carousel, not to nothing', () {
      expect(HomeLayoutTypeX.fromWire('MASONRY_3_COL'), HomeLayoutType.carousel);
      expect(HomeLayoutTypeX.fromWire(null), HomeLayoutType.carousel);
    });

    test('a section carries its layout through parse and serialize', () {
      final section = HomeSection.fromJson({
        'id': 's1',
        'sectionKey': 'CARE_SERVICES',
        'titleEn': 'Care services',
        'uiTemplate': 'HORIZONTAL_PRODUCT_CARD',
        'layoutType': 'GRID_2_COL',
      });
      expect(section.layoutType, HomeLayoutType.grid2Col);
      expect(section.isCareServices, isTrue);
      expect(section.toJson()['layoutType'], 'GRID_2_COL');
    });

    test('a section saved before layouts existed defaults to the carousel', () {
      final section = HomeSection.fromJson({
        'id': 's2',
        'sectionKey': 'trending',
        'titleEn': 'Trending',
        'uiTemplate': 'HORIZONTAL_PRODUCT_CARD',
      });
      expect(section.layoutType, HomeLayoutType.carousel);
      expect(section.isCareServices, isFalse);
    });
  });

  group('HomeSectionItem.categoryId', () {
    test('a flat id and a populated object both parse', () {
      final flat = HomeSectionItem.fromJson({
        'itemId': '1',
        'title': 'T',
        'imageUrl': 'https://cdn/x.png',
        'categoryId': 'c1',
        'categorySlug': 'nursing',
      });
      expect(flat.categoryId, 'c1');
      expect(flat.categorySlug, 'nursing');

      final populated = HomeSectionItem.fromJson({
        'itemId': '1',
        'title': 'T',
        'imageUrl': 'https://cdn/x.png',
        'categoryId': {'id': 'c1'},
        'category': {'slug': 'nursing'},
      });
      expect(populated.categoryId, 'c1');
      expect(populated.categorySlug, 'nursing');
    });

    test('the tag survives a save round trip', () {
      // The CMS saves sections back with a whole-array contentData replace, so
      // a dropped categoryId is silent data loss.
      final item = HomeSectionItem.fromJson({
        'itemId': '1',
        'title': 'T',
        'imageUrl': 'https://cdn/x.png',
        'categoryId': 'c1',
      });
      expect(item.toJson()['categoryId'], 'c1');
    });

    test('an untagged card parses as null, not as an empty string', () {
      final item = HomeSectionItem.fromJson({
        'itemId': '1',
        'title': 'T',
        'imageUrl': 'https://cdn/x.png',
      });
      expect(item.categoryId, isNull);
      expect(item.categorySlug, isNull);
    });
  });

  group('HomeServiceCard', () {
    test('parses the API card shape', () {
      final card = HomeServiceCard.fromJson({
        'itemId': 'svc_1',
        'serviceId': '1',
        'categoryId': 'c1',
        'categorySlug': 'doctor-in-home',
        'titleEn': 'Doctor home visit',
        'titleBn': 'হোম ডাক্তার',
        'subtitleEn': 'General consultation.',
        'price': 1500,
        'badgeText': 'Doctor in Home',
        'imageUrl': 'https://cdn/doctor.jpg',
      });
      expect(card.serviceId, '1');
      expect(card.categorySlug, 'doctor-in-home');
      expect(card.isBookable, isTrue);
      // Both scripts render at once — the app has no locale switch.
      expect(card.title, 'Doctor home visit\nহোম ডাক্তার');
      expect(card.priceLabel, '৳ 1,500');
    });

    test('a price stored as a string still renders', () {
      // Seed scripts and multipart round trips have both been observed to
      // leave a String behind where the schema says Number.
      expect(
        HomeServiceCard.fromJson({'itemId': 'x', 'titleEn': 'T', 'price': '1,200'})
            .priceLabel,
        '৳ 1,200',
      );
    });

    test('a non-numeric price tag passes through verbatim', () {
      final card = HomeServiceCard.fromJson({
        'itemId': 'x',
        'titleEn': 'T',
        'priceTag': 'Free',
      });
      expect(card.priceLabel, 'Free');
    });

    test('no price at all omits the line rather than printing zero', () {
      expect(
        HomeServiceCard.fromJson({'itemId': 'x', 'titleEn': 'T'}).priceLabel,
        isNull,
      );
    });

    test('a malformed card degrades instead of throwing', () {
      // One bad row must not abort the map and blank Care Services for
      // everyone — the same contract ServiceCatalogItem.fromJson holds.
      final card = HomeServiceCard.fromJson({
        'itemId': 42,
        'titleEn': {'nested': 'object'},
        'price': 'not a number',
      });
      expect(card.itemId, '42');
      expect(card.titleEn, isEmpty);
      expect(card.price, isNull);
    });

    test('the catalog fallback resolves the slug client-side', () {
      // This path runs when /api/home-data is unreachable, so nothing has
      // resolved the join for us.
      final card = HomeServiceCard.fromCatalog(
        catalogItem(id: 's9', category: 'Recovery', description: 'Wound care'),
      );
      expect(card.itemId, 'svc_s9');
      expect(card.serviceId, 's9');
      expect(card.categorySlug, 'post-op');
      expect(card.description, 'Wound care');
      expect(card.isBookable, isTrue);
    });

    test('an uncategorized service falls back to no badge and no slug', () {
      final card = HomeServiceCard.fromCatalog(catalogItem(category: ''));
      // Null, not '': that is what `fromJson` has always produced for an
      // untagged card, and the two constructors have to agree — a filter that
      // treated one as tagged-with-nothing and the other as untagged would
      // behave differently on the online and offline paths.
      expect(card.categorySlug, isNull);
      expect(card.categorySlugs, isEmpty);
      expect(card.badgeText, isNull);
      // Still visible under "All".
      expect(
        serviceMatchesCategorySlug(card.categorySlug, HomeCategory.allSlug),
        isTrue,
      );
    });
  });

  group('CareServicesBlock', () {
    test('parses the block and its cards', () {
      final block = CareServicesBlock.fromJson({
        'id': 's1',
        'titleEn': 'Care services',
        'titleBn': 'সেবা',
        'layoutType': 'LIST',
        'source': 'CURATED',
        'services': [
          {'itemId': 'a', 'titleEn': 'A', 'categorySlug': 'nursing'},
          {'itemId': 'b', 'titleEn': 'B'},
        ],
      });
      expect(block.layoutType, HomeLayoutType.list);
      expect(block.isCurated, isTrue);
      expect(block.services, hasLength(2));
    });

    test('an absent block defaults to the carousel and the catalog source', () {
      // What a backend with no CARE_SERVICES document sends.
      final block = CareServicesBlock.fromJson({'sectionKey': 'CARE_SERVICES'});
      expect(block.id, isNull);
      expect(block.layoutType, HomeLayoutType.carousel);
      expect(block.isCurated, isFalse);
      expect(block.titleEn, 'Care services');
    });
  });

  group('multi-pill membership', () {
    test('a card assigned to two pills matches both', () {
      // The CMS case this exists for: post-operative physiotherapy delivered by
      // a visiting doctor genuinely belongs on both tabs.
      final c = card(slugs: ['post-op', 'doctor-in-home']);
      expect(c.matchesCategorySlug('post-op'), isTrue);
      expect(c.matchesCategorySlug('doctor-in-home'), isTrue);
      expect(c.matchesCategorySlug('nursing'), isFalse);
      expect(c.matchesCategorySlug(HomeCategory.allSlug), isTrue);
    });

    test('an untagged card matches only All', () {
      final c = card();
      expect(c.matchesCategorySlug(HomeCategory.allSlug), isTrue);
      expect(c.matchesCategorySlug('post-op'), isFalse);
    });

    test('a payload predating the list still filters on the scalar slug', () {
      // An older backend sends `categorySlug` and no `categorySlugs`; the card
      // must keep filtering rather than silently falling out of every pill.
      final c = HomeServiceCard.fromJson({
        'itemId': 'old',
        'titleEn': 'Old',
        'categorySlug': 'post-op',
      });
      expect(c.categorySlugs, ['post-op']);
      expect(c.matchesCategorySlug('post-op'), isTrue);
      expect(c.matchesCategorySlug('nursing'), isFalse);
    });

    test('duplicate slugs on the wire collapse to one', () {
      final c = HomeServiceCard.fromJson({
        'itemId': 'dup',
        'titleEn': 'Dup',
        'categorySlugs': ['post-op', 'post-op', '', 'nursing'],
      });
      expect(c.categorySlugs, ['post-op', 'nursing']);
      expect(c.categorySlug, 'post-op');
    });

    test('rating and urgency survive the wire, and default to unrated', () {
      final rated = HomeServiceCard.fromJson({
        'itemId': 'r',
        'titleEn': 'R',
        'rating': 4.6,
        'ratingCount': 12,
        'isUrgentAvailable': true,
      });
      expect(rated.ratingLabel, '4.6');
      expect(rated.isUrgentAvailable, isTrue);

      final bare = HomeServiceCard.fromJson({'itemId': 'b', 'titleEn': 'B'});
      // No stars at all rather than a hollow "0.0" — nobody has rated it.
      expect(bare.ratingLabel, isNull);
      expect(bare.isUrgentAvailable, isFalse);
    });
  });

  group('applyCategoryFilters', () {
    final cards = [
      card(itemId: 'mid', price: 1500, rating: 4.9, ratingCount: 3),
      card(itemId: 'cheap', price: 500, urgent: true, rating: 4.2, ratingCount: 90),
      card(itemId: 'free'), // no price at all
      card(itemId: 'dear', price: 3000, urgent: true, rating: 4.9, ratingCount: 40),
    ];

    test('recommended leaves the admin order untouched', () {
      final out = applyCategoryFilters(cards, CategoryFilters.none);
      expect(out.map((c) => c.itemId), ['mid', 'cheap', 'free', 'dear']);
    });

    test('price sorts ascending and puts priceless cards last', () {
      final out = applyCategoryFilters(
        cards,
        const CategoryFilters(sort: CategorySort.priceAsc),
      );
      // 'free' has no numeric price, so it must not masquerade as ৳0 and win.
      expect(out.map((c) => c.itemId), ['cheap', 'mid', 'dear', 'free']);
    });

    test('rating breaks ties on review volume, then price', () {
      final out = applyCategoryFilters(
        cards,
        const CategoryFilters(sort: CategorySort.topRated),
      );
      // 4.9(40 reviews) beats 4.9(3), and the unrated card sorts last.
      expect(out.map((c) => c.itemId), ['dear', 'mid', 'cheap', 'free']);
    });

    test('urgent-only narrows without reordering', () {
      final out = applyCategoryFilters(
        cards,
        const CategoryFilters(urgentOnly: true),
      );
      expect(out.map((c) => c.itemId), ['cheap', 'dear']);
    });

    test('filters compose, and the source list is never mutated', () {
      final out = applyCategoryFilters(
        cards,
        const CategoryFilters(sort: CategorySort.priceAsc, urgentOnly: true),
      );
      expect(out.map((c) => c.itemId), ['cheap', 'dear']);
      // The caller holds the category-matched list and re-filters it on every
      // chip tap; sorting it in place would corrupt the admin's order.
      expect(cards.map((c) => c.itemId), ['mid', 'cheap', 'free', 'dear']);
    });

    test('isActive tells the empty state which exit to offer', () {
      expect(CategoryFilters.none.isActive, isFalse);
      expect(const CategoryFilters(urgentOnly: true).isActive, isTrue);
      expect(
        const CategoryFilters(sort: CategorySort.topRated).isActive,
        isTrue,
      );
    });
  });

  group('PatientHomeData.categoryBySlug', () {
    final data = PatientHomeData(
      categories: const [
        HomeCategory(id: '1', nameEn: 'Post-op', slug: 'post-op'),
        HomeCategory(
          id: '2',
          nameEn: 'Doctor in Home',
          slug: 'doctor-in-home',
          descriptionEn: 'Licensed doctors visiting your home.',
        ),
        HomeCategory(id: '3', nameEn: 'Hidden', slug: 'hidden', isActive: false),
      ],
    );

    test('resolves an active pill with its blurb', () {
      final c = data.categoryBySlug('doctor-in-home');
      expect(c?.nameEn, 'Doctor in Home');
      expect(c?.descriptionEn, 'Licensed doctors visiting your home.');
    });

    test('"All" and a hidden or unknown pill resolve to null', () {
      // Null is the signal to fall back to the full Home view rather than
      // stranding the patient on a header for a category that is gone.
      expect(data.categoryBySlug(HomeCategory.allSlug), isNull);
      expect(data.categoryBySlug('hidden'), isNull);
      expect(data.categoryBySlug('nope'), isNull);
    });
  });
}
