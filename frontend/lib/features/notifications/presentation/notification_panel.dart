import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/frosted_surface.dart';
import '../models/notification_item.dart';
import '../providers/notification_provider.dart';
import 'notification_format.dart';
import 'notification_hub_screen.dart';

/// Opens the ultra-premium glassmorphic notification panel as a top-anchored
/// overlay (floats above the current screen — no route push). Binds to the
/// existing [notificationProvider], so it shares the same live socket-fed
/// inbox + unread count as the bell and the full-screen hub.
///
/// The panel is THEME-AWARE: in dark mode it renders as a midnight glass slab;
/// in light mode it becomes a crisp, high-blur frosted-white sheet. Neutral
/// chrome resolves from `context.appColors`; the per-category accent colours
/// below stay vivid in both modes.
///
/// Dismiss: tap the scrim, the close button, or "See all" (which forwards to
/// the full [NotificationHubScreen]).
Future<void> showNotificationPanel(BuildContext context) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  var removed = false;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NotificationPanelHost(
      onDismiss: () {
        if (removed) return;
        removed = true;
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

// ---------------------------------------------------------------------------
// Per-category accent colours. These are semantic *category* markers (payment,
// appointment, chat, broadcast) rather than theme chrome, so they stay vivid
// and constant — they read cleanly on both the light-frost and dark-glass
// tiles. The `unknown` case falls back to the theme's muted colour.
// ---------------------------------------------------------------------------
const Color _kPaymentAccent = Color(0xFF2DD4BF); // teal
const Color _kAppointmentAccent = Color(0xFF7C4DFF); // violet
const Color _kChatAccent = Color(0xFF6366F1); // indigo
const Color _kBroadcastAccent = Color(0xFF8B5CF6); // bright violet

class _NotificationPanelHost extends StatefulWidget {
  final VoidCallback onDismiss;
  const _NotificationPanelHost({required this.onDismiss});

  @override
  State<_NotificationPanelHost> createState() => _NotificationPanelHostState();
}

class _NotificationPanelHostState extends State<_NotificationPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top + 8;
    final panelWidth =
        media.size.width < 460 ? media.size.width - 24 : 400.0;
    final maxHeight = media.size.height * 0.72;
    // Lighter scrim under a light theme so the frosted white doesn't read as a
    // dark modal; the classic deep scrim stays under the dark glass.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final scrim = Colors.black.withValues(alpha: isLight ? 0.28 : 0.54);

    return Stack(
      children: [
        // Tap-scrim.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: FadeTransition(
              opacity: _fade,
              child: ColoredBox(color: scrim),
            ),
          ),
        ),
        // Top-right anchored glass panel.
        Positioned(
          top: topInset,
          right: 12,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: panelWidth,
                  maxHeight: maxHeight,
                ),
                child: _GlassPanel(onDismiss: _dismiss),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassPanel extends ConsumerStatefulWidget {
  final Future<void> Function() onDismiss;
  const _GlassPanel({required this.onDismiss});

  @override
  ConsumerState<_GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends ConsumerState<_GlassPanel> {
  @override
  void initState() {
    super.initState();
    // Opening the panel clears the unread badge, mirroring
    // NotificationHubScreen. `markAllRead` early-returns when nothing is
    // unread and is optimistic (the dot vanishes instantly) with rollback on
    // network failure — so the red dot dies the moment notifications open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final notifier = ref.read(notificationProvider.notifier);
    final c = context.appColors;

    return FrostedSurface(
      blur: 18,
      borderRadius: BorderRadius.circular(24),
      child: Container(
          decoration: BoxDecoration(
            // Near-opaque on web (no blur) so the panel reads solid over the
            // scrim; the slight translucency stays where the blur exists.
            color: c.surface.withValues(
              alpha: FrostedSurface.blurSupported ? 0.88 : 0.98,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.brand.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: c.glow,
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(
                  unreadCount: state.unreadCount,
                  onMarkAll: state.unreadCount > 0 ? notifier.markAllRead : null,
                  onRefresh: notifier.refresh,
                  onClose: widget.onDismiss,
                ),
                const _HairLine(),
                Flexible(child: _Body(state: state, notifier: notifier)),
                const _HairLine(),
                _Footer(onSeeAll: () => _seeAll(context)),
              ],
            ),
          ),
        ),
      );
  }

  Future<void> _seeAll(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await widget.onDismiss();
    navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationHubScreen()),
    );
  }
}

class _Header extends StatelessWidget {
  final int unreadCount;
  final VoidCallback? onMarkAll;
  final VoidCallback onRefresh;
  final Future<void> Function() onClose;

  const _Header({
    required this.unreadCount,
    required this.onMarkAll,
    required this.onRefresh,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
      child: Row(
        children: [
          Text(
            'Notifications',
            style: MtTextStyles.h3.copyWith(color: c.title),
          ),
          const SizedBox(width: 8),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.brand.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: c.brand.withValues(alpha: 0.5)),
              ),
              child: Text(
                '$unreadCount new',
                style: MtTextStyles.labelSm.copyWith(
                  color: c.brand,
                  fontSize: 10,
                ),
              ),
            ),
          const Spacer(),
          if (onMarkAll != null)
            TextButton(
              onPressed: onMarkAll,
              style: TextButton.styleFrom(
                foregroundColor: c.brand,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Mark all read',
                style: MtTextStyles.labelSm.copyWith(
                  color: c.brand,
                ),
              ),
            ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: c.body,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final NotificationState state;
  final NotificationNotifier notifier;
  const _Body({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    if (state.isLoading && state.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(c.brand),
            ),
          ),
        ),
      );
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return _PanelMessage(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load notifications",
        message: state.errorMessage!,
        actionLabel: 'Retry',
        onAction: notifier.refresh,
      );
    }
    if (state.items.isEmpty) {
      return const _PanelMessage(
        icon: Icons.notifications_none_rounded,
        title: 'All caught up',
        message:
            'Booking updates, provider assignments, and chat alerts land here in real time.',
      );
    }

    final groups = groupNotificationsByDay(state.items);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      shrinkWrap: true,
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              child: Text(
                group.label.toUpperCase(),
                style: MtTextStyles.sectionLabel.copyWith(
                  color: c.muted,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            for (int j = 0; j < group.items.length; j++) ...[
              _GlassTile(
                item: group.items[j],
                onTap: () => notifier.markRead(group.items[j].id),
              ),
              if (j != group.items.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _GlassTile extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  const _GlassTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (accent, icon) = _accentFor(item.kind, c);
    final unread = !item.isRead;

    return Material(
      color: c.surfaceHi.withValues(alpha: unread ? 0.7 : 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? accent.withValues(alpha: 0.55)
                  : c.cardBorder,
              width: unread ? 1.2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: MtTextStyles.labelLg.copyWith(
                        color: c.title,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      style: MtTextStyles.bodySm.copyWith(
                        color: c.body,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    notificationRelativeTime(item.timestamp),
                    style: MtTextStyles.bodySm.copyWith(
                      color: c.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: unread ? 1 : 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _Footer({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onSeeAll,
        style: TextButton.styleFrom(
          foregroundColor: c.brand,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'See all notifications',
              style: MtTextStyles.labelMd.copyWith(
                color: c.brand,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
          ],
        ),
      ),
    );
  }
}

class _HairLine extends StatelessWidget {
  const _HairLine();

  @override
  Widget build(BuildContext context) => Container(
      height: 1, color: context.appColors.cardBorder.withValues(alpha: 0.6));
}

class _PanelMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.brand.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: c.brand),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: MtTextStyles.labelLg.copyWith(color: c.title),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: c.body),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: c.brand,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Per-kind accent + icon. Category accents stay vivid across themes; `unknown`
/// resolves to the ambient muted colour.
(Color, IconData) _accentFor(NotificationKind kind, AppColors c) {
  switch (kind) {
    case NotificationKind.payment:
      return (_kPaymentAccent, Icons.payments_outlined);
    case NotificationKind.appointment:
      return (_kAppointmentAccent, Icons.calendar_today_rounded);
    case NotificationKind.chat:
      return (_kChatAccent, Icons.chat_bubble_outline_rounded);
    case NotificationKind.systemBroadcast:
      return (_kBroadcastAccent, Icons.campaign_outlined);
    case NotificationKind.unknown:
      return (c.muted, Icons.notifications_none_rounded);
  }
}
