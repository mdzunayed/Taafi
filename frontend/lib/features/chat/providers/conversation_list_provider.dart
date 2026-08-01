import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/socket_manager.dart';
import '../../auth/auth_provider.dart';
import '../models/conversation_model.dart';

/// Async UI status for the inbox surface.
enum InboxStatus { loading, ready, error }

@immutable
class ConversationListState {
  final InboxStatus status;
  final List<ConversationModel> conversations;
  final String? errorMessage;

  const ConversationListState({
    this.status = InboxStatus.loading,
    this.conversations = const [],
    this.errorMessage,
  });

  /// Total unread across every thread — drives the inbox tab badge.
  int get totalUnread =>
      conversations.fold(0, (sum, c) => sum + c.unreadCount);

  ConversationListState copyWith({
    InboxStatus? status,
    List<ConversationModel>? conversations,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationListState(
      status: status ?? this.status,
      conversations: conversations ?? this.conversations,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Loads the signed-in user's conversation inbox and keeps unread badges
/// live by subscribing to the ONE app-wide authenticated socket's
/// `new_notification` stream (no second connection) — a chat notification
/// bumps the matching thread's unread + floats it to the top.
class ConversationListNotifier extends StateNotifier<ConversationListState> {
  ConversationListNotifier(this.ref) : super(const ConversationListState()) {
    _load();
    _subscribeToLiveUpdates();
  }

  final Ref ref;
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  bool _disposed = false;

  Future<void> _load() async {
    state = state.copyWith(status: InboxStatus.loading, clearError: true);
    try {
      final client = ref.read(dioClientProvider);
      final raw = await client.getConversations();
      final parsed = <ConversationModel>[];
      for (final r in raw) {
        try {
          parsed.add(ConversationModel.fromJson(r));
        } catch (_) {
          // skip a malformed row, keep the rest of the inbox
        }
      }
      if (_disposed) return;
      state = state.copyWith(
        status: InboxStatus.ready,
        conversations: parsed,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: InboxStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void _subscribeToLiveUpdates() {
    final manager = ref.read(socketManagerProvider);
    _notifSub = manager?.onNotification.listen((payload) {
      if (_disposed) return;
      final type = payload['type']?.toString();
      if (type != 'chat') return;
      final convoId = _extractConversationId(payload);
      if (convoId == null) return;
      _bumpUnread(convoId, payload);
    });
  }

  String? _extractConversationId(Map<String, dynamic> payload) {
    final data = payload['payload'];
    if (data is Map && data['conversationId'] != null) {
      return data['conversationId'].toString();
    }
    return null;
  }

  /// Increment a thread's unread count + move it to the top. If the thread
  /// isn't in our cached list yet (brand-new conversation), reload from the
  /// server so it appears.
  void _bumpUnread(String conversationId, Map<String, dynamic> payload) {
    final list = [...state.conversations];
    final idx = list.indexWhere((c) => c.id == conversationId);
    if (idx < 0) {
      // Unknown thread — pull a fresh inbox.
      _load();
      return;
    }
    final updated = list[idx].copyWith(unreadCount: list[idx].unreadCount + 1);
    list.removeAt(idx);
    list.insert(0, updated);
    state = state.copyWith(conversations: list);
  }

  /// Optimistically clear a thread's unread badge (called when the user
  /// opens it). The server + socket `conversation:read` already zero it
  /// server-side; this keeps the inbox in sync without a reload.
  void markReadLocally(String conversationId) {
    final list = [
      for (final c in state.conversations)
        c.id == conversationId ? c.copyWith(unreadCount: 0) : c,
    ];
    state = state.copyWith(conversations: list);
  }

  Future<void> refresh() => _load();

  @override
  void dispose() {
    _disposed = true;
    _notifSub?.cancel();
    super.dispose();
  }
}

final conversationListProvider = StateNotifierProvider.autoDispose<
    ConversationListNotifier, ConversationListState>((ref) {
  // Keep the app-wide socket alive while the inbox is mounted so live
  // unread updates keep flowing.
  ref.watch(socketManagerProvider);
  return ConversationListNotifier(ref);
});
