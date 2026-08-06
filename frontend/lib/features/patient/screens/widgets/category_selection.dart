/// Which pill the Home screen is showing, and the sub-filters that apply
/// *inside* a pill once one is selected.
///
/// Split out of `category_filter_bar.dart` so the rail, the Care Services
/// block, and the dedicated category view can all reach this state without any
/// of them importing each other. The bar re-exports this library, so existing
/// `import 'category_filter_bar.dart';` call sites are unaffected.
library;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/home_category.dart';

/// The active filter pill, as a category **slug** — [HomeCategory.allSlug]
/// while unfiltered.
///
/// A slug rather than the display label it used to hold: labels are now
/// admin-editable and translatable, so renaming "Post-op" to "Post-operative
/// care" in the CMS would have silently emptied the filter of anyone with that
/// chip selected. Slugs are the join key and don't move.
///
/// Write it through [selectCategory], never directly — see that function for
/// why the sub-filters have to move with it.
final selectedCategorySlugProvider =
    StateProvider<String>((ref) => HomeCategory.allSlug);

/// Ordering for the dedicated category listing.
///
/// `recommended` is the catalog's own order (what the unfiltered rail has
/// always shown) and is deliberately the default: an admin curates that order,
/// and opening a category should not silently override them.
enum CategorySort {
  recommended,
  priceAsc,
  topRated;

  /// The chip label. Short enough to sit three-across on a small phone.
  String get label => switch (this) {
        CategorySort.recommended => 'Recommended',
        CategorySort.priceAsc => 'Price',
        CategorySort.topRated => 'Rating',
      };

  /// The wire value `GET /api/services/by-category?sort=` accepts, so the
  /// client and the server can never disagree on what "Price" means.
  String get wireValue => switch (this) {
        CategorySort.recommended => 'recommended',
        CategorySort.priceAsc => 'price_asc',
        CategorySort.topRated => 'rating',
      };
}

/// How the dedicated category listing is ordered and narrowed: one active sort
/// plus the urgent toggle.
///
/// No control on the category view writes this any more — the Price / Rating /
/// Urgent chip row was removed so the cards start directly under the pills — so
/// it sits at [none] in the app today. It is kept as the client mirror of
/// `GET /api/services/by-category`'s `sort=` / `urgentOnly=` query, which the
/// CMS preview and any future control both speak.
@immutable
class CategoryFilters extends Equatable {
  final CategorySort sort;

  /// Narrows the list to services an admin flagged as urgent-dispatchable.
  final bool urgentOnly;

  const CategoryFilters({
    this.sort = CategorySort.recommended,
    this.urgentOnly = false,
  });

  static const CategoryFilters none = CategoryFilters();

  /// True when anything is narrowing or reordering the list — drives whether
  /// the empty state offers "clear filters" or "back to all services".
  bool get isActive => sort != CategorySort.recommended || urgentOnly;

  CategoryFilters copyWith({CategorySort? sort, bool? urgentOnly}) =>
      CategoryFilters(
        sort: sort ?? this.sort,
        urgentOnly: urgentOnly ?? this.urgentOnly,
      );

  @override
  List<Object?> get props => [sort, urgentOnly];
}

final categoryFiltersProvider =
    StateProvider<CategoryFilters>((ref) => CategoryFilters.none);

/// Switches the active pill, resetting [categoryFiltersProvider].
///
/// The reset is the whole point of routing every caller through here. Filters
/// are scoped to the category on screen — "Urgent available" under Post-op is a
/// different question from the same toggle under Lab tests — and carrying a
/// `urgentOnly` from one pill to the next lands the patient in an empty list
/// they never asked for and can't see the cause of. That matters more now than
/// it did with the chip row on screen: there is no longer a visible control
/// showing that a filter is on.
void selectCategory(WidgetRef ref, String slug) {
  final current = ref.read(selectedCategorySlugProvider);
  if (current == slug) return;
  ref.read(selectedCategorySlugProvider.notifier).state = slug;
  ref.read(categoryFiltersProvider.notifier).state = CategoryFilters.none;
}

/// Back to the unfiltered Home view — the "Reset to All Services" action, and
/// the safety net the rail uses when a selected pill disappears from the CMS.
void resetToAllCategories(WidgetRef ref) =>
    selectCategory(ref, HomeCategory.allSlug);
