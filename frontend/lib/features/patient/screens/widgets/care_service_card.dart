import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/mt_text_styles.dart';
import 'care_card_primitives.dart';
import 'patient_home_palette.dart';

/// Fixed card footprint on the mobile Care-Services rail.
const double kCareServiceCardWidth = 240;
const double kCareServiceCardRailHeight = 260;

/// Tile proportions for the wide (web/desktop) grid, so the cells land on the
/// same 260px height the rail uses.
///
/// The home column is capped at 600px, so once the window clears ~632px the
/// tile widths are fixed: 278px at two columns, 181px at three. These ratios
/// are those widths over 260.
double careServiceGridAspectRatio(int cols) => cols == 3 ? 0.70 : 1.07;

final NumberFormat _moneyFmt = NumberFormat('#,###', 'en_US');

/// Price as it appears on a card, e.g. `৳ 1,500`.
String careServicePrice(num amount) => '৳ ${_moneyFmt.format(amount.round())}';

/// Below this tile width the CTA collapses to a circular arrow. At the
/// three-column width (181px) the labelled pill and the price together
/// overrun the row.
const double _compactCtaBelow = 190;

/// The Care-Services card: a full-bleed photo with a bottom scrim carrying the
/// title, description, price, and a Book Now action, plus the category badge
/// floating top-left.
///
/// Takes plain strings and callbacks rather than a model, because the two call
/// sites render different ones — `ServiceCatalogItem` from the catalog API and
/// `HomeSectionItem` from the admin-driven sections feed. Sharing the widget is
/// only possible at this altitude, and not sharing it is what produced the
/// duplicate card this replaced.
class CareServiceCard extends StatefulWidget {
  final String title;

  /// One or two lines under the title. Null/blank contributes zero height, so
  /// a service with no description keeps the same silhouette as one with.
  final String? description;

  /// Raw or canonical — the card normalizes it to pick the badge accent.
  /// Null/blank hides the badge.
  final String? categoryLabel;

  /// Pre-formatted; see [careServicePrice]. Null hides the price.
  final String? priceLabel;

  final String? imageUrl;

  /// Tapping anywhere on the card body.
  final VoidCallback onTap;

  /// The Book Now button. Defaults to [onTap].
  final VoidCallback? onBook;

  final String bookLabel;

  /// Admin overrides from the SDUI section styles; all null ⇒ theme defaults.
  final Color? cardColor;
  final Color? glowColor;
  final Color? badgeColor;
  final Color? badgeTextColor;
  final Color? ctaColor;

  const CareServiceCard({
    super.key,
    required this.title,
    required this.onTap,
    this.description,
    this.categoryLabel,
    this.priceLabel,
    this.imageUrl,
    this.onBook,
    this.bookLabel = 'Book Now',
    this.cardColor,
    this.glowColor,
    this.badgeColor,
    this.badgeTextColor,
    this.ctaColor,
  });

  @override
  State<CareServiceCard> createState() => _CareServiceCardState();
}

class _CareServiceCardState extends State<CareServiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: CareCardShimmerSweep.cycle,
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = (widget.categoryLabel ?? '').trim();
    final description = (widget.description ?? '').trim();
    final price = widget.priceLabel;
    final onBook = widget.onBook ?? widget.onTap;

    return Semantics(
      container: true,
      label: [
        widget.title,
        if (category.isNotEmpty) category,
        ?price,
      ].join(', '),
      child: PressableCard(
        onTap: widget.onTap,
        cardColor: widget.cardColor,
        glowColor: widget.glowColor,
        // Accessibility text scaling is the one thing that can still burst the
        // scrim column; clamp it rather than letting the card overflow.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CareCardImage(
                url: widget.imageUrl,
                fallbackIcon: serviceIconFor(category, widget.title),
              ),
              CareCardShimmerSweep(animation: _shimmer),
              _Scrim(
                title: widget.title,
                description: description,
                priceLabel: price,
                bookLabel: widget.bookLabel,
                ctaColor: widget.ctaColor,
                onBook: onBook,
              ),
              if (category.isNotEmpty)
                Positioned(
                  left: 12,
                  top: 12,
                  child: CareCardCategoryBadge(
                    label: category,
                    accent: ServiceCategoryTheme.accentFor(context, category),
                    background: widget.badgeColor,
                    textColor: widget.badgeTextColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom text panel. A dark gradient rather than a themed surface: the
/// text sits directly on a photo, so it is white in both light and dark mode,
/// and `hd.canvas` under the light theme is near-white — white-on-white.
class _Scrim extends StatelessWidget {
  final String title;
  final String description;
  final String? priceLabel;
  final String bookLabel;
  final Color? ctaColor;
  final VoidCallback onBook;

  const _Scrim({
    required this.title,
    required this.description,
    required this.priceLabel,
    required this.bookLabel,
    required this.ctaColor,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        // The generous top pad gives the gradient room to fade in rather than
        // starting as a hard edge across the photo.
        padding: const EdgeInsets.fromLTRB(14, 26, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.90),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MtTextStyles.labelLg.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MtTextStyles.bodySm.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.25,
                ),
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  if (priceLabel != null)
                    Expanded(
                      child: Text(
                        priceLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Tabular figures so prices line up down a rail.
                        style: MtTextStyles.timer.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  CareServiceBookButton(
                    label: bookLabel,
                    color: ctaColor,
                    compact: constraints.maxWidth < _compactCtaBelow,
                    onTap: onBook,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The teal Book Now affordance. Presses **independently** of the card: it is a
/// bare [GestureDetector] nested inside [PressableCard]'s [InkWell], and in
/// Flutter's gesture arena a descendant recognizer beats an ancestor's — so a
/// tap here fires the button only, never the button and the card both.
class CareServiceBookButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;

  /// Collapses to a circular arrow, for tiles too narrow for the label.
  final bool compact;

  /// Admin accent override; null ⇒ theme `hd.teal`.
  final Color? color;

  const CareServiceBookButton({
    super.key,
    required this.onTap,
    this.label = 'Book Now',
    this.compact = false,
    this.color,
  });

  @override
  State<CareServiceBookButton> createState() => _CareServiceBookButtonState();
}

class _CareServiceBookButtonState extends State<CareServiceBookButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  Animation<double> _scale = const AlwaysStoppedAnimation(1.0);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    _scale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    _press
      ..duration = const Duration(milliseconds: 110)
      ..reset()
      ..forward();
  }

  void _up() {
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _press, curve: Curves.elasticOut),
    );
    _press
      ..duration = const Duration(milliseconds: 400)
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final accent = widget.color ?? hd.teal;

    // Solid, not the old translucent disc — the button now sits on a photo
    // scrim where a tinted fill reads as smudge rather than affordance.
    final decoration = BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.38),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );

    final Widget body = widget.compact
        ? Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: decoration,
            child: const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Colors.white,
            ),
          )
        : Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: MtTextStyles.labelMd.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ],
            ),
          );

    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.compact ? widget.label : '',
        child: GestureDetector(
          onTapDown: _down,
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _press,
            builder: (context, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: body,
          ),
        ),
      ),
    );
  }
}
