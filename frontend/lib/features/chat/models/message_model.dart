import 'package:equatable/equatable.dart';

/// Rich message kind. TEXT, IMAGE and LOCATION are all sent + rendered; the
/// wire enum also reserves DOCUMENT for a future pass.
enum MessageType { text, image, document, location }

/// Structured payload for a [MessageType.location] message — the GPS fix the
/// sender shared plus a short human-readable address snippet. Mirrors the
/// backend `Message.locationCoordinates` sub-doc.
class LocationCoordinates extends Equatable {
  final double latitude;
  final double longitude;
  final String addressSnippet;

  const LocationCoordinates({
    required this.latitude,
    required this.longitude,
    this.addressSnippet = '',
  });

  bool get isValid => latitude != 0.0 || longitude != 0.0;

  @override
  List<Object?> get props => [latitude, longitude, addressSnippet];

  static LocationCoordinates? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final lat = (raw['latitude'] as num?)?.toDouble();
    final lng = (raw['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LocationCoordinates(
      latitude: lat,
      longitude: lng,
      addressSnippet: (raw['addressSnippet'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'addressSnippet': addressSnippet,
      };
}

MessageType _messageTypeFrom(dynamic raw) {
  switch (raw?.toString().toUpperCase()) {
    case 'IMAGE':
      return MessageType.image;
    case 'DOCUMENT':
      return MessageType.document;
    case 'LOCATION':
      return MessageType.location;
    case 'TEXT':
    default:
      return MessageType.text;
  }
}

/// One chat message. Serves BOTH thread models the backend shares in the
/// single `messages` collection:
///   • Appointment chat (legacy 1:1) — [appointmentId] + [receiverId] set.
///   • Conversation engine (multi-role / group) — [conversationId] set,
///     with the richer [senderRole] / [senderName] / [messageType] fields.
/// Wire shape mirrors the Mongoose `Message` schema; every ObjectId field
/// arrives stringified and `timestamp` is an ISO 8601 string.
class MessageModel extends Equatable {
  final String id;
  final String appointmentId;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String senderRole;
  final String senderName;
  final MessageType messageType;
  final String? attachmentUrl;
  final LocationCoordinates? locationCoordinates;
  final String messageText;
  final DateTime timestamp;
  final bool isRead;

  const MessageModel({
    required this.id,
    this.appointmentId = '',
    this.conversationId = '',
    required this.senderId,
    this.receiverId = '',
    this.senderRole = '',
    this.senderName = '',
    this.messageType = MessageType.text,
    this.attachmentUrl,
    this.locationCoordinates,
    required this.messageText,
    required this.timestamp,
    this.isRead = false,
  });

  /// Is this message coming FROM the supplied user — i.e. should it
  /// render right-aligned with the brand bubble?
  bool isMine(String currentUserId) => senderId == currentUserId;

  MessageModel copyWith({
    bool? isRead,
  }) =>
      MessageModel(
        id: id,
        appointmentId: appointmentId,
        conversationId: conversationId,
        senderId: senderId,
        receiverId: receiverId,
        senderRole: senderRole,
        senderName: senderName,
        messageType: messageType,
        attachmentUrl: attachmentUrl,
        locationCoordinates: locationCoordinates,
        messageText: messageText,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        conversationId,
        senderId,
        receiverId,
        senderRole,
        senderName,
        messageType,
        attachmentUrl,
        locationCoordinates,
        messageText,
        timestamp,
        isRead,
      ];

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    DateTime parseTs(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }

    return MessageModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      appointmentId: (json['appointmentId'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      receiverId: (json['receiverId'] ?? '').toString(),
      senderRole: (json['senderRole'] ?? '').toString(),
      senderName: (json['senderName'] ?? '').toString(),
      messageType: _messageTypeFrom(json['messageType']),
      attachmentUrl: (json['attachmentUrl'] as String?)?.isNotEmpty == true
          ? json['attachmentUrl'] as String
          : null,
      locationCoordinates:
          LocationCoordinates.fromJson(json['locationCoordinates']),
      messageText: (json['messageText'] ?? '').toString(),
      timestamp: parseTs(json['timestamp']),
      isRead: (json['isRead'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointmentId': appointmentId,
        'conversationId': conversationId,
        'senderId': senderId,
        'receiverId': receiverId,
        'senderRole': senderRole,
        'senderName': senderName,
        'messageType': messageType.name.toUpperCase(),
        'attachmentUrl': attachmentUrl,
        'locationCoordinates': locationCoordinates?.toJson(),
        'messageText': messageText,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };
}
