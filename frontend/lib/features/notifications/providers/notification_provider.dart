import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/notification_sound_service.dart';
import '../../../core/network/socket_manager.dart';
import '../../auth/auth_provider.dart';
import '../../chat/providers/active_chat_provider.dart';
import '../models/notification_item.dart';

/// Container for the notification hub state. Holds the full list plus
/// a denormalised `unreadCount` so AppBar badges can read it cheaply
/// without scanning the array.
@immutable
class NotificationState {
  final bool isLoading;
  final String? errorMessage;
  final List<NotificationItem> items;
  final int unreadCount;
  final bool socketConnected;

  const NotificationState({
    this.isLoading = false,
    this.errorMessage,
    this.items = const [],
    this.unreadCount = 0,
    this.socketConnected = false,
  });

  NotificationState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<NotificationItem>? items,
    int? unreadCount,
    bool? socketConnected,
  }) {
    return NotificationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      socketConnected: socketConnected ?? this.socketConnected,
    );
  }
}

/// App-wide notification engine. One instance per signed-in session —
/// when the auth state changes (sign-in / sign-out / token refresh)
/// Riverpod rebuilds the notifier and the old socket is disposed.
///
/// Responsibilities:
///   1. Fetch the persisted inbox over HTTP on mount.
///   2. Keep an open Socket.io connection registered to the user's
///      private room (`user:<accountId>`), listening for the
///      `new_notification` push event.
///   3. Expose `markRead(id)` and `markAllRead()` that optimistically
///      update local state, then write through to the backend.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier(this.ref, this.accountId) : super(const NotificationState()) {
    _bootstrap();
  }

  final Ref ref;
  final String accountId;
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _unreadSub;
  bool _disposed = false;

  Future<void> _bootstrap() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await refresh();
      _listenSocket();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Pulls the latest inbox from the server.
  Future<void> refresh() async {
    // No session yet (cold-start hydration window, or signed out): skip the
    // network call entirely so we never fire an unauthenticated request that
    // the server would 401. This notifier is keyed on `currentUserProvider`,
    // so Riverpod rebuilds it with a real account id the moment hydration
    // lands, and that rebuild fetches for real.
    if (accountId.isEmpty) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, clearError: true);
      return;
    }
    final client = ref.read(dioClientProvider);
    final body = await client.getNotifications(accountId: accountId);
    if (_disposed) return;
    final rawList = body['notifications'];
    final items = <NotificationItem>[];
    if (rawList is List) {
      for (final raw in rawList) {
        if (raw is Map) {
          try {
            items.add(
                NotificationItem.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {
            // Drop malformed rows; keep the rest of the inbox.
          }
        }
      }
    }
    final unread = body['unreadCount'] is num
        ? (body['unreadCount'] as num).toInt()
        : items.where((n) => !n.isRead).length;
    state = state.copyWith(
      isLoading: false,
      items: items,
      unreadCount: unread,
      clearError: true,
    );
  }

  /// Subscribe to the single app-wide authenticated socket
  /// ([socketManagerProvider]) for `new_notification` pushes instead of
  /// opening a second anonymous connection. The manager owns the JWT
  /// handshake + reconnection; this notifier just consumes the stream.
  void _listenSocket() {
    if (_notifSub != null) return;
    final manager = ref.read(socketManagerProvider);
    if (manager == null) return;
    state = state.copyWith(socketConnected: true);
    // Cross-session badge sync: another session/device marked the inbox read,
    // so the server pushes the authoritative unread count. A `count == 0`
    // (mark-all-read) also flips every local row read so the tiles agree with
    // the badge. On the device that originated the action this is a harmless
    // echo — it already cleared optimistically.
    _unreadSub = manager.onUnreadCount.listen((payload) {
      if (_disposed) return;
      final count = (payload['count'] as num?)?.toInt() ?? 0;
      if (count == 0) {
        state = state.copyWith(
          items: [for (final n in state.items) n.copyWith(isRead: true)],
          unreadCount: 0,
        );
      } else {
        state = state.copyWith(unreadCount: count);
      }
    });
    _notifSub = manager.onNotification.listen((payload) {
      if (_disposed) return;
      try {
        final item = NotificationItem.fromJson(payload);
        final list = [...state.items];
        final existingIdx = list.indexWhere((n) => n.id == item.id);
        final isBrandNew = existingIdx < 0;
        if (existingIdx >= 0) {
          list[existingIdx] = item;
        } else {
          list.insert(0, item);
        }
        final unread = list.where((n) => !n.isRead).length;
        state = state.copyWith(items: list, unreadCount: unread);
        // Sound feedback fires only for genuinely new arrivals — a
        // re-broadcast of an already-known row (server retry, etc.)
        // mustn't chime. Unread arrivals that are echoes of our own
        // recent action (e.g. our own chat send) also shouldn't ring,
        // so we additionally gate on `isRead == false`.
        //
        // Chat pushes carry the extra rule from the spec: stay SILENT for
        // the exact thread the user is already looking at (the backend fans
        // a `new_notification` to every recipient regardless of whether
        // they're in the room). Any other new chat — a different thread, or
        // this one while backgrounded — still rings, as do non-chat alerts.
        if (isBrandNew && !item.isRead && !_isViewingSource(item)) {
          // ignore: unawaited_futures
          ref.read(notificationSoundProvider).playBubble();
        }
      } catch (e) {
        assert(() {
          debugPrint('[notifications] parse failed: $e');
          return true;
        }());
      }
    });
  }

  /// True when [item] is a chat push for the thread the user currently has
  /// open and foregrounded — the one case the chime must skip. Non-chat
  /// notifications (and chats for any other thread) return `false`, so they
  /// ring normally.
  bool _isViewingSource(NotificationItem item) {
    if (item.kind != NotificationKind.chat) return false;
    final threadKey = chatThreadKeyFromPayload(item.payload);
    if (threadKey == null) return false;
    return threadKey == ref.read(activeChatProvider);
  }

  /// Optimistically flips one row to read and writes through to the
  /// backend. If the backend call fails the local state is rolled back
  /// (and the error surfaces in `state.errorMessage`).
  Future<void> markRead(String id) async {
    final prevList = state.items;
    final prevUnread = state.unreadCount;
    final updated = [
      for (final n in prevList)
        if (n.id == id && !n.isRead) n.copyWith(isRead: true) else n,
    ];
    final newUnread = updated.where((n) => !n.isRead).length;
    state = state.copyWith(items: updated, unreadCount: newUnread);
    try {
      await ref
          .read(dioClientProvider)
          .markHubNotificationRead(id, accountId: accountId);
    } catch (e) {
      if (_disposed) return;
      // Roll back so the bell badge stays truthful.
      state = state.copyWith(
        items: prevList,
        unreadCount: prevUnread,
        errorMessage: e.toString(),
      );
    }
  }

  /// Bulk mark — fires the backend write first; on success flips every
  /// local row to read in one state copy.
  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    final prevList = state.items;
    final prevUnread = state.unreadCount;
    state = state.copyWith(
      items: [for (final n in prevList) n.copyWith(isRead: true)],
      unreadCount: 0,
    );
    try {
      await ref
          .read(dioClientProvider)
          .markAllHubNotificationsRead(accountId: accountId);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        items: prevList,
        unreadCount: prevUnread,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Detach from the shared socket — the manager owns the connection's
    // lifecycle, so we only cancel our subscription, never disconnect it.
    // ignore: unawaited_futures
    _notifSub?.cancel();
    _notifSub = null;
    // ignore: unawaited_futures
    _unreadSub?.cancel();
    _unreadSub = null;
    super.dispose();
  }
}

/// Notifier keyed off the signed-in account. `null` when no one is
/// signed in — the AppBar bell + hub screen render their empty/locked
/// states in that case.
final notificationProvider = StateNotifierProvider.autoDispose<
    NotificationNotifier, NotificationState>((ref) {
  final user = ref.watch(currentUserProvider);
  // Account id of empty string means "no session" — the notifier
  // gracefully no-ops in that case (HTTP returns 401, socket connects
  // but is never registered), but we still want a NotificationNotifier
  // so widgets can call `state.unreadCount` without a null check.
  final accountId = user?.id ?? '';
  return NotificationNotifier(ref, accountId);
});

/// Convenience selector for the AppBar bell.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationProvider).unreadCount;
});
