// Covers the per-card CMS fields added to home-section content items:
//   1. `badgeText` owns the floating capsule, but a card saved before that
//      field existed still shows its `subtitle` there — the upgrade must not
//      silently blank out every legacy badge.
//   2. `subtitle` is only promoted to a description line once `badgeText` has
//      taken over the capsule, so it is never rendered twice.
//   3. `isActive` defaults to true, so a backend predating per-card visibility
//      never hides a card by omission.
//   4. Bengali counterparts render beneath their English text (the app has no
//      locale switch), and blank BN values collapse rather than leaving a
//      trailing newline.
//   5. The new fields survive a JSON round trip — the CMS saves sections back
//      with a whole-array `contentData` replace, so a dropped field is a
//      silent data loss.

import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/home_section.dart';
import 'package:taafi/features/patient/screens/widgets/care_card_primitives.dart';
import 'package:taafi/features/patient/screens/widgets/dynamic_home_sections.dart';

HomeSectionItem parseItem(Map<String, dynamic> json) =>
    HomeSectionItem.fromJson({
      'itemId': '1',
      'title': 'Post-surgery care',
      'imageUrl': 'https://cdn/x.png',
      ...json,
    });

void main() {
  group('badge vs subtitle', () {
    test('an explicit badgeText owns the capsule', () {
      final item = parseItem({
        'subtitle': 'Post-op wound care & monitoring',
        'badgeText': 'Popular',
      });

      expect(item.badgeLabel, 'Popular');
    });

    test('a legacy card with no badgeText keeps its subtitle as the badge', () {
      final item = parseItem({'subtitle': 'Nursing'});

      expect(item.badgeLabel, 'Nursing');
      // Not also shown as a description — that would duplicate it on the card.
      expect(item.descriptionLine, isNull);
    });

    test('subtitle becomes the description once badgeText takes the capsule', () {
      final item = parseItem({
        'subtitle': 'Post-op wound care & monitoring',
        'badgeText': 'Popular',
      });

      expect(item.descriptionLine, 'Post-op wound care & monitoring');
    });

    test('blank strings collapse to no badge at all', () {
      final item = parseItem({'subtitle': '   ', 'badgeText': ''});

      expect(item.badgeLabel, isNull);
      expect(item.descriptionLine, isNull);
    });
  });

  group('per-card visibility', () {
    test('isActive defaults to true when the backend omits it', () {
      expect(parseItem({}).isActive, isTrue);
    });

    test('an explicitly hidden card reports false', () {
      expect(parseItem({'isActive': false}).isActive, isFalse);
    });
  });

  group('bilingual composition', () {
    test('a Bengali title renders under the English one', () {
      final item = parseItem({
        'title': 'Post-surgery care',
        'titleBn': 'পোস্ট-সার্জারি কেয়ার',
      });

      expect(dynamicCardTitle(item), 'Post-surgery care\nপোস্ট-সার্জারি কেয়ার');
    });

    test('no Bengali title leaves the English one untouched', () {
      expect(dynamicCardTitle(parseItem({'title': 'Nursing'})), 'Nursing');
    });

    test('a blank Bengali title adds no trailing newline', () {
      final item = parseItem({'title': 'Nursing', 'titleBn': '  '});

      expect(dynamicCardTitle(item), 'Nursing');
    });

    test('the description pairs both subtitles when a badge is set', () {
      final item = parseItem({
        'subtitle': 'Post-op wound care',
        'subtitleBn': 'অপারেশন পরবর্তী সেবা',
        'badgeText': 'Popular',
      });

      expect(
        dynamicCardDescription(item),
        'Post-op wound care\nঅপারেশন পরবর্তী সেবা',
      );
    });

    test('a legacy card shows no description even with a Bengali subtitle', () {
      // `subtitle` is still the badge here, so promoting only its Bengali
      // counterpart would strand an unpaired line under the title.
      final item = parseItem({
        'subtitle': 'Nursing',
        'subtitleBn': 'নার্সিং',
      });

      expect(item.descriptionLine, isNull);
      expect(dynamicCardDescription(item), 'নার্সিং');
    });
  });

  group('icon format routing', () {
    test('an SVG icon is routed to the vector branch', () {
      // A raster decoder renders nothing for these, so misrouting an SVG shows
      // the fallback tile instead of the admin's icon.
      expect(isSvgUrl('https://cdn.taafi.app/icons/post-op.svg'), isTrue);
      expect(isSvgUrl('https://cdn.taafi.app/icons/POST-OP.SVG'), isTrue);
    });

    test('a cache-buster query does not hide the extension', () {
      expect(isSvgUrl('https://cdn.taafi.app/icons/post-op.svg?v=2'), isTrue);
    });

    test('raster icons stay on the cached-image branch', () {
      expect(isSvgUrl('https://cdn.taafi.app/icons/post-op.png'), isFalse);
      expect(isSvgUrl('https://cdn.taafi.app/icons/post-op.jpg?x=.svg'), isFalse);
    });
  });

  test('the new fields survive a JSON round trip', () {
    final item = parseItem({
      'subtitle': 'Post-op wound care',
      'titleBn': 'পোস্ট-সার্জারি কেয়ার',
      'subtitleBn': 'অপারেশন পরবর্তী সেবা',
      'badgeText': 'Popular',
      'isActive': false,
      'priceTag': '৳2400',
    });

    final round = HomeSectionItem.fromJson(item.toJson());

    expect(round.titleBn, 'পোস্ট-সার্জারি কেয়ার');
    expect(round.subtitleBn, 'অপারেশন পরবর্তী সেবা');
    expect(round.badgeText, 'Popular');
    expect(round.isActive, isFalse);
    expect(round, item);
  });
}
