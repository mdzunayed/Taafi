import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/models/service_category.dart';
import '../../../../core/theme/mt_text_styles.dart';
import 'patient_home_palette.dart';

/// Shared building blocks for every Care-Services-styled card on the patient
/// Home surface.
///
/// These used to exist twice — once privately in `patient_home_screen.dart`
/// and once again in `dynamic_home_sections.dart`, whose header carried a
/// standing instruction to "keep constants in sync with the source of truth
/// there". Two copies of a press spring and a shimmer interval is exactly the
/// kind of thing that drifts, and the two rails render one below the other on
/// the same screen, so any drift is immediately visible. This file is now the
/// single source.
///
/// Everything here is model-agnostic (plain strings + callbacks) because the
/// two call sites render different models: `ServiceCatalogItem` from the
/// catalog API, and `HomeSectionItem` from the admin-driven SDUI feed.

/// Corner radius shared by the card shell and everything clipped inside it.
const double kCareCardRadius = 24;

/// Resolves the accent colour that identifies a service category.
///
/// Deliberately narrow: only the canonical categories get a colour. Anything
/// else — including a legacy value still sitting in the database mid-migration
/// — renders neutral rather than borrowing a brand colour it doesn't own.
abstract final class ServiceCategoryTheme {
  /// Accent for [category], or `null` when it has none.
  ///
  /// [category] may be raw; it is normalized here.
  ///
  /// Note what is *not* used: `hd.accent` (brand orange) is reserved for the
  /// active nav item and the active filter chip, and `hd.teal` is the
  /// book/quick-add affordance — see the token docs in
  /// [patient_home_palette.dart]. Spending either one on a category badge
  /// would blunt both signals.
  static Color? accentFor(BuildContext context, String? category) {
    final hd = HomeDark.of(context);
    switch (normalizeServiceCategory(category)) {
      case kServiceCategoryPostOp:
        return hd.violet2; // brand violet — the core care journey
      case kServiceCategoryDoctorInHome:
        return hd.indigo; // already the "someone is coming to you" colour
      default:
        return null;
    }
  }
}

/// Picks a fallback glyph for a card with no photo, from the service's
/// category and title keywords.
///
/// Intentionally tolerant where [serviceMatchesCategoryChip] is strict: this
/// only decides which icon decorates an image-less card, so a loose keyword
/// hit is a better outcome than the generic medical bag. It has no bearing on
/// filtering.
IconData serviceIconFor(String? category, String? title) {
  final h = '${category ?? ''} ${title ?? ''}'.toLowerCase();
  bool has(List<String> ks) => ks.any(h.contains);
  if (has(['wound', 'dressing', 'surgery', 'post-op', 'post op', 'postop'])) {
    return Icons.healing_rounded;
  }
  if (has(['doctor', 'physician', 'consult', 'home visit'])) {
    return Icons.house_rounded;
  }
  if (has(['vitals', 'vital', 'monitor', 'checkup', 'check-up', 'check up'])) {
    return Icons.monitor_heart_rounded;
  }
  if (has(['lab', 'laboratory', 'sample', 'diagnostic', 'test'])) {
    return Icons.science_rounded;
  }
  if (has(['elderly', 'senior', 'geriatric', 'aged'])) {
    return Icons.elderly_rounded;
  }
  if (has(['nursing', 'nurse'])) return Icons.vaccines_rounded;
  return Icons.medical_services_rounded;
}

/// The Care-Services card shell: a radius-24 surface with a coloured glow that
/// dims while pressed, plus the press-spring micro-animation (squash to 0.96 in
/// 120ms/easeOut, elastic spring-back in 450ms/elasticOut).
///
/// [cardColor] and [glowColor] are the admin override hooks the SDUI sections
/// need; both fall back to the theme.
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  /// Admin card-background override; null ⇒ theme `hd.surface`.
  final Color? cardColor;

  /// Admin accent override recolouring the drop-shadow glow; null ⇒ `hd.violet`.
  final Color? glowColor;

  const PressableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.cardColor,
    this.glowColor,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard>
    with SingleTickerProviderStateMixin {
  // `_scale` is re-tweened per gesture so press-in (easeOut) and spring-back
  // (elasticOut) can use different curves off one controller.
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
              borderRadius: BorderRadius.circular(kCareCardRadius),
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
      // Material + InkWell (rather than a bare DecoratedBox) so taps get a
      // ripple clipped to the card's corners; the InkWell also drives the
      // press-scale controller above.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kCareCardRadius),
        child: Material(
          color: widget.cardColor ?? hd.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCareCardRadius),
            side: BorderSide(color: hd.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(kCareCardRadius),
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

/// A faint diagonal light sweep that glides across a card image on a gentle
/// repeat, then rests off-screen — the "living" glass shimmer. Purely
/// decorative, so it ignores pointers.
class CareCardShimmerSweep extends StatelessWidget {
  final Animation<double> animation;

  /// The full sweep cycle, including the rest beat between passes.
  static const Duration cycle = Duration(milliseconds: 3500);

  const CareCardShimmerSweep({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Sweep only during the first ~45% of the cycle; the band then sits
          // off the right edge for the rest (a brief rest between sweeps).
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
                    Color(0x1AFFFFFF), // white @ ~10%
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

/// Vivid violet gradient shown in place of a card photo — on its own while the
/// image loads, and with [icon] when there is no image or it failed.
class CareCardImageFallback extends StatelessWidget {
  final IconData? icon;
  const CareCardImageFallback({super.key, this.icon});

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

/// True for an SVG source.
///
/// [CachedNetworkImage] decodes raster formats only and would send a vector
/// straight to the error widget, so SVGs — which is what an admin naturally
/// reaches for when uploading a service icon — need their own branch.
///
/// Matched on the URL *path*, so a `?v=2` cache-buster can't hide the
/// extension and push a valid icon onto the raster decoder.
bool isSvgUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return path.toLowerCase().endsWith('.svg');
}

/// A card photo with the shared gradient placeholder / error treatment.
/// Sized by its parent — pass it a bounded box or a [Stack] with
/// `fit: StackFit.expand`.
class CareCardImage extends StatelessWidget {
  final String? url;
  final IconData? fallbackIcon;

  const CareCardImage({super.key, required this.url, this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) {
      return CareCardImageFallback(icon: fallbackIcon);
    }
    if (isSvgUrl(u)) {
      return SvgPicture.network(
        u,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => const CareCardImageFallback(),
        // Keeps a broken vector on the same gradient tile a broken photo gets,
        // rather than flutter_svg's own error rendering.
        errorBuilder: (_, _, _) => CareCardImageFallback(icon: fallbackIcon),
      );
    }
    return CachedNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      placeholder: (_, _) => const CareCardImageFallback(),
      errorWidget: (_, _, _) => CareCardImageFallback(icon: fallbackIcon),
    );
  }
}

/// The glowing category pill overlaid on a card image.
///
/// With an [accent] it renders near-solid and glowing; without one it falls
/// back to a neutral chip. The near-solid fill is deliberate — a translucent
/// tint vanishes against the violet gradient fallback and washes out over a
/// light photo, which is precisely where the badge has to stay legible.
class CareCardCategoryBadge extends StatelessWidget {
  final String label;

  /// Category accent. Null ⇒ the neutral, glow-less variant.
  final Color? accent;

  /// Admin overrides for the SDUI sections; win over [accent] when set.
  final Color? background;
  final Color? textColor;

  final IconData? icon;

  const CareCardCategoryBadge({
    super.key,
    required this.label,
    this.accent,
    this.background,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final a = accent;
    final fill = background ??
        (a != null
            ? a.withValues(alpha: 0.92)
            : hd.surfaceHi.withValues(alpha: 0.72));
    // The glow is the category signal, so an unrecognised (or admin-coloured)
    // badge deliberately doesn't get one.
    final glow = background == null && a != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: a != null
              ? Colors.white.withValues(alpha: 0.22)
              : hd.border,
        ),
        boxShadow: glow
            ? [BoxShadow(color: a.withValues(alpha: 0.50), blurRadius: 14)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor ?? Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            // Rendered verbatim, never uppercased — 'DOCTOR IN HOME' does not
            // fit the 181px three-column tile.
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.labelSm.copyWith(
              color: textColor ?? Colors.white,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
