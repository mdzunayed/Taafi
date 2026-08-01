import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../models/notification_item.dart';
import '../providers/notification_provider.dart';
import 'notification_format.dart';

/// Unified notification inbox shared by all three roles. Renders a
/// timeline-grouped list ("Today" / "Yesterday" / "Earlier") of
/// notification cards. Each card uses a colored leading icon circle,
/// title + body column, and a trailing time + unread-dot pair.
///
/// Opening the hub counts as "seeing" the inbox, so it marks every unread
/// row read on first frame — this is what clears the bell badge across all
/// three role shells the moment the user views their notifications.
class NotificationHubScreen extends ConsumerStatefulWidget {
  const NotificationHubScreen({super.key});

  @override
  ConsumerState<NotificationHubScreen> createState() =>
      _NotificationHubScreenState();
}

class _NotificationHubScreenState extends ConsumerState<NotificationHubScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to the first frame so we mutate the notifier after the initial
    // build, then clear the unseen signal (atomic PATCH /read-all). No-ops
    // when the inbox is already fully read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final hasUnread = state.unreadCount > 0;

    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Notifications'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: hasUnread
                ? () =>
                    ref.read(notificationProvider.notifier).markAllRead()
                : null,
            style: TextButton.styleFrom(
              foregroundColor: MtColors.brand,
              disabledForegroundColor: MtColors.ink3,
            ),
            child: const Text('Mark all read'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: RefreshIndicator(
        color: MtColors.brand,
        onRefresh: () => ref.read(notificationProvider.notifier).refresh(),
        child: _Body(state: state),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final NotificationState state;
  const _Body({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MtColors.brand),
      );
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return _ErrorView(message: state.errorMessage!);
    }
    if (state.items.isEmpty) {
      return const _EmptyView();
    }

    final groups = groupNotificationsByDay(state.items);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: groups.length,
      itemBuilder: (context, groupIdx) {
        final group = groups[groupIdx];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  group.label.toUpperCase(),
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              for (int i = 0; i < group.items.length; i++) ...[
                _NotificationCard(item: group.items[i]),
                if (i != group.items.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }

}

// ---------------------------------------------------------------------------
// Notification card
// ---------------------------------------------------------------------------

class _NotificationCard extends ConsumerWidget {
  final NotificationItem item;
  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _paletteFor(item.kind);
    final timeLabel = notificationRelativeTime(item.timestamp);

    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(context, ref),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isRead ? MtColors.line : palette.accent,
              width: item.isRead ? 1 : 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconCircle(palette: palette, icon: palette.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: MtTextStyles.labelLg.copyWith(
                        color: MtColors.ink,
                        fontWeight: item.isRead
                            ? FontWeight.w600
                            : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: MtTextStyles.bodySm.copyWith(
                        color: MtColors.ink2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeLabel,
                    style: MtTextStyles.bodySm.copyWith(
                      color: MtColors.ink3,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: item.isRead ? 0 : 1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB), // blue unread dot
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

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // Optimistic flip — provider also patches the backend in the same call.
    if (!item.isRead) {
      // ignore: unawaited_futures
      ref.read(notificationProvider.notifier).markRead(item.id);
    }
    final deepLink = item.payload['deepLink']?.toString();
    final appointmentId = item.payload['appointmentId']?.toString();
    if (deepLink == null || deepLink.isEmpty) return;

    // The hub doesn't import every feature directly to avoid build-time
    // cycles. Each deep link emits an event the embedding shell can
    // listen to via a route name — for now we route by popping the hub
    // and letting the user land on the relevant tab themselves.
    // (Chat / tracking screens are also reachable from the dashboard
    // shells.)
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
    if (appointmentId != null && appointmentId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opened: ${item.title}')),
      );
    }
  }

}

class _IconCircle extends StatelessWidget {
  final _NotificationPalette palette;
  final IconData icon;
  const _IconCircle({required this.palette, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        // 10% opacity tint of the type's accent color — soft circle
        // backdrop per the spec.
        color: palette.accent.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: palette.accent, size: 20),
    );
  }
}

class _NotificationPalette {
  final Color accent;
  final IconData icon;
  const _NotificationPalette(this.accent, this.icon);
}

_NotificationPalette _paletteFor(NotificationKind kind) {
  switch (kind) {
    case NotificationKind.appointment:
      return const _NotificationPalette(MtColors.brand, Icons.calendar_today);
    case NotificationKind.chat:
      return const _NotificationPalette(Color(0xFF2563EB), Icons.message);
    case NotificationKind.payment:
      return const _NotificationPalette(MtColors.completed, Icons.payments_outlined);
    case NotificationKind.systemBroadcast:
      return const _NotificationPalette(Color(0xFF7C3AED), Icons.campaign_outlined);
    case NotificationKind.unknown:
      return const _NotificationPalette(MtColors.ink2, Icons.notifications_outlined);
  }
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none,
              size: 36,
              color: MtColors.brand,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'No notifications yet',
          textAlign: TextAlign.center,
          style: MtTextStyles.h2.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            'Booking updates, doctor assignments, and chat alerts will land here in real time.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Icon(Icons.cloud_off_outlined, size: 36, color: MtColors.ink3),
        ),
        const SizedBox(height: 12),
        Text(
          "Couldn't load notifications",
          textAlign: TextAlign.center,
          style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
          ),
        ),
      ],
    );
  }
}
