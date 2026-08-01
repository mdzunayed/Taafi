import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// Web-safe frosted glass.
///
/// On mobile/desktop this applies a real [BackdropFilter] blur. On **web** it
/// skips the blur entirely: a scene-capturing `BackdropFilter` on Flutter's
/// CanvasKit web renderer is a known cause of an all-black region (it blanked
/// the whole patient-home body — everything behind the glass rendered black
/// while the one non-blurred element, the nav pill, stayed visible). The
/// caller's own translucent fill provides the frosted look instead, so bump
/// that fill's opacity on web via [blurSupported].
///
/// Drop-in for `ClipR*( child: BackdropFilter(filter: blur, child: fill) )`:
/// `FrostedSurface(borderRadius: r, blur: n, child: fill)`.
class FrostedSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius borderRadius;

  const FrostedSurface({
    super.key,
    required this.child,
    this.blur = 12,
    this.borderRadius = BorderRadius.zero,
  });

  /// True when the real backdrop blur is safe to use (everything except web).
  /// Callers use this to raise their fill opacity on web so it still reads as
  /// glass without the blur.
  static bool get blurSupported => !kIsWeb;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (!kIsWeb) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      );
    }
    return borderRadius == BorderRadius.zero
        ? ClipRect(child: content)
        : ClipRRect(borderRadius: borderRadius, child: content);
  }
}

/// Web-safe blur layer (no clipping). A drop-in for a raw `BackdropFilter`
/// nested inside an existing `ClipR*`: on web it returns [child] unchanged
/// (the caller's own translucent fill carries the frosting) so it can't blank
/// the CanvasKit scene; on native it applies the real blur.
Widget blurLayer({required Widget child, double blur = 12}) {
  if (kIsWeb) return child;
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
    child: child,
  );
}
