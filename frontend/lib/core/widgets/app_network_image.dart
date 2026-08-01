import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/mt_colors.dart';
import '../utils/image_url.dart';

/// A network image that always degrades gracefully.
///
/// Wraps [CachedNetworkImage] with the three guards that every call site was
/// otherwise re-implementing (or forgetting):
///
///  1. The URL is run through [resolveImageUrl], so relative `/uploads/...`
///     paths are absolutized and empty/malformed values resolve to `null`.
///  2. A `null` URL renders the fallback directly — [CachedNetworkImage]
///     asserts on an empty `imageUrl`, so it is never constructed at all.
///  3. Load failures render a neutral placeholder instead of Flutter's red
///     error box. On Flutter Web this covers decode failures (a wrong
///     `Content-Type`), CORS rejections, and plain 404s alike.
class AppNetworkImage extends StatelessWidget {
  /// Raw value from the API. May be absolute, relative, empty, or null.
  final String? url;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Rounds the image and both fallback states together.
  final BorderRadius? borderRadius;

  /// Icon shown in the error/empty state. Sized to fit small thumbnails.
  final IconData fallbackIcon;

  /// Overrides for call sites with an established look of their own — e.g.
  /// the banner list, which falls back to a brand gradient rather than a grey
  /// box. When omitted, both default to [_neutralBox].
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.broken_image_outlined,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  Widget _neutralBox(BuildContext context, {IconData? icon}) {
    return Container(
      width: width,
      height: height,
      color: MtColors.surface2,
      alignment: Alignment.center,
      child: icon == null
          ? null
          : Icon(icon, color: MtColors.ink3, size: _iconSize),
    );
  }

  // Keep the glyph proportional so a 44px avatar and a 220px ad tile both
  // look deliberate rather than stamped with the same 24px default.
  double get _iconSize {
    final box = [
      width,
      height,
    ].whereType<double>().where((d) => d.isFinite).fold<double?>(
          null,
          (min, d) => min == null || d < min ? d : min,
        );
    if (box == null) return 28;
    return (box * 0.32).clamp(14.0, 40.0);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveImageUrl(url);

    Widget child;
    if (resolved == null) {
      // Nothing renderable — skip CachedNetworkImage entirely.
      child = errorBuilder?.call(context) ??
          _neutralBox(context, icon: fallbackIcon);
    } else {
      child = CachedNetworkImage(
        imageUrl: resolved,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, _) =>
            placeholderBuilder?.call(context) ?? _neutralBox(context),
        errorWidget: (context, _, _) =>
            errorBuilder?.call(context) ??
            _neutralBox(context, icon: fallbackIcon),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
