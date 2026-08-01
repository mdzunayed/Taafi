import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors_ext.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../chat/models/conversation_model.dart';
import '../../../chat/presentation/chat_screen.dart';
import '../../../chat/providers/conversation_list_provider.dart';
import '../../../notifications/models/notification_item.dart';
import '../../../notifications/providers/notification_provider.dart';

/// Support & Admin multi-tab communications terminal.
///
/// The primary triage surface for operators authenticated as `Support` or
/// `Admin`. It layers three filtered views over the ONE app-wide conversation
/// inbox ([conversationListProvider], whose unread badges already ride the
/// shared socket) plus the platform notification stream:
///
///   • **Active Patient Inquiries** — live patient ↔ helpdesk threads.
///   • **Provider Verification / Escalate Requests** — provider-side threads
///     (doctor / nurse / lab tech) requesting credential clearance or support.
///   • **System Logs** — a telemetry console of platform notifications,
///     routing alerts, and critical ticket-state changes.
///
/// Fully theme-aware: it reads the semantic [AppColors] tokens so it flips to
/// the dark obsidian canvas with the reserved `#F36512` brand-orange accent,
/// matching the rest of the messaging surfaces — no hardcoded canvas literals.
///
/// (Deviation from the request skeleton: this is a [ConsumerStatefulWidget]
/// rather than a plain [StatefulWidget] so it can subscribe to the Riverpod
/// conversation/notification providers for real-time state. It still owns its
/// own [TabController] via [SingleTickerProviderStateMixin].)
class SupportInboxScreen extends ConsumerStatefulWidget {
  final String currentAdminId;

  /// Supports 'Admin' or 'Support' profiles.
  final String adminRole;

  const SupportInboxScreen({
    super.key,
    required this.currentAdminId,
    required this.adminRole,
  });

  @override
  ConsumerState<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends ConsumerState<SupportInboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Threads whose non-me participants include [role] and that are still open.
  List<ConversationModel> _threadsFor(
    List<ConversationModel> all,
    ParticipantRole role,
  ) {
    return [
      for (final c in all)
        if (c.isActive &&
            c.participants.any(
              (p) => p.userId != widget.currentAdminId && p.role == role,
            ))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final inbox = ref.watch(conversationListProvider);
    final logs = ref.watch(notificationProvider).items;

    final patientThreads = _threadsFor(
      inbox.conversations,
      ParticipantRole.patient,
    );
    final providerThreads = _threadsFor(
      inbox.conversations,
      ParticipantRole.provider,
    );

    return Scaffold(
      backgroundColor: a.canvas,
      appBar: AppBar(
        backgroundColor: a.surface,
        foregroundColor: a.title,
        elevation: 0,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Support ',
                    style: MtTextStyles.h2.copyWith(color: a.title),
                  ),
                  TextSpan(
                    text: 'Inbox',
                    style: MtTextStyles.h2.copyWith(color: a.accent),
                  ),
                ],
              ),
            ),
            Text(
              'Signed in as ${widget.adminRole}',
              style: MtTextStyles.bodySm.copyWith(color: a.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: a.body),
            onPressed: () =>
                ref.read(conversationListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Container(
            decoration: BoxDecoration(
              color: a.surface,
              border: Border(
                bottom: BorderSide(color: a.cardBorder),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: a.accent,
              indicatorWeight: 2.5,
              labelColor: a.title,
              unselectedLabelColor: a.muted,
              labelStyle: MtTextStyles.labelMd,
              unselectedLabelStyle: MtTextStyles.labelMd,
              tabs: [
                _CountTab(
                  label: 'Active Patient Inquiries',
                  count: _unread(patientThreads),
                ),
                _CountTab(
                  label: 'Provider Verification & Escalations',
                  count: _unread(providerThreads),
                ),
                _CountTab(label: 'System Logs', count: 0),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ThreadList(
            inbox: inbox,
            threads: patientThreads,
            meUserId: widget.currentAdminId,
            emptyIcon: Icons.support_agent_rounded,
            emptyTitle: 'No active patient inquiries',
            emptyBody:
                'Live patient conversations routed to the helpdesk appear here.',
            onOpen: _openThread,
            onRefresh: () =>
                ref.read(conversationListProvider.notifier).refresh(),
          ),
          _ThreadList(
            inbox: inbox,
            threads: providerThreads,
            meUserId: widget.currentAdminId,
            emptyIcon: Icons.verified_user_outlined,
            emptyTitle: 'No provider requests',
            emptyBody:
                'Credential clearance and provider account escalations land here.',
            onOpen: _openThread,
            onRefresh: () =>
                ref.read(conversationListProvider.notifier).refresh(),
          ),
          _SystemLogsConsole(logs: logs),
        ],
      ),
    );
  }

  int _unread(List<ConversationModel> threads) =>
      threads.fold(0, (sum, c) => sum + c.unreadCount);

  void _openThread(ConversationModel convo) {
    // Optimistically clear the badge; the chat screen's `conversation:read`
    // zeroes it server-side too.
    ref.read(conversationListProvider.notifier).markReadLocally(convo.id);
    final me = widget.currentAdminId;
    final other = convo.otherParticipant(me);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: convo.id,
          currentUserId: me,
          otherUserName: convo.titleFor(me),
          otherUserAvatarUrl: other?.avatarUrl,
          otherUserSubtitle:
              convo.isGroup ? '${convo.participants.length} members' : null,
        ),
      ),
    );
  }
}

/// A tab label with a trailing unread-count capsule.
class _CountTab extends StatelessWidget {
  final String label;
  final int count;
  const _CountTab({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    return Tab(
      height: 46,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: a.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: MtTextStyles.bodySm.copyWith(
                  color: a.onAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A filtered, refreshable list of conversation cards for one tab.
class _ThreadList extends StatelessWidget {
  final ConversationListState inbox;
  final List<ConversationModel> threads;
  final String meUserId;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final ValueChanged<ConversationModel> onOpen;
  final Future<void> Function() onRefresh;

  const _ThreadList({
    required this.inbox,
    required this.threads,
    required this.meUserId,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;

    if (inbox.status == InboxStatus.loading && inbox.conversations.isEmpty) {
      return Center(child: CircularProgressIndicator(color: a.accent));
    }
    if (inbox.status == InboxStatus.error && inbox.conversations.isEmpty) {
      return _CenteredState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load the inbox",
        body: inbox.errorMessage ?? 'Please try again.',
        onRetry: onRefresh,
      );
    }

    return RefreshIndicator(
      color: a.accent,
      backgroundColor: a.surface,
      onRefresh: onRefresh,
      child: threads.isEmpty
          ? _CenteredState(icon: emptyIcon, title: emptyTitle, body: emptyBody)
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: threads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final convo = threads[index];
                return _InboxCard(
                  convo: convo,
                  meUserId: meUserId,
                  onTap: () => onOpen(convo),
                );
              },
            ),
    );
  }
}

/// A single rounded (r16) inbox message card with a soft drop-shadow,
/// role token badges, and an inline unread capsule.
class _InboxCard extends StatelessWidget {
  final ConversationModel convo;
  final String meUserId;
  final VoidCallback onTap;

  const _InboxCard({
    required this.convo,
    required this.meUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final title = convo.titleFor(meUserId);
    final other = convo.otherParticipant(meUserId);
    final hasUnread = convo.unreadCount > 0;
    final preview = convo.lastMessageText.isEmpty
        ? 'Start the conversation'
        : convo.lastMessageText;

    // Distinct non-me roles present in the thread, for triage badges.
    final roles = <ParticipantRole>{
      for (final p in convo.participants)
        if (p.userId != meUserId) p.role,
    }.toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: a.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: title, url: other?.avatarUrl, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MtTextStyles.labelLg.copyWith(
                                color: a.title,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(convo.lastMessageAt),
                            style: MtTextStyles.bodySm.copyWith(
                              color: hasUnread ? a.accent : a.muted,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (convo.isGroup) ...[
                            Icon(Icons.groups_outlined,
                                size: 15, color: a.muted),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MtTextStyles.bodyMd.copyWith(
                                color: hasUnread ? a.body : a.muted,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            _UnreadPill(count: convo.unreadCount),
                          ],
                        ],
                      ),
                      if (roles.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in roles) _RoleBadge(role: r),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime? ts) {
    if (ts == null) return '';
    final local = ts.toLocal();
    final now = DateTime.now();
    final sameDay = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    if (sameDay) return DateFormat('h:mm a').format(local);
    final diff = now.difference(local);
    if (diff.inDays < 7) return DateFormat('EEE').format(local);
    return DateFormat('MMM d').format(local);
  }
}

/// A compact color-coded semantic role tag, e.g. "PATIENT" / "PROVIDER".
class _RoleBadge extends StatelessWidget {
  final ParticipantRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final (label, fg, bg) = switch (role) {
      ParticipantRole.patient => ('PATIENT', a.info, a.infoBg),
      ParticipantRole.provider => ('PROVIDER', a.warning, a.warningBg),
      ParticipantRole.admin => ('ADMIN', a.brand, a.brand.withValues(alpha: 0.14)),
      ParticipantRole.support => ('SUPPORT', a.accent, a.accent.withValues(alpha: 0.14)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: MtTextStyles.labelSm.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _UnreadPill extends StatelessWidget {
  final int count;
  const _UnreadPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: a.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: MtTextStyles.bodySm.copyWith(
          color: a.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          height: 1.0,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const _Avatar({required this.name, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final cleaned = name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '');
    final src = url;
    if (src != null && src.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: cleaned,
            size: size,
            backgroundColor: a.accent,
            textColor: a.onAccent,
          ),
        ),
      );
    }
    return InitialsAvatar(
      name: cleaned,
      size: size,
      backgroundColor: a.accent,
      textColor: a.onAccent,
    );
  }
}

/// Tab 3 — a text-heavy telemetry console rendering platform notifications,
/// routing alerts, and critical ticket-state changes as log lines.
class _SystemLogsConsole extends StatelessWidget {
  final List<NotificationItem> logs;
  const _SystemLogsConsole({required this.logs});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    if (logs.isEmpty) {
      return const _CenteredState(
        icon: Icons.terminal_rounded,
        title: 'Console is quiet',
        body: 'Platform alerts and ticket-state changes stream in here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: logs.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: a.cardBorder),
      itemBuilder: (context, index) => _LogRow(item: logs[index]),
    );
  }
}

class _LogRow extends StatelessWidget {
  final NotificationItem item;
  const _LogRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final (tag, color) = _kindStyle(item.kind, a);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: MtTextStyles.labelSm.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d · HH:mm:ss').format(
                        item.timestamp.toLocal(),
                      ),
                      style: MtTextStyles.bodySm.copyWith(
                        color: a.muted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  style: MtTextStyles.labelMd.copyWith(color: a.title),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.body,
                    style: MtTextStyles.bodySm.copyWith(color: a.body),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _kindStyle(NotificationKind kind, AppColors a) {
    return switch (kind) {
      NotificationKind.appointment => ('APPT', a.info),
      NotificationKind.chat => ('CHAT', a.accent),
      NotificationKind.payment => ('PAY', a.positive),
      NotificationKind.systemBroadcast => ('SYS', a.warning),
      NotificationKind.unknown => ('LOG', a.muted),
    };
  }
}

/// Shared empty / error placeholder that keeps pull-to-refresh alive.
class _CenteredState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function()? onRetry;

  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: a.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: a.accent),
              ),
              const SizedBox(height: 16),
              Text(title, style: MtTextStyles.h3.copyWith(color: a.title)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodyMd.copyWith(color: a.body),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: a.accent,
                    foregroundColor: a.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
