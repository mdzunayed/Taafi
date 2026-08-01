import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../presentation/notification_panel.dart';
import '../providers/notification_provider.dart';

/// Shared notification bell used by the patient, doctor, and admin
/// dashboard app bars. Renders an `IconButton(Icons.notifications_none)`
/// inside a `Stack` with the unread-count badge pinned at the top-right
/// corner. The badge is automatically hidden when `unreadCount == 0`,
/// matching the spec.
///
/// Tap opens the glassmorphic [showNotificationPanel] overlay (whose "See
/// all" forwards to the full-screen hub). Embedding screens can override that
/// by passing [onTap].
class NotificationBell extends ConsumerWidget {
  final VoidCallback? onTap;

  /// Variant — when true (default) the bell renders inside a soft
  /// rounded chip (used on the patient + doctor home headers). When
  /// false it renders as a plain `IconButton` that fits inside an
  /// `AppBar.actions` slot (used on the admin shell).
  final bool framed;

  const NotificationBell({
    super.key,
    this.onTap,
    this.framed = true,
  });

  void _open(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    // Default action across all role shells: the glassmorphic overlay panel.
    // Its "See all" forwards to the full-screen NotificationHubScreen.
    showNotificationPanel(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final iconButton = IconButton(
      onPressed: () => _open(context),
      icon: const Icon(Icons.notifications_none, color: MtColors.ink),
      tooltip: 'Notifications',
    );

    if (!framed) {
      // Admin-style: plain icon button, pin the badge using a Stack
      // around the button so the dot sits at the icon's top-right
      // corner, never inside the button hit-target.
      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: iconButton),
            if (unread > 0)
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(
                  child: _CountBadgeLabel(count: unread),
                ),
              ),
          ],
        ),
      );
    }

    // Framed variant — used on the patient + doctor home headers.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MtColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MtColors.line),
              ),
              child: const Icon(
                Icons.notifications_none,
                color: MtColors.ink,
                size: 22,
                semanticLabel: 'Notifications',
              ),
            ),
            if (unread > 0)
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(
                  child: _CountBadgeLabel(count: unread),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadgeLabel extends StatelessWidget {
  final int count;
  const _CountBadgeLabel({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: MtColors.rejected,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: MtTextStyles.labelSm.copyWith(
          color: Colors.white,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
