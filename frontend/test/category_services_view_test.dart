// Renders the dedicated category view — the surface a patient lands on when
// they tap any pill other than "All".
//
// The point is not that a title appears. It is that:
//
//   1. The layout holds. This view is one full-height list mounted inside an
//      `AnimatedSwitcher` on Home, which can produce an unbounded-constraint
//      crash or a RenderFlex stripe that no model test would catch.
//   2. It shows ONLY the selected category's services. Leaking one card from
//      another pill is the whole bug this feature exists to avoid.
//   3. Nothing sits between the pills and the first card: the masthead and the
//      Price / Rating / Urgent row are gone, and they must stay gone.
//   4. An empty category always offers a way out. A filter rail with no exit
//      is a trap, and this is the screen where a patient can end up in one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/api/home_data_providers.dart';
import 'package:taafi/core/api/service_catalog_providers.dart';
import 'package:taafi/core/models/home_category.dart';
import 'package:taafi/core/models/home_service_card.dart';
import 'package:taafi/core/models/patient_home_data.dart';
import 'package:taafi/core/models/service_catalog_item.dart';
import 'package:taafi/features/patient/screens/widgets/care_service_card.dart';
import 'package:taafi/features/patient/screens/widgets/category_selection.dart';
import 'package:taafi/features/patient/screens/widgets/category_services_view.dart';

const _postOp = HomeCategory(
  id: 'c1',
  nameEn: 'Post-op',
  nameBn: 'অপারেশন পরবর্তী',
  slug: 'post-op',
  descriptionEn: 'Recovery care at home after surgery.',
);

const _doctorInHome = HomeCategory(
  id: 'c2',
  nameEn: 'Doctor in Home',
  slug: 'doctor-in-home',
);

const _cards = [
  HomeServiceCard(
    itemId: '1',
    serviceId: 's1',
    categorySlug: 'post-op',
    categorySlugs: ['post-op'],
    titleEn: 'Wound dressing',
    subtitleEn: 'Dressing changes and recovery checks by a nurse.',
    price: 900,
    badgeText: 'Post-op',
    rating: 4.8,
    ratingCount: 24,
  ),
  HomeServiceCard(
    itemId: '2',
    serviceId: 's2',
    categorySlug: 'post-op',
    categorySlugs: ['post-op'],
    titleEn: 'Physiotherapy session',
    price: 1800,
    badgeText: 'Post-op',
    isUrgentAvailable: true,
  ),
  // Assigned to both pills — it has to show under either.
  HomeServiceCard(
    itemId: '3',
    serviceId: 's3',
    categorySlug: 'post-op',
    categorySlugs: ['post-op', 'doctor-in-home'],
    titleEn: 'Post-op doctor review',
    price: 2500,
  ),
  // A different pill entirely: must never appear under Post-op.
  HomeServiceCard(
    itemId: '4',
    serviceId: 's4',
    categorySlug: 'doctor-in-home',
    categorySlugs: ['doctor-in-home'],
    titleEn: 'General home consultation',
    price: 1500,
  ),
];

Future<ProviderContainer> pumpCategoryView(
  WidgetTester tester, {
  String slug = 'post-op',
  List<HomeServiceCard> cards = _cards,
  CategoryFilters filters = CategoryFilters.none,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final data = PatientHomeData(
    categories: const [_postOp, _doctorInHome],
    careServices: CareServicesBlock(services: cards),
  );

  final container = ProviderContainer(
    overrides: [
      patientHomeDataProvider.overrideWith((ref) => Stream.value(data)),
      activeServicesProvider
          .overrideWith((ref) => Stream.value(const <ServiceCatalogItem>[])),
      selectedCategorySlugProvider.overrideWith((ref) => slug),
      categoryFiltersProvider.overrideWith((ref) => filters),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          // Mirrors how Home mounts it: a bounded box below the pinned rail.
          body: CategoryServicesView(categorySlug: slug),
        ),
      ),
    ),
  );
  await settle(tester);
  return container;
}

/// Advances past the 250 ms view transition without waiting for quiescence.
///
/// `pumpAndSettle` cannot be used here: [CareServiceCard] — which the wide
/// grid layout renders — runs a repeating shimmer sweep, so the tree never
/// goes idle and the pump times out. `care_service_card_test.dart` pumps fixed
/// frames for the same reason.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('shows only the selected category', (t) async {
    await pumpCategoryView(t);

    expect(find.text('Wound dressing'), findsOneWidget);
    expect(find.text('Physiotherapy session'), findsOneWidget);
    // Multi-assigned: belongs here too.
    expect(find.text('Post-op doctor review'), findsOneWidget);
    // Belongs to the other pill only — the leak this whole feature guards.
    expect(find.text('General home consultation'), findsNothing);
  });

  testWidgets('nothing sits between the pills and the first card', (t) async {
    await pumpCategoryView(t);

    // The masthead: bilingual title, the admin's blurb, the running count.
    expect(find.text('Post-op / অপারেশন পরবর্তী'), findsNothing);
    expect(find.text('Recovery care at home after surgery.'), findsNothing);
    expect(find.text('3 services available'), findsNothing);
    // The sub-filter row. "Urgent" is deliberately not asserted on — it is
    // also the capsule printed on every urgent-dispatchable card, so it is
    // still on screen for a legitimate reason.
    expect(find.text('Price'), findsNothing);
    expect(find.text('Rating'), findsNothing);

    // The first card is the first thing in the view.
    final firstCard = t.getTopLeft(find.text('Wound dressing'));
    expect(firstCard.dy, lessThan(100));
  });

  testWidgets('a second pill renders its own services', (t) async {
    await pumpCategoryView(t, slug: 'doctor-in-home');
    expect(find.text('Post-op doctor review'), findsOneWidget);
    expect(find.text('General home consultation'), findsOneWidget);
    expect(find.text('Wound dressing'), findsNothing);
  });

  // No control on this surface writes `categoryFiltersProvider` any more, but
  // the list still reads it — that is what keeps a deep link or a future
  // control from being silently ignored.
  testWidgets('a filter set from outside the UI still narrows the list',
      (t) async {
    await pumpCategoryView(
      t,
      filters: const CategoryFilters(urgentOnly: true),
    );

    expect(find.text('Physiotherapy session'), findsOneWidget);
    expect(find.text('Wound dressing'), findsNothing);
  });

  testWidgets('an empty category offers a way back to all services', (t) async {
    await pumpCategoryView(t, cards: const []);

    expect(find.text('No Post-op services yet'), findsOneWidget);
    expect(find.text('Reset to all services'), findsOneWidget);
  });

  testWidgets('"Reset to all services" returns to the All pill', (t) async {
    final container = await pumpCategoryView(t, cards: const []);

    await t.tap(find.text('Reset to all services'));
    await settle(t);

    expect(
      container.read(selectedCategorySlugProvider),
      HomeCategory.allSlug,
    );
  });

  // One case per viewport rather than a loop in one test: a RenderFlex
  // overflow is recorded against the test that caused it, and a loop would
  // report every size as the same failure.
  for (final size in const [
    Size(320, 640), // smallest phone still in the wild
    Size(390, 844), // the reference phone
    Size(834, 1112), // tablet — reflows into the grid
  ]) {
    testWidgets('lays out without overflow at ${size.width}x${size.height}',
        (t) async {
      await pumpCategoryView(t, size: size);
      expect(takeRenderException(), isNull);

      // Again with the empty state on screen: it is a different composition
      // (a centred card, not rows) and can overflow on its own.
      await pumpCategoryView(t, size: size, cards: const []);
      expect(takeRenderException(), isNull);
    });
  }
}

/// Surfaces a RenderFlex overflow (or any other render-phase throw) as a test
/// failure. `pumpWidget` swallows these into the pending-exception slot rather
/// than rethrowing, so an overflow stripe otherwise passes silently.
Object? takeRenderException() => TestWidgetsFlutterBinding.instance.takeException();
