// Covers the canonical service-category vocabulary that the patient Home
// filter rail runs on:
//   1. normalizeServiceCategory folds case / whitespace / punctuation variants
//      of both canonical labels onto the exact stored strings.
//   2. The legacy vocabulary the database accumulated while `category` was
//      free text ('Recovery', 'Consultation', 'Diagnostics', …) maps onto the
//      new labels, or to '' when it belongs to neither.
//   3. The chip rail is exactly three chips — a regression guard on the whole
//      point of the change.
//   4. serviceMatchesCategoryChip is an exact match on the normalized
//      category and NOT a substring search over the title, which is what the
//      old alias table did.

import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/models/service_catalog_item.dart';
import 'package:taafi/core/models/service_category.dart';

ServiceCatalogItem _item({
  String title = 'Some service',
  String category = '',
}) {
  final now = DateTime(2026, 1, 1);
  return ServiceCatalogItem(
    id: 'svc_1',
    title: title,
    price: 1500,
    category: category,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('normalizeServiceCategory — canonical variants', () {
    test('folds case, spacing and punctuation onto Post-op', () {
      for (final raw in [
        'Post-op',
        'post-op',
        'POST OP',
        '  post_op ',
        'postop',
        'Post  Op',
        'Post-Op',
      ]) {
        expect(normalizeServiceCategory(raw), kServiceCategoryPostOp,
            reason: 'input: "$raw"');
      }
    });

    test('folds case, spacing and punctuation onto Doctor in Home', () {
      for (final raw in [
        'Doctor in Home',
        'doctor in home',
        'Doctor-In-Home',
        'DOCTOR_IN_HOME',
        '  doctor  in  home  ',
      ]) {
        expect(normalizeServiceCategory(raw), kServiceCategoryDoctorInHome,
            reason: 'input: "$raw"');
      }
    });
  });

  group('normalizeServiceCategory — legacy vocabulary', () {
    test('maps the pre-migration categories that have a home', () {
      expect(normalizeServiceCategory('Recovery'), kServiceCategoryPostOp);
      expect(
          normalizeServiceCategory('Rehabilitation'), kServiceCategoryPostOp);
      expect(normalizeServiceCategory('post-surgery'), kServiceCategoryPostOp);
      expect(normalizeServiceCategory('Consultation'),
          kServiceCategoryDoctorInHome);
      expect(normalizeServiceCategory('home visit'),
          kServiceCategoryDoctorInHome);
      expect(normalizeServiceCategory('Doctor At Home'),
          kServiceCategoryDoctorInHome);
    });

    test('clears the ones that belong to neither category', () {
      for (final raw in ['Nursing', 'Diagnostics', 'Vitals', 'Lab Test']) {
        expect(normalizeServiceCategory(raw), '', reason: 'input: "$raw"');
      }
    });

    test('treats null, empty and blank as uncategorized', () {
      expect(normalizeServiceCategory(null), '');
      expect(normalizeServiceCategory(''), '');
      expect(normalizeServiceCategory('   '), '');
    });
  });

  group('chip rail', () {
    test('is exactly All / Post-op / Doctor in Home', () {
      expect(kPatientCategoryChips, hasLength(3));
      expect(kPatientCategoryChips, [
        kServiceCategoryAll,
        kServiceCategoryPostOp,
        kServiceCategoryDoctorInHome,
      ]);
    });

    test('kServiceCategories excludes the All sentinel', () {
      expect(kServiceCategories, isNot(contains(kServiceCategoryAll)));
      expect(kServiceCategories, hasLength(2));
    });
  });

  group('serviceMatchesCategoryChip', () {
    test('All matches everything, including uncategorized', () {
      expect(
        serviceMatchesCategoryChip(_item(category: ''), kServiceCategoryAll),
        isTrue,
      );
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'Post-op'), kServiceCategoryAll),
        isTrue,
      );
    });

    test('matches on the normalized category, not the raw string', () {
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'Recovery'), kServiceCategoryPostOp),
        isTrue,
      );
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'consultation'), kServiceCategoryDoctorInHome),
        isTrue,
      );
    });

    test('the two categories do not cross-match', () {
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'Post-op'), kServiceCategoryDoctorInHome),
        isFalse,
      );
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'Doctor in Home'), kServiceCategoryPostOp),
        isFalse,
      );
    });

    test('uncategorized services match no category chip', () {
      expect(
        serviceMatchesCategoryChip(_item(category: ''), kServiceCategoryPostOp),
        isFalse,
      );
      expect(
        serviceMatchesCategoryChip(
            _item(category: 'Diagnostics'), kServiceCategoryPostOp),
        isFalse,
      );
    });

    // The old implementation matched against '${item.category} ${item.title}',
    // so "Post-op wound care" landed under Post-op purely on its name. The
    // title is no longer consulted at all.
    test('does not fall back to a substring search over the title', () {
      final item = _item(title: 'Post-op wound dressing', category: '');
      expect(
        serviceMatchesCategoryChip(item, kServiceCategoryPostOp),
        isFalse,
      );
    });
  });
}
