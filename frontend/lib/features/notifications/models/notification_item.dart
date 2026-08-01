import 'package:equatable/equatable.dart';

/// One persisted notification row. Mirrors the backend's `Notification`
/// Mongoose schema. `payload` is a free-form map — the hub screen
/// reads `payload['appointmentId']` / `payload['deepLink']` to route
/// the user to the right place when they tap a card.
enum NotificationKind { appointment, chat, payment, systemBroadcast, unknown }

NotificationKind parseNotificationKind(String? wire) {
  switch (wire) {
    case 'appointment':
      return NotificationKind.appointment;
    case 'chat':
      return NotificationKind.chat;
    case 'payment':
      return NotificationKind.payment;
    case 'system_broadcast':
      return NotificationKind.systemBroadcast;
    default:
      return NotificationKind.unknown;
  }
}

String notificationKindToWire(NotificationKind kind) {
  switch (kind) {
    case NotificationKind.appointment:
      return 'appointment';
    case NotificationKind.chat:
      return 'chat';
    case NotificationKind.payment:
      return 'payment';
    case NotificationKind.systemBroadcast:
      return 'system_broadcast';
    case NotificationKind.unknown:
      return 'unknown';
  }
}

class NotificationItem extends Equatable {
  final String id;
  final String recipientId;
  final String? senderId;
  final String title;
  final String body;
  final NotificationKind kind;
  final bool isRead;
  final DateTime timestamp;
  final Map<String, dynamic> payload;

  const NotificationItem({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.body,
    required this.kind,
    required this.isRead,
    required this.timestamp,
    this.senderId,
    this.payload = const {},
  });

  NotificationItem copyWith({
    bool? isRead,
  }) {
    return NotificationItem(
      id: id,
      recipientId: recipientId,
      senderId: senderId,
      title: title,
      body: body,
      kind: kind,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp,
      payload: payload,
    );
  }

  @override
  List<Object?> get props => [
        id,
        recipientId,
        senderId,
        title,
        body,
        kind,
        isRead,
        timestamp,
        payload,
      ];

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parseTs(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    final rawPayload = json['payload'];
    final Map<String, dynamic> payload;
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      payload = const {};
    }
    return NotificationItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      recipientId: (json['recipientId'] ?? '').toString(),
      senderId: json['senderId']?.toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      kind: parseNotificationKind(json['type']?.toString()),
      isRead: (json['isRead'] as bool?) ?? false,
      timestamp: parseTs(json['timestamp']),
      payload: payload,
    );
  }
}
