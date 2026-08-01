import 'package:flutter/material.dart';

import '../../../../core/theme/mt_text_styles.dart';

/// ============================================================================
/// CustomFloatingNavBar
/// ============================================================================
/// The app-wide floating "capsule pill" bottom navigation bar, shared by the
/// patient, doctor and nurse shells.
///
/// Visual anatomy (matches the reference design):
///   • A floating stadium shell — solid deep midnight navy, fully semicircular
///     ends (radius = height / 2) — lifted off the screen base by side + bottom
///     margins and a soft drop shadow so it reads as elevated.
///   • The shell spans the viewport minus fixed side margins (capped at
///     [maxWidth] on wide viewports) and distributes its circular slots with
///     even spacing.
///   • ACTIVE slot: a bold, solid vibrant-orange circle with a clean white
///     glyph centred inside it. Selection is a STATIC per-slot fill — the
///     circle colour cross-fades in place; nothing slides between slots.
///   • INACTIVE slots: a faint translucent white disc with a low-contrast
///     silver glyph.
///   • Each tap applies a micro-scale press feedback so the circles feel
///     tactile and responsive.
///
/// The pill wears a FIXED deep-navy identity in BOTH light and dark themes —
/// matching the reference design exactly regardless of the ambient
/// [Brightness]. It deliberately does not read the theme.
///
/// Integration is via a plain [currentIndex] + [onTap] callback pair, so it
/// slots straight into an existing tab-index state (Riverpod notifier,
/// `setState`, `PageController`, …) without touching routing logic. The widget
/// fires NO haptics of its own — every shell's controller already does.
///
/// ```dart
/// CustomFloatingNavBar(
///   currentIndex: index,
///   onTap: (i) => setState(() => index = i),
///   items: const [
///     FloatingNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
///     ...
///   ],
/// )
/// ```

// ---------------------------------------------------------------------------
// Public value type
// ---------------------------------------------------------------------------

/// One navigation destination. Kept as a tiny value type so
/// [CustomFloatingNavBar] can lay the row out generically without hard-coding
/// any fixed number of items.
@immutable
class FloatingNavItem {
  /// The glyph shown while the item is inactive.
  final IconData icon;

  /// The glyph shown inside the orange circle while the item is active.
  /// Defaults to [icon] when a distinct active glyph isn't supplied.
  final IconData activeIcon;

  /// Semantic label — surfaced to screen readers. The UI itself is icon-only,
  /// so this text is never painted.
  final String label;

  /// Live count rendered as a small coral bubble riding the circle's
  /// top-right edge. `0` hides the badge; anything above 9 renders as `9+`.
  final int badgeCount;

  const FloatingNavItem({
    required this.icon,
    IconData? activeIcon,
    required this.label,
    this.badgeCount = 0,
  }) : activeIcon = activeIcon ?? icon;
}

// ---------------------------------------------------------------------------
// The navigation bar
// ---------------------------------------------------------------------------

class CustomFloatingNavBar extends StatelessWidget {
  /// Index of the currently selected destination. May legitimately point
  /// OUTSIDE `0..items.length-1` (e.g. the patient Account screen, which lives
  /// in the same shell but has no bottom-nav slot) — in that case no orange
  /// circle is shown and every item renders inactive.
  final int currentIndex;

  /// Fired with the tapped item's index. Drop your tab-switch call in here.
  /// No haptics fire inside the widget — the shells' controllers own that.
  final ValueChanged<int> onTap;

  /// The destinations, left-to-right.
  final List<FloatingNavItem> items;

  /// Width cap for the capsule on wide viewports; it stays centred beyond it.
  final double maxWidth;

  const CustomFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.maxWidth = 480,
  });

  // Fixed reference palette — identical in light and dark, not theme-derived
  // on purpose (see class doc).
  static const Color _shellColor = Color(0xFF0D1B2A); // midnight navy fill
  static const Color _activeColor = Color(0xFFF36512); // brand orange circle
  static final Color _inactiveFill = Colors.white.withValues(alpha: 0.08);
  static const Color _inactiveIcon = Colors.white54;

  /// Overall capsule height; the stadium radius is exactly half of it.
  static const double barHeight = 64;

  /// Nominal circle diameter — shrinks responsively on narrow viewports so
  /// five slots still fit a 320px screen without clipping.
  static const double circleSize = 48;

  /// Fixed side margins; the capsule must never span the full width.
  static const double sideMargin = 24;

  /// Gap the capsule floats above the bottom safe-area inset.
  static const double bottomMargin = 12;

  @override
  Widget build(BuildContext context) {
    // SafeArea keeps the pill clear of the home indicator / gesture bar on
    // modern edge-to-edge screens; the margins let it float.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, bottomMargin),
        // `heightFactor: 1.0` sizes this Align to the pill's own height
        // instead of expanding to fill the slot. Without it, when the bar is
        // placed in Scaffold.bottomNavigationBar (measured with loose
        // 0..screenHeight height constraints) a plain Center would balloon to
        // full screen height — swallowing the body and stranding the pill in
        // the vertical centre.
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Responsive circle size: keep at least an 8px gap around
                // every circle; shrink (never below 40 — a sane tap target)
                // only when the slot count doesn't fit at full size. Worst
                // supported case — 5 slots on a 320px screen — lands at ~44.
                final int n = items.length;
                final double w = constraints.maxWidth;
                const double minGap = 8;
                final double circle =
                    ((w - (n + 1) * minGap) / n).clamp(40.0, circleSize);
                final double iconSize = circle < 44 ? 22 : 24;

                return Container(
                  width: double.infinity,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: _shellColor,
                    // A true stadium: the end radius is exactly half the
                    // shell height, so the ends are full semicircles.
                    borderRadius: BorderRadius.circular(barHeight / 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (int i = 0; i < n; i++)
                        _NavSlot(
                          item: items[i],
                          // An off-tray currentIndex simply matches no slot,
                          // so every circle renders inactive — no clamp
                          // logic needed.
                          active: i == currentIndex,
                          circleSize: circle,
                          iconSize: iconSize,
                          onTap: () => onTap(i),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single tappable slot: full-height hit area, press-scale feedback, a
// static circle whose fill cross-fades between the orange active state and
// the translucent inactive tint, and an optional count badge.
// ---------------------------------------------------------------------------

class _NavSlot extends StatefulWidget {
  final FloatingNavItem item;
  final bool active;
  final double circleSize;
  final double iconSize;
  final VoidCallback onTap;

  const _NavSlot({
    required this.item,
    required this.active,
    required this.circleSize,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_NavSlot> createState() => _NavSlotState();
}

class _NavSlotState extends State<_NavSlot> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Semantics(
      button: true,
      selected: widget.active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // Full-bar-height hit target; the visible circle sits centred in it.
        child: SizedBox(
          height: CustomFloatingNavBar.barHeight,
          width: widget.circleSize + 8,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.86 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Static per-slot fill — the circle colour cross-fades in
                  // place on selection; no sliding indicator.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    width: widget.circleSize,
                    height: widget.circleSize,
                    decoration: BoxDecoration(
                      color: widget.active
                          ? CustomFloatingNavBar._activeColor
                          : CustomFloatingNavBar._inactiveFill,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        widget.active ? item.activeIcon : item.icon,
                        color: widget.active
                            ? Colors.white
                            : CustomFloatingNavBar._inactiveIcon,
                        size: widget.iconSize,
                      ),
                    ),
                  ),
                  if (item.badgeCount > 0)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: _CountBadge(count: item.badgeCount),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coral count bubble riding a slot circle's top-right edge (same look as the
// doctor rail's badge, bordered in the shell navy so it pops off both the
// orange and the faint-white circles).
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  static const Color _coral = Color(0xFFF43F5E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16),
      decoration: BoxDecoration(
        color: _coral,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CustomFloatingNavBar._shellColor, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: MtTextStyles.labelSm.copyWith(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
