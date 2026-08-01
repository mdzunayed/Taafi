// Covers the shared Care-Services card, which both the patient Home rail and
// the admin-driven dynamic sections render:
//   1. It survives its real footprints (240x260 rail slot, 181x260 three-column
//      tile) with hostile content — a very long title, description and price —
//      without a RenderFlex overflow.
//   2. The same holds at 2x text scale, proving the withClampedTextScaling
//      guard actually bounds the scrim column.
//   3. A missing / blank description collapses to zero height rather than
//      leaving a gap, and the price row still renders.
//   4. The CTA collapses to a circular arrow on narrow tiles and keeps its
//      label on wide ones.
//   5. Tapping the CTA fires onBook exactly once and does NOT also fire the
//      card's onTap — the gesture-arena contract that lets a button live
//      inside the card's InkWell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/features/patient/screens/widgets/care_service_card.dart';

const String _longTitle =
    'Post-operative wound dressing and recovery monitoring at home by a nurse';
const String _longDescription =
    'A certified nurse visits your home to clean and re-dress the surgical '
    'site, check vitals, review medication adherence, and escalate to the '
    'supervising doctor if anything looks wrong during recovery.';

Future<void> _pumpCard(
  WidgetTester tester, {
  required double width,
  double height = kCareServiceCardRailHeight,
  String title = _longTitle,
  String? description = _longDescription,
  String? priceLabel = '৳ 1,500',
  double textScale = 1.0,
  VoidCallback? onTap,
  VoidCallback? onBook,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: CareServiceCard(
                title: title,
                description: description,
                categoryLabel: 'Post-op',
                priceLabel: priceLabel,
                onTap: onTap ?? () {},
                onBook: onBook,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The card runs a repeating shimmer, so settle is never reached — pump a
  // couple of frames instead.
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('layout', () {
    testWidgets('no overflow in the 240px rail slot', (tester) async {
      await _pumpCard(tester, width: kCareServiceCardWidth);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow in the 181px three-column tile', (tester) async {
      await _pumpCard(tester, width: 181);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow in the 278px two-column tile', (tester) async {
      await _pumpCard(tester, width: 278);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 2x text scale', (tester) async {
      await _pumpCard(tester, width: 181, textScale: 2.0);
      expect(tester.takeException(), isNull);

      await _pumpCard(tester, width: kCareServiceCardWidth, textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('description', () {
    testWidgets('renders when present', (tester) async {
      await _pumpCard(
        tester,
        width: kCareServiceCardWidth,
        description: 'Short and sweet',
      );
      expect(find.text('Short and sweet'), findsOneWidget);
      expect(find.text('৳ 1,500'), findsOneWidget);
    });

    testWidgets('null and blank both collapse, price still renders',
        (tester) async {
      for (final d in [null, '', '   ']) {
        await _pumpCard(
          tester,
          width: kCareServiceCardWidth,
          title: 'Wound dressing',
          description: d,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('৳ 1,500'), findsOneWidget, reason: 'description: $d');
      }
    });
  });

  group('call to action', () {
    testWidgets('shows the label on a wide tile', (tester) async {
      await _pumpCard(tester, width: kCareServiceCardWidth);
      expect(find.text('Book Now'), findsOneWidget);
    });

    testWidgets('collapses to an icon on a narrow tile', (tester) async {
      await _pumpCard(tester, width: 181);
      expect(find.text('Book Now'), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });

    // The button is a bare GestureDetector nested inside PressableCard's
    // InkWell. Flutter's arena gives a descendant recognizer priority, so a
    // tap on the button must not also book through the card.
    testWidgets('fires onBook once and never onTap', (tester) async {
      var taps = 0;
      var books = 0;
      await _pumpCard(
        tester,
        width: kCareServiceCardWidth,
        onTap: () => taps++,
        onBook: () => books++,
      );

      await tester.tap(find.text('Book Now'));
      await tester.pump(const Duration(milliseconds: 16));

      expect(books, 1);
      expect(taps, 0);
    });

    testWidgets('tapping the card body fires onTap', (tester) async {
      var taps = 0;
      var books = 0;
      await _pumpCard(
        tester,
        width: kCareServiceCardWidth,
        title: 'Wound dressing',
        onTap: () => taps++,
        onBook: () => books++,
      );

      await tester.tap(find.text('Wound dressing'));
      await tester.pump(const Duration(milliseconds: 16));

      expect(taps, 1);
      expect(books, 0);
    });
  });

  group('geometry helpers', () {
    test('grid ratios land tiles on the rail height', () {
      // 600px column cap: (600 - 32 inset - 12 gap) / 2 = 278
      expect((278 / careServiceGridAspectRatio(2)).round(), 260);
      // (600 - 32 inset - 24 gaps) / 3 ~= 181
      expect((181 / careServiceGridAspectRatio(3)).round(), 259);
    });

    test('careServicePrice formats with a thousands separator', () {
      expect(careServicePrice(1500), '৳ 1,500');
      expect(careServicePrice(900), '৳ 900');
      expect(careServicePrice(2400.4), '৳ 2,400');
    });
  });
}
