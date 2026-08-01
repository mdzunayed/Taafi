import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/mt_text_styles.dart';
import '../../../chat/presentation/widgets/chat_input_bar.dart';
import '../../../chat/presentation/widgets/chat_message_list.dart';
import '../../../chat/presentation/widgets/chat_palette.dart';
import '../../../chat/providers/active_chat_provider.dart';
import '../../../chat/providers/chat_provider.dart';

/// Opens the [ActiveChatDrawer] as a right-side slide-in panel over the
/// current route. Shared by the patient tracking screen and the doctor /
/// nurse active-care consoles so an in-visit conversation is always one tap
/// away without leaving the active-job context.
Future<void> openActiveChatDrawer(
  BuildContext context, {
  required String appointmentId,
  required String currentUserId,
  required String otherUserId,
  required String otherUserName,
  String? otherUserAvatarUrl,
  String otherRoleLabel = 'Care Provider',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chat',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: _panelWidthFactor(context),
        heightFactor: 1,
        child: Material(
          color: Colors.transparent,
          child: ActiveChatDrawer(
            appointmentId: appointmentId,
            currentUserId: currentUserId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatarUrl: otherUserAvatarUrl,
            otherRoleLabel: otherRoleLabel,
          ),
        ),
      ),
    ),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

double _panelWidthFactor(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  // Full width on phones; a right-docked panel on tablets / desktop.
  if (w >= 900) return 0.42;
  if (w >= 600) return 0.62;
  return 1.0;
}

/// Reusable in-app communication drawer for an ACTIVE home-care visit. Wraps
/// the shared chat engine ([chatProvider] + [ChatMessageList] +
/// [ChatInputBar]) with a header carrying the recipient identity, a live
/// connection / typing indicator, and a prominent "Call via Secure Line"
/// masked-calling button. Locks to a read-only archive banner the moment the
/// booking's communication channel closes.
class ActiveChatDrawer extends ConsumerStatefulWidget {
  final String appointmentId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final String otherRoleLabel;

  const ActiveChatDrawer({
    super.key,
    required this.appointmentId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarUrl,
    this.otherRoleLabel = 'Care Provider',
  });

  @override
  ConsumerState<ActiveChatDrawer> createState() => _ActiveChatDrawerState();
}

class _ActiveChatDrawerState extends ConsumerState<ActiveChatDrawer> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();
  int _previousMessageCount = 0;
  bool _calling = false;

  ChatArgs get _args => ChatArgs(
        appointmentId: widget.appointmentId,
        currentUserId: widget.currentUserId,
        otherUserId: widget.otherUserId,
      );

  String? get _threadKey =>
      chatThreadKey(appointmentId: widget.appointmentId);

  @override
  void initState() {
    super.initState();
    final key = _threadKey;
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(activeChatProvider.notifier).enter(key);
      });
    }
  }

  @override
  void dispose() {
    final key = _threadKey;
    if (key != null) ref.read(activeChatProvider.notifier).leave(key);
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScrollToBottom(int newCount) {
    if (newCount == _previousMessageCount) return;
    _previousMessageCount = newCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _callSecureLine() async {
    if (_calling) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _calling = true);
    try {
      final res =
          await ref.read(chatProvider(_args).notifier).initiateMaskedCall();
      if (!mounted) return;
      final ok = res['success'] == true;
      final msg = res['message']?.toString() ??
          (ok
              ? 'Connecting via secure proxy line…'
              : 'Could not place the secure call.');
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Secure call failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final state = ref.watch(chatProvider(_args));
    _maybeScrollToBottom(state.messages.length);

    return SafeArea(
      left: false,
      child: Container(
        decoration: BoxDecoration(
          color: cc.bg,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _DrawerHeader(
              name: widget.otherUserName,
              avatarUrl: widget.otherUserAvatarUrl,
              roleLabel: widget.otherRoleLabel,
              isConnected: state.isConnected,
              isTyping: state.isOtherTyping,
              calling: _calling,
              onClose: () => Navigator.of(context).maybePop(),
              onSecureCall: _callSecureLine,
            ),
            Expanded(
              child: ChatMessageList(
                state: state,
                scrollController: _scrollController,
                currentUserId: widget.currentUserId,
                otherUserName: widget.otherUserName,
                otherUserAvatarUrl: widget.otherUserAvatarUrl,
                onRetry: () =>
                    ref.read(chatProvider(_args).notifier).refresh(),
              ),
            ),
            state.canSendMessages
                ? ChatInputBar(
                    args: _args,
                    controller: _inputController,
                    focusNode: _inputFocus,
                    isSending: state.isSending,
                  )
                : const ChatLockedFooter(),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String roleLabel;
  final bool isConnected;
  final bool isTyping;
  final bool calling;
  final VoidCallback onClose;
  final Future<void> Function() onSecureCall;

  const _DrawerHeader({
    required this.name,
    required this.avatarUrl,
    required this.roleLabel,
    required this.isConnected,
    required this.isTyping,
    required this.calling,
    required this.onClose,
    required this.onSecureCall,
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final statusText = isTyping
        ? 'Typing…'
        : (isConnected ? 'Online' : 'Offline');
    final statusColor = isTyping
        ? cc.brand
        : (isConnected ? const Color(0xFF34D399) : cc.ink3);

    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 6,
        12,
        10,
      ),
      decoration: BoxDecoration(
        color: cc.surface,
        border: Border(bottom: BorderSide(color: cc.line)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: cc.ink2),
            tooltip: 'Close',
          ),
          ChatAvatar(name: name, url: avatarUrl, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelLg.copyWith(
                    color: cc.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cc.brandSofter,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        roleLabel,
                        style: MtTextStyles.bodySm.copyWith(
                          color: cc.brand,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: MtTextStyles.bodySm.copyWith(
                        color: statusColor,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SecureCallButton(calling: calling, onTap: onSecureCall),
        ],
      ),
    );
  }
}

/// Prominent "Call via Secure Line" button — a filled brand pill that dials
/// the masked proxy bridge. Shows a spinner while the call is being placed.
class _SecureCallButton extends StatelessWidget {
  final bool calling;
  final Future<void> Function() onTap;
  const _SecureCallButton({required this.calling, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    return Material(
      color: cc.brand,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: calling ? null : () => onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (calling)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                const Icon(Icons.phone_in_talk, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                calling ? 'Connecting…' : 'Secure Line',
                style: MtTextStyles.bodySm.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
