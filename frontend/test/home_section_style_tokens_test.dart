// Covers the dynamic-color theming tokens added to the SDUI home sections:
//   1. hexToColor parses valid hex, rejects malformed/blank/null.
//   2. HomeSection JSON round-trips the nested styleTokens/cardStyles.
//   3. The token value classes resolve the right Light/Dark color per theme
//      and fall back (null) when a token is unset.
//   4. An all-null token object collapses to null on parse (treated as "no
//      override") so unstyled sections behave exactly as before.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/home_section.dart';
import 'package:taafi/core/theme/hex_color.dart';

void main() {
  group('hexToColor', () {
    test('parses #RGB, #RRGGBB, RRGGBB and #AARRGGBB', () {
      expect(hexToColor('#FFFFFF'), const Color(0xFFFFFFFF));
      expect(hexToColor('0284C7'), const Color(0xFF0284C7));
      expect(hexToColor('#8038BDF8'), const Color(0x8038BDF8));
      expect(hexToColor('#abc'), const Color(0xFFAABBCC)); // shorthand
    });

    test('returns null for blank, null and malformed input', () {
      expect(hexToColor(null), isNull);
      expect(hexToColor(''), isNull);
      expect(hexToColor('   '), isNull);
      expect(hexToColor('#12'), isNull);
      expect(hexToColor('not-a-color'), isNull);
    });
  });

  group('CardStyleTokens', () {
    const tokens = CardStyleTokens(
      cardBgLight: '#FFFFFF',
      cardBgDark: '#1E293B',
      accentColorLight: '#0284C7',
      accentColorDark: '#38BDF8',
      tagBgColor: '#F1F5F9',
      tagTextColor: '#475569',
    );

    test('resolves the correct color per brightness', () {
      expect(tokens.cardBg(false), const Color(0xFFFFFFFF));
      expect(tokens.cardBg(true), const Color(0xFF1E293B));
      expect(tokens.accent(false), const Color(0xFF0284C7));
      expect(tokens.accent(true), const Color(0xFF38BDF8));
      expect(tokens.tagBg, const Color(0xFFF1F5F9));
      expect(tokens.tagText, const Color(0xFF475569));
    });

    test('null tokens resolve to null so the renderer falls back', () {
      const empty = CardStyleTokens();
      expect(empty.isEmpty, isTrue);
      expect(empty.cardBg(true), isNull);
      expect(empty.accent(false), isNull);
      expect(empty.tagBg, isNull);
    });
  });

  group('HomeSection JSON round-trip', () {
    test('serializes and parses nested style tokens', () {
      const section = HomeSection(
        id: 'abc',
        sectionKey: 'trending',
        titleEn: 'Trending',
        uiTemplate: HomeSection.templateHorizontalProductCard,
        styleTokens: SectionStyleTokens(
          titleColorLight: '#0F172A',
          titleColorDark: '#F8FAFC',
          sectionBackgroundColor: '#EEF2FF',
        ),
        contentData: [
          HomeSectionItem(
            itemId: '1',
            title: 'Card',
            imageUrl: 'https://x/y.png',
            cardStyles: CardStyleTokens(
              cardBgLight: '#FFFFFF',
              accentColorDark: '#38BDF8',
            ),
          ),
        ],
      );

      final parsed = HomeSection.fromJson(section.toJson());

      expect(parsed.styleTokens?.titleColorLight, '#0F172A');
      expect(parsed.styleTokens?.title(true), const Color(0xFFF8FAFC));
      expect(parsed.styleTokens?.background, const Color(0xFFEEF2FF));
      expect(parsed.contentData.single.cardStyles?.cardBgLight, '#FFFFFF');
      expect(parsed.contentData.single.cardStyles?.accent(true),
          const Color(0xFF38BDF8));
      expect(parsed.contentData.single.cardStyles?.accent(false), isNull);
    });

    test('omits tokens when unset; all-null input collapses to null', () {
      const plain = HomeSection(
        id: 'abc',
        sectionKey: 'plain',
        titleEn: 'Plain',
        uiTemplate: HomeSection.templateGrid2x2Tiles,
        contentData: [
          HomeSectionItem(itemId: '1', title: 'A', imageUrl: 'u'),
        ],
      );
      // Nothing serialized for styleTokens/cardStyles when unset.
      expect(plain.toJson().containsKey('styleTokens'), isFalse);
      expect(
        (plain.toJson()['contentData'] as List).single,
        isNot(contains('cardStyles')),
      );

      // A server payload of all-null tokens is treated as "no override".
      final parsed = HomeSection.fromJson({
        'id': 'abc',
        'sectionKey': 'plain',
        'titleEn': 'Plain',
        'uiTemplate': HomeSection.templateGrid2x2Tiles,
        'styleTokens': {
          'titleColorLight': null,
          'titleColorDark': null,
          'sectionBackgroundColor': null,
        },
        'contentData': [
          {
            'itemId': '1',
            'title': 'A',
            'imageUrl': 'u',
            'cardStyles': {'cardBgLight': null, 'tagBgColor': ''},
          },
        ],
      });
      expect(parsed.styleTokens, isNull);
      expect(parsed.contentData.single.cardStyles, isNull);
    });
  });
}
