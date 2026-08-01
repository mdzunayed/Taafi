import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/storage/app_prefs.dart';
import '../../auth/auth_provider.dart';
import '../models/message_model.dart';

/// Async UI status for the chat surface. Mirrors the AsyncValue pattern
/// used elsewhere in the app but as a flat enum so the screen can
/// switch on it cheaply.
enum ChatStatus { idle, loading, ready, error }

/// Immutable state container for one open chat (one appointment +
/// participant pair).
@immutable
class ChatState {
  final ChatStatus status;
  final List<MessageModel> messages;
  final String? errorMessage;
  final bool isConnected;
  final bool isSending;

  /// Live appointment status as broadcast by
  /// `appointment_status_change`. Drives the chat input lockdown:
  /// when the value transitions to `completed`, the input pane is
  /// disabled on BOTH sides and the conversation reads as a
  /// historical transcript. `null` means the status hasn't been
  /// reported yet (defaults to "open for messaging").
  final String? appointmentStatus;

  /// Server-driven access-control lock, delivered by the
  /// `channel_locked` / `channel_unlocked` socket events (backed by
  /// `CareRequest.communicationChannel.isLocked`). This is the
  /// server-of-truth reinforcing [appointmentStatus] — the moment the
  /// visit is completed/cancelled the backend flips this and both apps
  /// close their input bars. `null` = not yet reported.
  final bool? isChannelLocked;

  /// The other party is currently typing (appointment path). Cleared on
  /// a short timeout and on every inbound message.
  final bool isOtherTyping;

  const ChatState({
    this.status = ChatStatus.idle,
    this.messages = const [],
    this.errorMessage,
    this.isConnected = false,
    this.isSending = false,
    this.appointmentStatus,
    this.isChannelLocked,
    this.isOtherTyping = false,
  });

  /// `true` when the visit is still in-flight — accepted /
  /// on-the-way / arrived / in-service. The chat is read-only once
  /// the status flips to `completed` / `cancelled` / `rejected`, or the
  /// server explicitly locks the communication channel.
  bool get canSendMessages {
    if (isChannelLocked == true) return false;
    final s = appointmentStatus;
    if (s == null) return true;
    const closed = {'completed', 'cancelled', 'rejected'};
    return !closed.contains(s);
  }

  ChatState copyWith({
    ChatStatus? status,
    List<MessageModel>? messages,
    String? errorMessage,
    bool clearError = false,
    bool? isConnected,
    bool? isSending,
    String? appointmentStatus,
    bool? isChannelLocked,
    bool? isOtherTyping,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isConnected: isConnected ?? this.isConnected,
      isSending: isSending ?? this.isSending,
      appointmentStatus: appointmentStatus ?? this.appointmentStatus,
      isChannelLocked: isChannelLocked ?? this.isChannelLocked,
      isOtherTyping: isOtherTyping ?? this.isOtherTyping,
    );
  }
}

/// Per-thread key — one `(appointmentId | conversationId, currentUserId)`
/// pair gets one notifier instance. `autoDispose` cleans the socket when
/// the user navigates away.
///
/// Two modes, selected by which id is supplied:
///   • Appointment chat (legacy 1:1) — [appointmentId] + [otherUserId] set,
///     [conversationId] null. Uses the `join_room` / `send_message` events.
///   • Conversation engine (multi-role / group) — [conversationId] set,
///     [appointmentId] empty. Uses the `conversation:*` events; there is no
///     single [otherUserId] (fan-out is server-derived).
class ChatArgs {
  final String appointmentId;
  final String currentUserId;
  final String otherUserId;
  final String? conversationId;

  const ChatArgs({
    this.appointmentId = '',
    required this.currentUserId,
    this.otherUserId = '',
    this.conversationId,
  });

  /// True when this notifier drives a conversation-engine thread rather
  /// than the legacy appointment chat.
  bool get isConversation =>
      conversationId != null && conversationId!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ChatArgs &&
      other.appointmentId == appointmentId &&
      other.currentUserId == currentUserId &&
      other.otherUserId == otherUserId &&
      other.conversationId == conversationId;

  @override
  int get hashCode =>
      Object.hash(appointmentId, currentUserId, otherUserId, conversationId);
}

/// Riverpod notifier driving the chat surface. Owns the Socket.io
/// connection lifecycle: opens on creation, joins the appointment room,
/// listens for `receive_message`, and tears everything down on dispose.
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this.ref, this.args) : super(const ChatState()) {
    _bootstrap();
  }

  final Ref ref;
  final ChatArgs args;
  io.Socket? _socket;
  bool _disposed = false;

  // Auto-clears the "other party is typing" bubble if their "stopped"
  // event goes missing.
  Timer? _incomingTypingTimer;
  // Debounces our OUTBOUND typing signal so a burst of keystrokes fans out
  // at most one `isTyping:true` + a trailing `isTyping:false`.
  Timer? _outgoingTypingTimer;
  bool _typingBroadcast = false;

  // The Dio client + the socket connection both target the same
  // backend host. We pull the base URL out of DioClient so a single
  // `--dart-define=API_BASE_URL=…` covers both transports.
  static const String _socketBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://taafi-backend.onrender.com',
  );

  Future<void> _bootstrap() async {
    state = state.copyWith(status: ChatStatus.loading, clearError: true);
    try {
      await _loadHistory();
      _connectSocket();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // --- HTTP history --------------------------------------------------------

  Future<void> _loadHistory() async {
    final client = ref.read(dioClientProvider);
    final rawList = args.isConversation
        ? await client.getConversationMessages(args.conversationId!)
        : await client.getChatHistory(args.appointmentId);
    final parsed = <MessageModel>[];
    for (final raw in rawList) {
      try {
        parsed.add(MessageModel.fromJson(raw));
      } catch (_) {
        // Skip a malformed row, keep the rest of the conversation.
      }
    }
    if (_disposed) return;
    state = state.copyWith(
      status: ChatStatus.ready,
      messages: parsed,
    );
  }

  // --- Socket lifecycle ----------------------------------------------------

  void _connectSocket() {
    if (_socket != null) return;
    // Attach the JWT when we have one so the backend can verify conversation
    // membership + auto-join the user room. The legacy appointment path works
    // with or without it (the server allows anonymous join_room sockets).
    final token = ref.read(tokenProvider);
    final optsBuilder = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(1500);
    if (token != null && token.isNotEmpty) {
      optsBuilder.setAuth({'token': token});
    }
    final socket = io.io(_socketBaseUrl, optsBuilder.build());

    socket.onConnect((_) {
      if (_disposed) return;
      state = state.copyWith(isConnected: true);
      if (args.isConversation) {
        socket.emit('conversation:join', args.conversationId);
        // Opening the thread clears our unread badge for it.
        socket.emit('conversation:read', {
          'conversationId': args.conversationId,
          'userId': args.currentUserId,
        });
      } else {
        socket.emit('join_room', args.appointmentId);
        // Opening the thread marks every inbound message read (their ticks
        // turn blue) and clears our own unread badge for this booking.
        socket.emit('mark_chat_read', {
          'appointmentId': args.appointmentId,
          'userId': args.currentUserId,
        });
      }
    });

    socket.on('receive_message', (payload) {
      if (_disposed) return;
      if (payload is! Map) return;
      try {
        final incoming =
            MessageModel.fromJson(Map<String, dynamic>.from(payload));
        // Any inbound message means the other party stopped typing.
        if (state.isOtherTyping) {
          state = state.copyWith(isOtherTyping: false);
        }
        // While this thread is open, immediately acknowledge inbound
        // messages as read so the sender sees the blue ticks live.
        if (!args.isConversation &&
            incoming.senderId != args.currentUserId &&
            _socket != null) {
          _socket!.emit('mark_chat_read', {
            'appointmentId': args.appointmentId,
            'userId': args.currentUserId,
          });
        }
        // De-dupe — the optimistic local row gets replaced by the
        // canonical one if their ids match (or appointmentId+text+sender
        // collision for the fallback case).
        final list = [...state.messages];
        final existingIdx = list.indexWhere((m) => m.id == incoming.id);
        if (existingIdx >= 0) {
          list[existingIdx] = incoming;
        } else {
          list.add(incoming);
        }
        state = state.copyWith(messages: list);
        // No chime here on purpose: this listener only ever fires for the
        // chat that's currently OPEN, and the spec wants the focused room
        // silent. The app-wide notification hub owns the chime and rings
        // only for threads you're NOT looking at (it consults
        // `activeChatProvider`).
      } catch (e) {
        assert(() {
          debugPrint('[chat] failed to parse incoming message: $e');
          return true;
        }());
      }
    });

    // Provider-driven status transitions broadcast by
    // `PATCH /api/appointments/:id/update-status`. The chat input
    // gate watches `state.canSendMessages`; the moment the visit
    // flips to `completed` the send button + text field disable
    // automatically on both sides — no extra round-trip needed.
    socket.on('appointment_status_change', (payload) {
      if (_disposed) return;
      if (payload is! Map) return;
      final apptId = payload['appointmentId']?.toString();
      if (apptId != args.appointmentId) return;
      final wireStatus = payload['status']?.toString().toLowerCase();
      if (wireStatus == null || wireStatus.isEmpty) return;
      state = state.copyWith(appointmentStatus: wireStatus);
    });

    // Server-of-truth access-control lock. `channel_locked` /
    // `channel_unlocked` are emitted by the booking lifecycle hooks
    // (assign → unlock, complete/cancel → lock). Flips the input bar to the
    // read-only archive banner on both apps without a manual refresh.
    void handleChannel(dynamic payload, bool locked) {
      if (_disposed || args.isConversation) return;
      if (payload is! Map) return;
      if (payload['appointmentId']?.toString() != args.appointmentId) return;
      state = state.copyWith(isChannelLocked: locked);
    }

    socket.on('channel_locked', (payload) => handleChannel(payload, true));
    socket.on('channel_unlocked', (payload) => handleChannel(payload, false));

    // Typing indicator relay (appointment path). Ignore our own echo; a
    // fresh `isTyping:true` (re)arms the auto-clear timer so a dropped
    // "stopped typing" event can't strand the bubble on-screen.
    socket.on('user_typing', (payload) {
      if (_disposed || args.isConversation) return;
      if (payload is! Map) return;
      if (payload['appointmentId']?.toString() != args.appointmentId) return;
      if (payload['userId']?.toString() == args.currentUserId) return;
      final typing = payload['isTyping'] == true;
      state = state.copyWith(isOtherTyping: typing);
      _incomingTypingTimer?.cancel();
      if (typing) {
        _incomingTypingTimer = Timer(const Duration(seconds: 4), () {
          if (!_disposed && state.isOtherTyping) {
            state = state.copyWith(isOtherTyping: false);
          }
        });
      }
    });

    // Read receipt (appointment path) — the other party opened the thread,
    // so flip our OWN sent messages to read (blue ticks). Mirrors the
    // conversation-engine `conversation:read` handler below.
    socket.on('chat_read', (payload) {
      if (_disposed || args.isConversation) return;
      if (payload is! Map) return;
      if (payload['appointmentId']?.toString() != args.appointmentId) return;
      if (payload['userId']?.toString() == args.currentUserId) return;
      final list = [
        for (final m in state.messages)
          m.isMine(args.currentUserId) && !m.isRead
              ? m.copyWith(isRead: true)
              : m,
      ];
      state = state.copyWith(messages: list);
    });

    // Read receipt from another participant — flip our OWN sent messages to
    // read so the delivery ticks turn blue. Only relevant in conversation
    // mode; ignore our own read echoes.
    socket.on('conversation:read', (payload) {
      if (_disposed || !args.isConversation) return;
      if (payload is! Map) return;
      if (payload['conversationId']?.toString() != args.conversationId) return;
      if (payload['userId']?.toString() == args.currentUserId) return;
      final list = [
        for (final m in state.messages)
          m.isMine(args.currentUserId) && !m.isRead
              ? m.copyWith(isRead: true)
              : m,
      ];
      state = state.copyWith(messages: list);
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      state = state.copyWith(isConnected: false);
    });

    socket.onConnectError((err) {
      assert(() {
        debugPrint('[chat] socket connect error: $err');
        return true;
      }());
    });

    socket.onError((err) {
      assert(() {
        debugPrint('[chat] socket error: $err');
        return true;
      }());
    });

    _socket = socket;
    socket.connect();
  }

  // --- Send ----------------------------------------------------------------

  /// Send a plain TEXT message. Kept as `sendMessage` for the existing
  /// `ChatScreen` call site.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // Stop broadcasting "typing" the instant we actually send.
    _stopTyping();
    await _emitSend(messageText: trimmed);
  }

  /// Send an IMAGE message. [mediaUrl] comes from
  /// `DioClient.uploadChatAttachment`; [caption] is optional. Appointment
  /// path only (the conversation engine keeps text-only for now).
  Future<void> sendImage(String mediaUrl, {String caption = ''}) async {
    if (mediaUrl.isEmpty) return;
    _stopTyping();
    await _emitSend(
      messageText: caption.trim(),
      messageType: 'IMAGE',
      attachmentUrl: mediaUrl,
    );
  }

  /// Send a LOCATION message from a device GPS fix. Appointment path only.
  Future<void> sendLocation(
    double latitude,
    double longitude, {
    String addressSnippet = '',
  }) async {
    _stopTyping();
    await _emitSend(
      messageText: addressSnippet.trim(),
      messageType: 'LOCATION',
      locationCoordinates: {
        'latitude': latitude,
        'longitude': longitude,
        'addressSnippet': addressSnippet.trim(),
      },
    );
  }

  /// Shared send path for every message kind. Builds the right payload for
  /// the appointment vs conversation transport, emits with an ack, and
  /// manages the `isSending` flag + safety timeout.
  Future<void> _emitSend({
    required String messageText,
    String messageType = 'TEXT',
    String? attachmentUrl,
    Map<String, dynamic>? locationCoordinates,
  }) async {
    // Spec guardrail — once the visit is completed/cancelled (status close
    // OR the server locked the channel) the conversation is read-only on
    // both sides. The UI disables the input too, but this is the client-side
    // half of the server-of-truth gate.
    if (!state.canSendMessages) return;
    final socket = _socket;
    if (socket == null) return;

    state = state.copyWith(isSending: true);
    final completer = Completer<void>();
    final event = args.isConversation ? 'conversation:send' : 'send_message';
    final Map<String, dynamic> payload;
    if (args.isConversation) {
      payload = {
        'conversationId': args.conversationId,
        'senderId': args.currentUserId,
        'messageText': messageText,
      };
    } else {
      payload = {
        'appointmentId': args.appointmentId,
        'senderId': args.currentUserId,
        'receiverId': args.otherUserId,
        'messageText': messageText,
        'messageType': messageType,
      };
      if (attachmentUrl != null) payload['attachmentUrl'] = attachmentUrl;
      if (locationCoordinates != null) {
        payload['locationCoordinates'] = locationCoordinates;
      }
    }
    socket.emitWithAck(
      event,
      payload,
      ack: (response) {
        if (_disposed) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        if (response is Map && response['ok'] == false) {
          state = state.copyWith(
            isSending: false,
            errorMessage: response['message']?.toString() ?? 'Send failed',
          );
        } else {
          // Success — the `receive_message` broadcast we'll see in a
          // moment carries the canonical row. Nothing else to do.
          state = state.copyWith(isSending: false, clearError: true);
        }
        if (!completer.isCompleted) completer.complete();
      },
    );
    // Safety timeout — without an ack from the server we shouldn't hang
    // the UI's "Sending…" indicator forever.
    Future<void>.delayed(const Duration(seconds: 8)).then((_) {
      if (!completer.isCompleted) {
        completer.complete();
        if (!_disposed && state.isSending) {
          state = state.copyWith(isSending: false);
        }
      }
    });
    return completer.future;
  }

  // --- Typing indicator ----------------------------------------------------

  /// Call on every keystroke while composing. Debounced: emits one
  /// `isTyping:true` immediately, then a trailing `isTyping:false` ~2.5s
  /// after typing stops. Appointment path only.
  void notifyTyping() {
    if (args.isConversation) return;
    final socket = _socket;
    if (socket == null || !state.canSendMessages) return;
    if (!_typingBroadcast) {
      _typingBroadcast = true;
      socket.emit('typing_indicator', {
        'appointmentId': args.appointmentId,
        'userId': args.currentUserId,
        'isTyping': true,
      });
    }
    _outgoingTypingTimer?.cancel();
    _outgoingTypingTimer =
        Timer(const Duration(milliseconds: 2500), _stopTyping);
  }

  void _stopTyping() {
    _outgoingTypingTimer?.cancel();
    if (!_typingBroadcast) return;
    _typingBroadcast = false;
    final socket = _socket;
    if (socket != null && !args.isConversation) {
      socket.emit('typing_indicator', {
        'appointmentId': args.appointmentId,
        'userId': args.currentUserId,
        'isTyping': false,
      });
    }
  }

  // --- Masked calling ------------------------------------------------------

  /// Bridge a masked proxy voice call to the other booking party. Returns
  /// the server response map (`{ success, status, proxyDisplay, message }`).
  /// Throws on transport error so the caller can surface it.
  Future<Map<String, dynamic>> initiateMaskedCall() async {
    final client = ref.read(dioClientProvider);
    return client.initiateMaskedCall(args.appointmentId);
  }

  /// Re-load history from the server (pull-to-refresh).
  Future<void> refresh() async {
    try {
      await _loadHistory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _incomingTypingTimer?.cancel();
    _outgoingTypingTimer?.cancel();
    final socket = _socket;
    if (socket != null) {
      try {
        if (args.isConversation) {
          socket.emit('conversation:leave', args.conversationId);
          socket.off('conversation:read');
        } else {
          // Best-effort "stopped typing" so we don't strand a bubble on the
          // other side after we leave.
          if (_typingBroadcast) {
            socket.emit('typing_indicator', {
              'appointmentId': args.appointmentId,
              'userId': args.currentUserId,
              'isTyping': false,
            });
          }
          socket.emit('leave_room', args.appointmentId);
          socket.off('channel_locked');
          socket.off('channel_unlocked');
          socket.off('user_typing');
          socket.off('chat_read');
        }
        socket.off('receive_message');
        socket.off('appointment_status_change');
        socket.disconnect();
        socket.dispose();
      } catch (_) {
        // Best-effort cleanup — failure here is harmless because we're
        // tearing down anyway.
      }
      _socket = null;
    }
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, ChatArgs>(
  (ref, args) => ChatNotifier(ref, args),
);
