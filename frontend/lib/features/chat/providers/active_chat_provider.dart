import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks which chat thread the signed-in user currently has open AND in
/// the foreground — the single source of truth the app-wide notification
/// chime consults so it stays silent for the room you're already looking
/// at, while every other arrival still rings.
///
/// State is a normalised *thread key* (see [chatThreadKey]) or `null` when
/// no chat is focused. It's deliberately root-scoped (not `autoDispose`):
/// the value has to survive across screen changes and be readable from the
/// notification hub, which lives outside the chat feature.
///
/// Backgrounding counts as "not focused": if a message lands while the app
/// is paused the chime should still fire, so a lifecycle transition off
/// `resumed` transparently clears the active key without the chat screen
/// having to unregister.
class ActiveChatController extends StateNotifier<String?>
    with WidgetsBindingObserver {
  ActiveChatController() : super(null) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// The thread a chat screen has claimed, independent of foreground state.
  String? _openKey;
  bool _foreground = true;

  /// Called by the chat screen when it mounts. Claims [key] as the focused
  /// thread.
  void enter(String key) {
    _openKey = key;
    _sync();
  }

  /// Called by the chat screen on dispose. Only clears if [key] still owns
  /// the slot — guards the race where a fast A→B navigation runs B.enter()
  /// before A.dispose() and A's leave would otherwise wipe B.
  void leave(String key) {
    if (_openKey == key) {
      _openKey = null;
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `state` here is the lifecycle arg, not the notifier's `state` field
    // (which `_sync` writes).
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() => state = _foreground ? _openKey : null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Root-scoped so the focused-thread value outlives individual screens and
/// is visible to the notification hub.
final activeChatProvider =
    StateNotifierProvider<ActiveChatController, String?>(
  (ref) => ActiveChatController(),
);

/// Build the normalised thread key for an open chat surface. Mirrors the two
/// [ChatArgs] modes: conversation-engine threads key on `conversationId`,
/// legacy appointment chats on `appointmentId`. Returns `null` when neither
/// id is present (nothing to track).
String? chatThreadKey({String? conversationId, String appointmentId = ''}) {
  if (conversationId != null && conversationId.isNotEmpty) {
    return 'c:$conversationId';
  }
  if (appointmentId.isNotEmpty) return 'a:$appointmentId';
  return null;
}

/// Build the same thread key from an inbound `new_notification` payload so
/// the hub can compare an arriving chat push against the active chat.
/// Conversation pushes carry `conversationId`; legacy appointment pushes
/// carry `appointmentId`.
String? chatThreadKeyFromPayload(Map<String, dynamic> payload) {
  final convo = payload['conversationId']?.toString();
  if (convo != null && convo.isNotEmpty) return 'c:$convo';
  final appt = payload['appointmentId']?.toString();
  if (appt != null && appt.isNotEmpty) return 'a:$appt';
  return null;
}
