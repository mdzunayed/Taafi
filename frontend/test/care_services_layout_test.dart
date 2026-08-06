// Renders the adaptive Care Services layout engine in all three formats.
//
// The point is not that a title appears — it is that each arrangement lays out
// without a RenderFlex overflow. All three share one card family but impose
// very different constraints on it (a 240px rail cell, a ~158px grid tile on a
// narrow phone, a 108px-tall full-width row), and an overflow in any of them
// is a red-and-yellow stripe across a patient's home screen that no unit test
// on the models would catch.
//
// Also pins the carousel→grid reflow breakpoint: an admin who picks CAROUSEL
// is choosing the phone layout, and on a desktop-width window the engine is
// expected to reflow rather than render a 240px strip in a 1400px viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/home_section.dart';
import 'package:taafi/core/models/home_service_card.dart';
import 'package:taafi/features/patient/screens/widgets/care_service_card.dart';
import 'package:taafi/features/patient/screens/widgets/care_services_section.dart';

const _cards = [
  HomeServiceCard(
    itemId: '1',
    serviceId: 's1',
    categorySlug: 'doctor-in-home',
    titleEn: 'Doctor home visit',
    subtitleEn: 'General consultation by a licensed doctor at your home.',
    price: 1500,
    badgeText: 'Doctor in Home',
  ),
  HomeServiceCard(
    itemId: '2',
    serviceId: 's2',
    categorySlug: 'post-op',
    titleEn: 'Post-op wound care',
    titleBn: 'অপারেশন পরবর্তী সেবা',
    subtitleEn: 'Dressing changes and recovery checks by a nurse.',
    price: 900,
    badgeText: 'Post-op',
  ),
  HomeServiceCard(
    itemId: '3',
    titleEn: 'Lab sample collection',
    priceTag: 'Free',
  ),
];

/// Pumps the engine at an explicit viewport, inside the scrolling column the
/// real Home screen provides.
Future<void> pumpEngine(
  WidgetTester tester,
  HomeLayoutType layout, {
  Size size = const Size(390, 844),
  ValueChanged<HomeServiceCard>? onTap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            LayoutEngine(
              layoutType: layout,
              cards: _cards,
              onTap: onTap ?? (_) {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final layout in HomeLayoutType.values) {
    testWidgets('${layout.wire} renders every card without overflowing',
        (tester) async {
      await pumpEngine(tester, layout);
      expect(tester.takeException(), isNull);

      // The carousel is a lazy horizontal ListView, so cards past the viewport
      // edge aren't built yet — scrolling to each is the honest check that the
      // rail carries them, and it exercises the layout under real constraints
      // rather than only the first cell.
      final scrollable = layout == HomeLayoutType.carousel
          ? find.byType(Scrollable).last
          : null;

      for (final card in _cards) {
        final finder = find.textContaining(card.titleEn);
        if (scrollable != null) {
          await tester.scrollUntilVisible(
            finder,
            200,
            scrollable: scrollable,
          );
        }
        expect(
          finder,
          findsOneWidget,
          reason: '${layout.wire} dropped "${card.titleEn}"',
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('a bilingual title renders both scripts', (tester) async {
    // There is no app-wide locale switch, so the Bengali line shows alongside
    // the English one rather than replacing it.
    await pumpEngine(tester, HomeLayoutType.list);
    expect(find.textContaining('অপারেশন পরবর্তী সেবা'), findsOneWidget);
  });

  testWidgets('prices render, including a non-numeric tag', (tester) async {
    await pumpEngine(tester, HomeLayoutType.list);
    expect(find.text('৳ 1,500'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('CAROUSEL is a horizontal rail on a phone', (tester) async {
    await pumpEngine(tester, HomeLayoutType.carousel);

    final rail = tester.widget<ListView>(
      find.descendant(
        of: find.byType(LayoutEngine),
        matching: find.byType(ListView),
      ),
    );
    expect(rail.scrollDirection, Axis.horizontal);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('CAROUSEL reflows into a grid on a desktop-width window',
      (tester) async {
    await pumpEngine(
      tester,
      HomeLayoutType.carousel,
      size: const Size(1400, 900),
    );

    expect(find.byType(GridView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GRID_2_COL stays two columns even on a wide window',
      (tester) async {
    // Unlike the carousel, an explicit 2-column choice is honoured at every
    // width — the layout is named after its column count.
    await pumpEngine(
      tester,
      HomeLayoutType.grid2Col,
      size: const Size(1400, 900),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('a narrow phone still lays the grid out cleanly', (tester) async {
    // The regression this guards: a fixed aspect ratio tuned for the 600px-
    // capped column squashes tiles at 320px and the card overflows.
    await pumpEngine(
      tester,
      HomeLayoutType.grid2Col,
      size: const Size(320, 720),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a card reports the card that was tapped',
      (tester) async {
    HomeServiceCard? tapped;
    await pumpEngine(
      tester,
      HomeLayoutType.list,
      onTap: (card) => tapped = card,
    );

    await tester.tap(find.textContaining('Doctor home visit'));
    await tester.pump();
    expect(tapped?.serviceId, 's1');
  });

  testWidgets('the Book Now action fires independently of the card body',
      (tester) async {
    // The button is a descendant recognizer inside the card's InkWell; a tap
    // on it must not also fire the card.
    var taps = 0;
    await pumpEngine(
      tester,
      HomeLayoutType.list,
      onTap: (_) => taps++,
    );

    await tester.tap(find.byType(CareServiceBookButton).first);
    await tester.pump();
    expect(taps, 1);
  });
}
