import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../providers/conversation_list_provider.dart';
import 'conversation_list_screen.dart';

/// Shared inbox entry point for the patient, provider (doctor/nurse), and
/// admin shell headers. Mirrors [NotificationBell]: an `Icons.forum_outlined`
/// button with a live unread-total badge (fed by [conversationListProvider],
/// which itself rides the one app-wide socket). Tap opens the
/// [ConversationListScreen].
///
/// [framed] (default) renders the soft rounded chip used on the patient +
/// provider home headers; set false for a plain `AppBar.actions` icon
/// (admin shell).
class ConversationInboxButton extends ConsumerWidget {
  final bool framed;
  const ConversationInboxButton({super.key, this.framed = true});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ConversationListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = context.appColors;
    // Watch the inbox so the badge stays live. autoDispose keeps the
    // provider (and its socket subscription) alive only while a header
    // that mounts this button is on screen.
    final unread = ref.watch(
      conversationListProvider.select((s) => s.totalUnread),
    );

    if (!framed) {
      final iconButton = IconButton(
        onPressed: () => _open(context),
        icon: Icon(Icons.forum_outlined, color: a.title),
        tooltip: 'Messages',
      );
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
                child: IgnorePointer(child: _CountBadge(count: unread)),
              ),
          ],
        ),
      );
    }

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
                color: a.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: a.cardBorder),
              ),
              child: Icon(
                Icons.forum_outlined,
                color: a.title,
                size: 22,
                semanticLabel: 'Messages',
              ),
            ),
            if (unread > 0)
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(child: _CountBadge(count: unread)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final a = context.appColors;
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: a.accent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: a.surface, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: MtTextStyles.labelSm.copyWith(
          color: a.onAccent,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
