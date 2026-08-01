// Covers the "link a home-section card to a service" target model:
//   1. A SERVICE item parses its id + populated snapshot and reports
//      linksToService, so the tap can prefill the booking form.
//   2. CUSTOM_ROUTE / EXTERNAL_URL / NONE keep their own fields.
//   3. Items written before target linking shipped (route string only, or a
//      backend default 'SERVICE' with no serviceId) re-derive their effective
//      target from `navigationRoute` — nothing regresses.
//   4. toJson emits the structured fields plus the legacy navigationRoute
//      mirror older app builds still navigate off.

import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/home_section.dart';

HomeSectionItem parseItem(Map<String, dynamic> json) =>
    HomeSectionItem.fromJson({
      'itemId': '1',
      'title': 'Orthopedic doctor for adults',
      'imageUrl': 'https://cdn/x.png',
      ...json,
    });

void main() {
  group('HomeSectionItem target parsing', () {
    test('SERVICE item carries its id and populated snapshot', () {
      final item = parseItem({
        'targetType': 'SERVICE',
        'serviceId': '65f000000000000000000001',
        'navigationRoute': 'service:65f000000000000000000001',
        'service': {
          'id': '65f000000000000000000001',
          'title': 'Orthopedic doctor for adults',
          'price': 800,
          'category': 'Doctor visit',
          'status': 'active',
        },
      });

      expect(item.targetType, HomeItemTargetType.service);
      expect(item.serviceId, '65f000000000000000000001');
      expect(item.linksToService, isTrue);
      expect(item.linkedService?.price, 800);
      expect(item.linkedService?.isActive, isTrue);
    });

    test('CUSTOM_ROUTE, EXTERNAL_URL and NONE keep their own target', () {
      final route = parseItem({
        'targetType': 'CUSTOM_ROUTE',
        'customRoute': 'activities:tracking',
        'navigationRoute': 'activities:tracking',
      });
      expect(route.targetType, HomeItemTargetType.customRoute);
      expect(route.customRoute, 'activities:tracking');
      expect(route.linksToService, isFalse);

      final url = parseItem({
        'targetType': 'EXTERNAL_URL',
        'customRoute': 'https://taafi.example/offer',
        'navigationRoute': 'https://taafi.example/offer',
      });
      expect(url.targetType, HomeItemTargetType.externalUrl);
      expect(url.customRoute, 'https://taafi.example/offer');

      final none = parseItem({'targetType': 'NONE'});
      expect(none.targetType, HomeItemTargetType.none);
      expect(none.serviceId, isNull);
    });

    test('legacy items with only navigationRoute infer their target', () {
      expect(
        parseItem({'navigationRoute': 'service:65f000000000000000000002'})
            .targetType,
        HomeItemTargetType.service,
      );
      expect(
        parseItem({'navigationRoute': 'activities:tracking'}).targetType,
        HomeItemTargetType.customRoute,
      );
      expect(
        parseItem({'navigationRoute': 'https://taafi.example'}).targetType,
        HomeItemTargetType.externalUrl,
      );
      expect(parseItem({}).targetType, HomeItemTargetType.none);
    });

    test(
        'a schema-default SERVICE with no serviceId falls back to the route '
        'string instead of dead-ending', () {
      final item = parseItem({
        'targetType': 'SERVICE',
        'serviceId': null,
        'navigationRoute': 'activities:medications',
      });
      expect(item.targetType, HomeItemTargetType.customRoute);
      expect(item.linksToService, isFalse);
    });
  });

  group('HomeSectionItem target serialization', () {
    test('emits structured fields plus the legacy navigationRoute mirror', () {
      final json = const HomeSectionItem(
        itemId: '1',
        title: 'Orthopedic doctor for adults',
        imageUrl: 'https://cdn/x.png',
        targetType: HomeItemTargetType.service,
        serviceId: '65f000000000000000000001',
        navigationRoute: 'service:65f000000000000000000001',
      ).toJson();

      expect(json['targetType'], 'SERVICE');
      expect(json['serviceId'], '65f000000000000000000001');
      expect(json['customRoute'], '');
      expect(json['navigationRoute'], 'service:65f000000000000000000001');
    });

    test('round-trips through a section without losing the link', () {
      final section = HomeSection(
        id: 'sec1',
        sectionKey: 'trending_doctors',
        titleEn: 'Trending doctors',
        uiTemplate: HomeSection.templateHorizontalProductCard,
        contentData: const [
          HomeSectionItem(
            itemId: '1',
            title: 'Orthopedic doctor for adults',
            imageUrl: 'https://cdn/x.png',
            priceTag: '৳800',
            targetType: HomeItemTargetType.service,
            serviceId: '65f000000000000000000001',
            navigationRoute: 'service:65f000000000000000000001',
          ),
        ],
      );

      final parsed = HomeSection.fromJson({
        'id': section.id,
        ...section.toJson(),
      });
      final item = parsed.contentData.single;
      expect(item.targetType, HomeItemTargetType.service);
      expect(item.serviceId, '65f000000000000000000001');
      expect(item.linksToService, isTrue);
    });
  });
}
