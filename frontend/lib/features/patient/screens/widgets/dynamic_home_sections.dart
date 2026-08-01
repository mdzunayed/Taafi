import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/home_section_providers.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../navigation/dynamic_route_dispatcher.dart';
import 'patient_home_palette.dart';

/// Server-driven section blocks rendered on the patient Home below the fixed
/// Banners + Care Services blocks.
///
/// Both horizontal templates (`HORIZONTAL_ROUND_AVATAR`,
/// `HORIZONTAL_PRODUCT_CARD`) render through the same premium rail —
/// [_DynamicCardRail] — a visual clone of the Care Services section: the same
/// flush-edge 190px horizontal list, radius-24 card with violet glow, category
/// capsule, price typography, teal "+" button, and press micro-animations.
/// The grid and wide-banner templates keep their layouts but share the
/// identical design tokens via [_PressableCard].
///
/// Sections whose template this app version doesn't know, or with no content,
/// are skipped — and while the list is loading or errored the whole block
/// collapses (like `_PromoCarousel`).
class DynamicHomeSections extends ConsumerWidget {
  const DynamicHomeSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(activeHomeSectionsProvider);
    return sectionsAsync.maybeWhen(
      data: (sections) {
        final renderable = sections
            .where((s) =>
                s.isActive &&
                s.contentData.isNotEmpty &&
                HomeSection.supportedTemplates.contains(s.uiTemplate))
            .toList();
        if (renderable.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in renderable) _SectionBlock(section: section),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

final _dynamicMoneyFmt = NumberFormat('#,###', 'en_US');

/// Turns the freeform admin `priceTag` into the Care-Services price line.
/// Numeric content (e.g. "৳2400", "2400") → `from ৳2,400`, matching
/// `_patientMoney` in patient_home_screen.dart; non-numeric text (e.g.
/// "Free") passes through verbatim; blank → null (line omitted).
String? _dynamicPriceLine(String? tag) {
  final raw = tag?.trim();
  if (raw == null || raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final n = int.tryParse(digits);
  if (n == null) return raw;
  return 'from ৳${_dynamicMoneyFmt.format(n)}';
}

/// Header + template body + bottom gap for one section. The 24 px bottom gap
/// matches the spacing rhythm of the fixed blocks above.
class _SectionBlock extends ConsumerWidget {
  final HomeSection section;
  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Admin overrides fall back to the theme token when unset.
    final titleColor = section.styleTokens?.title(dark) ?? hd.body;
    final sectionBg = section.styleTokens?.background;
    // Structured target (service link / route / URL) configured by the admin
    // in the CMS — a SERVICE item opens the booking flow pre-selected.
    void onItemTap(HomeSectionItem item) => dispatchHomeItemTarget(ref, item);

    final Widget body;
    switch (section.uiTemplate) {
      // Both horizontal templates unify onto the Care-Services-style rail.
      case HomeSection.templateHorizontalRoundAvatar:
      case HomeSection.templateHorizontalProductCard:
        body = _DynamicCardRail(
          items: section.contentData,
          onItemTap: onItemTap,
        );
      case HomeSection.templateGrid2x2Tiles:
        body = _Grid2x2Tiles(
          items: section.contentData,
          onItemTap: onItemTap,
        );
      case HomeSection.templateSingleWideBanner:
        body = _SingleWideBanner(
          item: section.contentData.first,
          onItemTap: onItemTap,
        );
      default:
        return const SizedBox.shrink();
    }

    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                section.titleEn.toUpperCase(),
                style: MtTextStyles.sectionLabel.copyWith(
                  color: titleColor,
                  letterSpacing: 1.0,
                ),
              ),
              if (section.titleBn != null && section.titleBn!.isNotEmpty)
                Text(
                  section.titleBn!,
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: hd.muted,
                    fontFamily: 'Kalpurush',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        body,
        const SizedBox(height: 24),
      ],
    );

    // An admin section background paints a full-width band behind the block.
    return sectionBg != null ? ColoredBox(color: sectionBg, child: block) : block;
  }
}

// --- Shared Care-Services design primitives ---------------------------------
// Visual replicas of the private widgets in patient_home_screen.dart
// (_AnimatedCareServiceCard and friends) — keep constants in sync with the
// source of truth there.

/// The Care-Services card shell: radius-24 surface with a violet glow that
/// dims while pressed, plus the press-spring micro-animation (squash to 0.96
/// on touch-down in 120ms/easeOut, elastic spring-back in 450ms/elasticOut).
/// One place for the spring constants — used by the unified card, the grid
/// tiles, and the wide banner.
class _PressableCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  /// Admin card-background override; null ⇒ theme `hd.surface`.
  final Color? cardColor;

  /// Admin accent override recoloring the drop-shadow glow; null ⇒ `hd.violet`.
  final Color? glowColor;

  const _PressableCard({
    required this.onTap,
    required this.child,
    this.cardColor,
    this.glowColor,
  });

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  Animation<double> _scale = const AlwaysStoppedAnimation(1.0);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    _press
      ..duration = const Duration(milliseconds: 120)
      ..reset()
      ..forward();
  }

  void _onTapRelease() {
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _press, curve: Curves.elasticOut),
    );
    _press
      ..duration = const Duration(milliseconds: 450)
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final glow = widget.glowColor ?? hd.violet;
    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final scale = _scale.value;
        // 0 (released) .. 1 (fully pressed) — dims the glow on press.
        final pressed = ((1.0 - scale) / 0.04).clamp(0.0, 1.0).toDouble();
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.30 * (1 - pressed)),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: widget.cardColor ?? hd.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: hd.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTapDown: _onTapDown,
            onTapCancel: _onTapRelease,
            onTap: () {
              _onTapRelease();
              widget.onTap();
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Perpetual, gentle shimmer sweep across the card's image header.
class _ShimmerSweep extends StatelessWidget {
  final Animation<double> animation;
  const _ShimmerSweep({required this.animation});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Sweep only during the first ~45% of the cycle, rest off-screen.
          final t = const Interval(0.0, 0.45, curve: Curves.easeInOut)
              .transform(animation.value);
          return FractionalTranslation(
            translation: Offset(-1.0 + 2.0 * t, 0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x1AFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.35, 0.5, 0.65],
                ),
              ),
              child: SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

/// Violet-gradient image placeholder/error treatment, matching
/// `_ServiceHeaderFallback`. Placeholder passes no icon; error shows one.
class _DynamicHeaderFallback extends StatelessWidget {
  final IconData? icon;
  const _DynamicHeaderFallback({this.icon});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hd.violet2, hd.violetDeep],
        ),
      ),
      child: icon == null
          ? const SizedBox.expand()
          : Center(child: Icon(icon, color: Colors.white, size: 40)),
    );
  }
}

/// Semi-translucent capsule label overlaid on the card image (top-left),
/// matching the Care-Services category tag.
class _CategoryCapsule extends StatelessWidget {
  final String label;

  /// Admin tag overrides; null ⇒ the translucent-canvas capsule + white text.
  final Color? tagBg;
  final Color? tagText;

  const _CategoryCapsule(this.label, {this.tagBg, this.tagText});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tagBg ?? hd.canvas.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: MtTextStyles.labelSm.copyWith(
          color: tagText ?? Colors.white,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// The teal "+" action button, replica of `_AddServiceButton`. Kept separate
/// from [_PressableCard] — its spring constants and gesture shape differ, and
/// its own GestureDetector wins the arena over the card's InkWell.
class _DynamicAddButton extends StatefulWidget {
  final VoidCallback onTap;

  /// Admin accent override; null ⇒ theme `hd.teal`.
  final Color? accent;
  const _DynamicAddButton({required this.onTap, this.accent});

  @override
  State<_DynamicAddButton> createState() => _DynamicAddButtonState();
}

class _DynamicAddButtonState extends State<_DynamicAddButton>
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
    final accent = widget.accent ?? hd.teal;
    return GestureDetector(
      onTapDown: _down,
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 1),
          ),
          child: Icon(Icons.add_rounded, color: accent, size: 20),
        ),
      ),
    );
  }
}

// --- The unified card + rail -------------------------------------------------

/// One dynamic-section item rendered as an exact visual clone of the
/// Care-Services card: image top (flex 5) with shimmer + capsule tag, text
/// bottom (flex 4) with title, price line, and the teal "+" button. Card tap
/// and "+" tap fire the same action — dynamic items carry a single route.
class _DynamicCareServiceCard extends StatefulWidget {
  final String title;
  final String? categoryTag;
  final String? priceLine;
  final String imageUrl;
  final VoidCallback onTap;
  final CardStyleTokens? styles;

  const _DynamicCareServiceCard({
    required this.title,
    required this.categoryTag,
    required this.priceLine,
    required this.imageUrl,
    required this.onTap,
    this.styles,
  });

  @override
  State<_DynamicCareServiceCard> createState() =>
      _DynamicCareServiceCardState();
}

class _DynamicCareServiceCardState extends State<_DynamicCareServiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final styles = widget.styles;
    final accent = styles?.accent(dark);
    return _PressableCard(
      onTap: widget.onTap,
      cardColor: styles?.cardBg(dark),
      glowColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.imageUrl.isEmpty)
                    const _DynamicHeaderFallback(icon: Icons.image_outlined)
                  else
                    CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const _DynamicHeaderFallback(),
                      errorWidget: (_, _, _) => const _DynamicHeaderFallback(
                          icon: Icons.image_outlined),
                    ),
                  _ShimmerSweep(animation: _shimmer),
                  if (widget.categoryTag != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _CategoryCapsule(
                        widget.categoryTag!,
                        tagBg: styles?.tagBg,
                        tagText: styles?.tagText,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              MtTextStyles.labelLg.copyWith(color: hd.title),
                        ),
                        if (widget.priceLine != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.priceLine!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MtTextStyles.timer.copyWith(
                              color: hd.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _DynamicAddButton(onTap: widget.onTap, accent: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The unified horizontal rail — a clone of `_ServicesCarousel` /
/// `_ServicesFluidGrid`: on mobile a flush-edge 190px horizontal list (the
/// 16px inset lives inside the ListView so the first card rests on the
/// section-header line and cards clip flush to the screen edge mid-swipe),
/// on wide layouts (≥700px) the same fluid grid the Care Services section
/// switches to.
class _DynamicCardRail extends StatelessWidget {
  /// Fixed card footprint on the rail — keep in sync with
  /// `_ServicesCarousel._railCardWidth` in patient_home_screen.dart.
  static const double _railCardWidth = 220;

  final List<HomeSectionItem> items;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _DynamicCardRail({required this.items, required this.onItemTap});

  Widget _card(HomeSectionItem item) {
    final subtitle = item.subtitle?.trim();
    return _DynamicCareServiceCard(
      title: item.title,
      categoryTag:
          (subtitle != null && subtitle.isNotEmpty) ? subtitle : null,
      priceLine: _dynamicPriceLine(item.priceTag),
      imageUrl: item.imageUrl,
      onTap: () => onItemTap(item),
      styles: item.cardStyles,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 700) {
      final cols = width >= 1000 ? 3 : 2;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 3 ? 0.95 : 1.30,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _card(items[i]),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: _railCardWidth,
          child: _card(items[i]),
        ),
      ),
    );
  }
}

// --- Grid + banner templates (layouts kept, tokens unified) ------------------

/// Full-bleed section image with the shared gradient placeholder/error
/// treatment. Used by the grid and banner templates (the rail card handles
/// its own image half).
class _SectionImage extends StatelessWidget {
  final String url;
  const _SectionImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const _DynamicHeaderFallback(icon: Icons.image_outlined);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => const _DynamicHeaderFallback(),
      errorWidget: (_, _, _) =>
          const _DynamicHeaderFallback(icon: Icons.image_outlined),
    );
  }
}

/// GRID_2X2_TILES — inset two-column grid of image tiles. Same geometry as
/// before, restyled onto [_PressableCard] (radius 24, violet glow, press
/// spring) with the subtitle promoted to the standard category capsule.
class _Grid2x2Tiles extends StatelessWidget {
  final List<HomeSectionItem> items;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _Grid2x2Tiles({required this.items, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          for (final item in items)
            _PressableCard(
              onTap: () => onItemTap(item),
              cardColor: item.cardStyles?.cardBg(dark),
              glowColor: item.cardStyles?.accent(dark),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SectionImage(url: item.imageUrl),
                  if (item.subtitle != null &&
                      item.subtitle!.trim().isNotEmpty)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _CategoryCapsule(
                        item.subtitle!.trim(),
                        tagBg: item.cardStyles?.tagBg,
                        tagText: item.cardStyles?.tagText,
                      ),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// SINGLE_WIDE_BANNER — one inset full-width promotional image (first item
/// only). Same layout as before, restyled onto [_PressableCard] with the
/// subtitle promoted to the category capsule and an optional price line.
class _SingleWideBanner extends StatelessWidget {
  final HomeSectionItem item;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _SingleWideBanner({required this.item, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final priceLine = _dynamicPriceLine(item.priceTag);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 140,
        child: _PressableCard(
          onTap: () => onItemTap(item),
          cardColor: item.cardStyles?.cardBg(dark),
          glowColor: item.cardStyles?.accent(dark),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _SectionImage(url: item.imageUrl),
              if (item.subtitle != null && item.subtitle!.trim().isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  child: _CategoryCapsule(
                    item.subtitle!.trim(),
                    tagBg: item.cardStyles?.tagBg,
                    tagText: item.cardStyles?.tagText,
                  ),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.h3.copyWith(color: Colors.white),
                      ),
                      if (priceLine != null)
                        Text(
                          priceLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MtTextStyles.timer.copyWith(
                            color: Colors.white70,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
