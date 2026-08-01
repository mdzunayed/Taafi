import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../models/conversation_model.dart';
import '../providers/conversation_list_provider.dart';
import 'chat_screen.dart';

/// The multi-role conversation inbox. Lists every thread the signed-in user
/// participates in — patient ↔ provider, group escalations, support — with
/// a live unread badge fed by the app-wide socket. Fully theme-aware:
/// flips to the dark obsidian canvas via [AppColors].
class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = context.appColors;
    final state = ref.watch(conversationListProvider);
    final me = ref.watch(currentUserProvider)?.id ?? '';

    return Scaffold(
      backgroundColor: a.canvas,
      appBar: AppBar(
        backgroundColor: a.surface,
        foregroundColor: a.title,
        elevation: 0,
        title: Text(
          'Messages',
          style: MtTextStyles.h2.copyWith(color: a.title),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: a.cardBorder),
        ),
      ),
      body: RefreshIndicator(
        color: a.accent,
        onRefresh: () => ref.read(conversationListProvider.notifier).refresh(),
        child: _body(context, ref, state, me),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    ConversationListState state,
    String me,
  ) {
    final a = context.appColors;
    if (state.status == InboxStatus.loading && state.conversations.isEmpty) {
      return Center(child: CircularProgressIndicator(color: a.accent));
    }
    if (state.status == InboxStatus.error && state.conversations.isEmpty) {
      return _ErrorState(
        message: state.errorMessage ?? 'Could not load your messages.',
        onRetry: () => ref.read(conversationListProvider.notifier).refresh(),
      );
    }
    if (state.conversations.isEmpty) {
      return const _EmptyInbox();
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.conversations.length,
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(left: 84),
        child: Divider(height: 1, color: a.cardBorder),
      ),
      itemBuilder: (context, index) {
        final convo = state.conversations[index];
        return _ConversationTile(
          convo: convo,
          meUserId: me,
          onTap: () => _openThread(context, ref, convo, me),
        );
      },
    );
  }

  void _openThread(
    BuildContext context,
    WidgetRef ref,
    ConversationModel convo,
    String me,
  ) {
    // Optimistically clear the badge; the socket `conversation:read` on the
    // chat screen zeroes it server-side too.
    ref.read(conversationListProvider.notifier).markReadLocally(convo.id);
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

class _ConversationTile extends StatelessWidget {
  final ConversationModel convo;
  final String meUserId;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.convo,
    required this.meUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final other = convo.otherParticipant(meUserId);
    final title = convo.titleFor(meUserId);
    final hasUnread = convo.unreadCount > 0;
    final preview = convo.lastMessageText.isEmpty
        ? 'Start the conversation'
        : convo.lastMessageText;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(name: title, url: other?.avatarUrl, size: 52),
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
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(convo.lastMessageAt),
                        style: MtTextStyles.bodySm.copyWith(
                          color: hasUnread ? a.accent : a.muted,
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (convo.isGroup) ...[
                        Icon(Icons.groups_outlined, size: 15, color: a.muted),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MtTextStyles.bodyMd.copyWith(
                            color: hasUnread ? a.body : a.muted,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        _UnreadPill(count: convo.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    return ListView(
      // ListView so pull-to-refresh works even when empty.
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
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
                child: Icon(Icons.forum_outlined, size: 34, color: a.accent),
              ),
              const SizedBox(height: 16),
              Text('No conversations yet',
                  style: MtTextStyles.h2.copyWith(color: a.title)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Messages with your care team and support will appear here.',
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodyMd.copyWith(color: a.body),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 36, color: a.muted),
              const SizedBox(height: 12),
              Text("Couldn't load messages",
                  style: MtTextStyles.labelLg.copyWith(color: a.title)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodySm.copyWith(color: a.body),
                ),
              ),
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
          ),
        ),
      ],
    );
  }
}
