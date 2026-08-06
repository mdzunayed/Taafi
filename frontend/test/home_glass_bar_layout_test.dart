// Pins the geometry behind the Home header's "RenderFlex overflowed by 1.00
// pixels on the bottom".
//
// The header is a fixed-height box: `PatientHomeScreen` has to know how tall
// the glass bar is *before* layout, because the scroll body's top padding is
// computed from it. That makes every dp of the bar an arithmetic agreement
// between three places — the reserved slot, the rail that fills it, and the
// hairline that insets it — and an off-by-one anywhere clips the rail.
//
// Two ways that agreement broke, both covered here:
//
//   1. The hairline. It lives in the bar's `BoxDecoration`, and a decoration
//      border insets its child, so the bar has to add it back on top of the
//      content height. It did not, so the `Column` was handed 123 dp for 124
//      dp of children — the reported 1.00 px, exactly.
//   2. Text scale. Both rows are text-driven and the heights were pinned at
//      60/46, so a patient with larger system type got the same clipping at a
//      larger magnitude. The rail is now handed a scaled height by Home, which
//      is why `CategoryFilterBar` takes one at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/api/home_data_providers.dart';
import 'package:taafi/core/models/home_category.dart';
import 'package:taafi/core/models/patient_home_data.dart';
import 'package:taafi/features/patient/screens/widgets/category_filter_bar.dart';

const _kGlassBarBorder = 1.0;
const _kRailGap = 8.0;
const _kRailBottomPad = 10.0;
const _kHeaderContent = 60.0;

/// The bar's real recipe: status-bar padding, a fixed height, and a hairline
/// in the decoration. Mirrors `_GlassTopBar`, which is private.
///
/// [countBorderInHeight] is the fix under test. The hairline is always drawn —
/// that is the design — the question is only whether the box was sized to
/// carry it.
Widget _glassBar({
  required double topInset,
  required double contentHeight,
  required bool countBorderInHeight,
  required Widget child,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: EdgeInsets.only(top: topInset),
        height: topInset +
            contentHeight +
            (countBorderInHeight ? _kGlassBarBorder : 0),
        decoration: const BoxDecoration(
          color: Color(0xFF0D151C),
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF283040),
              width: _kGlassBarBorder,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    ),
  );
}

/// The bar's `Column`, stripped to its geometry.
///
/// The two rows have to actually paint: `RenderFlex` reports its overflow from
/// the paint pass, so a stand-in built from empty `SizedBox`es sails through a
/// constraint it does not fit and the test proves nothing.
Widget _barContent({required double railHeight, required double headerHeight}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: headerHeight,
        width: 200,
        child: const ColoredBox(color: Color(0xFF161C28)),
      ),
      const SizedBox(height: _kRailGap),
      SizedBox(
        height: railHeight,
        width: 200,
        child: const ColoredBox(color: Color(0xFF1E2536)),
      ),
      const SizedBox(height: _kRailBottomPad),
    ],
  );
}

HomeCategory _category({String nameEn = 'Nursing', String? nameBn}) {
  return HomeCategory(
    id: 'c1',
    nameEn: nameEn,
    nameBn: nameBn,
    slug: 'nursing',
    displayOrder: 1,
  );
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('glass bar height accounts for its own hairline', () {
    testWidgets('a bar that forgets the border overflows by exactly 1 px',
        (tester) async {
      // The pre-fix arithmetic, reproduced: the container is sized to the
      // content alone, and the decoration border takes a dp back out of it.
      const content =
          _kHeaderContent + _kRailGap + kCategoryRailHeight + _kRailBottomPad;

      await tester.pumpWidget(_host(_glassBar(
        topInset: 24,
        contentHeight: content,
        countBorderInHeight: false, // the bug: the box ignores its own line
        child: _barContent(
          railHeight: kCategoryRailHeight,
          headerHeight: _kHeaderContent,
        ),
      )));

      // Guards the guard: if this ever stops overflowing, the test below is
      // no longer proving anything.
      final error = tester.takeException();
      expect(error, isFlutterError);
      expect('$error', contains('overflowed by 1.0'));
    });

    testWidgets('adding the hairline to the height clears it', (tester) async {
      const content =
          _kHeaderContent + _kRailGap + kCategoryRailHeight + _kRailBottomPad;

      await tester.pumpWidget(_host(_glassBar(
        topInset: 24,
        contentHeight: content,
        countBorderInHeight: true, // the fix
        child: _barContent(
          railHeight: kCategoryRailHeight,
          headerHeight: _kHeaderContent,
        ),
      )));

      expect(tester.takeException(), isNull);
    });

    testWidgets('and still clears it at the largest supported text scale',
        (tester) async {
      // Home clamps at 1.3; the bar and the rail scale together from the same
      // factor, so the sum has to keep fitting.
      const scale = 1.3;
      const content = _kHeaderContent * scale +
          _kRailGap +
          kCategoryRailHeight * scale +
          _kRailBottomPad;

      await tester.pumpWidget(_host(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: _glassBar(
          topInset: 24,
          contentHeight: content,
          countBorderInHeight: true,
          child: _barContent(
            railHeight: kCategoryRailHeight * scale,
            headerHeight: _kHeaderContent * scale,
          ),
        ),
      )));

      expect(tester.takeException(), isNull);
    });
  });

  group('the rail fills exactly the slot the header reserved', () {
    testWidgets('CategoryFilterBar honours a scaled height override',
        (tester) async {
      const scaled = kCategoryRailHeight * 1.3;

      // Held in the loading state on purpose — the reserved height has to
      // hold before any category data lands, or the header reflows on first
      // paint. Overridden rather than left to the real provider, which would
      // reach for Dio and leave a pending timer.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientHomeDataProvider.overrideWith(
              (ref) => const Stream<PatientHomeData>.empty(),
            ),
          ],
          child: _host(const CategoryFilterBar(height: scaled)),
        ),
      );
      await tester.pump();

      final rail = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(CategoryFilterBar),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(rail.height, scaled);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a two-line Bengali pill fits the default rail',
        (tester) async {
      await tester.pumpWidget(_host(Center(
        child: SizedBox(
          height: kCategoryRailHeight,
          child: CategoryPill(
            category: _category(nameBn: 'নার্সিং সেবা'),
            active: true,
            onTap: () {},
          ),
        ),
      )));

      expect(tester.takeException(), isNull);
    });

    testWidgets('and fits the scaled rail at the largest supported scale',
        (tester) async {
      const scale = 1.3;
      await tester.pumpWidget(_host(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Center(
          child: SizedBox(
            height: kCategoryRailHeight * scale,
            child: CategoryPill(
              category: _category(nameBn: 'নার্সিং সেবা'),
              active: false,
              onTap: () {},
            ),
          ),
        ),
      )));

      expect(tester.takeException(), isNull);
    });
  });
}
