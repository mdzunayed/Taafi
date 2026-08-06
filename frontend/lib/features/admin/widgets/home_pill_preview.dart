import 'package:flutter/material.dart';

import '../../../core/models/home_category.dart';
import '../../patient/screens/widgets/category_filter_bar.dart';

/// Renders the patient Home chip rail inside the admin console, on the canvas
/// it will actually sit on.
///
/// The pills are the app's own [CategoryPill], not a CMS lookalike — the same
/// reasoning as the card preview in `admin_home_sections_page.dart`: an
/// approximation drifts from the shipped surface the moment either side moves,
/// and this preview exists precisely so an operator can trust what they see.
///
/// Two pieces of context have to be forced, because the admin console runs a
/// light Material theme and the patient Home is a dark surface:
///   * [Theme] with `Brightness.dark`, which is what `HomeDark.of` resolves
///     against, and
///   * the near-black canvas fill behind the row.
class HomePillPreview extends StatelessWidget {
  final List<HomeCategory> categories;

  /// Which pill renders in the active (filled brand-orange) state.
  final int selectedIndex;

  const HomePillPreview({
    super.key,
    required this.categories,
    this.selectedIndex = 0,
  });

  /// Matches the `_ItemCardPreview` canvas in the sections CMS, which
  /// approximates `HomeDark.canvas`.
  static const Color canvas = Color(0xFF0E0B1A);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: ThemeData(brightness: Brightness.dark),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(
                  height: kCategoryRailHeight,
                  child: CategoryPill(
                    category: categories[i],
                    active: i == selectedIndex,
                    // Preview only: taps are swallowed rather than dispatched.
                    onTap: () {},
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
