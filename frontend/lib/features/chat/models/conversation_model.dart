import 'package:equatable/equatable.dart';

/// Normalised participant role the client reasons about — mirrors the
/// backend `PARTICIPANT_ROLES` (patient / provider / admin / support).
enum ParticipantRole { patient, provider, admin, support }

ParticipantRole participantRoleFrom(dynamic raw) {
  switch (raw?.toString().toLowerCase()) {
    case 'provider':
      return ParticipantRole.provider;
    case 'admin':
      return ParticipantRole.admin;
    case 'support':
      return ParticipantRole.support;
    case 'patient':
    default:
      return ParticipantRole.patient;
  }
}

/// One member of a conversation. Name + avatar are snapshots taken at
/// join/open time so the inbox renders without an extra lookup.
class ConversationParticipant extends Equatable {
  final String userId;
  final ParticipantRole role;
  final String name;
  final String avatarUrl;

  const ConversationParticipant({
    required this.userId,
    required this.role,
    required this.name,
    this.avatarUrl = '',
  });

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      userId: (json['userId'] ?? '').toString(),
      role: participantRoleFrom(json['role']),
      name: (json['name'] ?? 'Member').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [userId, role, name, avatarUrl];
}

/// A conversation thread header (the inbox row + chat-screen context).
/// Individual messages are loaded separately via the messages endpoint.
class ConversationModel extends Equatable {
  final String id;
  final List<ConversationParticipant> participants;
  final String? contextRequestId;
  final String lastMessageText;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final bool isActive;

  /// The signed-in user's unread count for this thread (server-computed).
  final int unreadCount;

  const ConversationModel({
    required this.id,
    required this.participants,
    this.contextRequestId,
    this.lastMessageText = '',
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.isActive = true,
    this.unreadCount = 0,
  });

  /// The "other side" of the thread from [meUserId]'s perspective — used
  /// for the inbox row title/avatar. For a 1:1 this is the single other
  /// participant; for a group it's the first non-me participant (the row
  /// then also shows a group count).
  ConversationParticipant? otherParticipant(String meUserId) {
    for (final p in participants) {
      if (p.userId != meUserId) return p;
    }
    return participants.isNotEmpty ? participants.first : null;
  }

  /// A display title: the other member's name for a 1:1, or a
  /// comma-joined member list for a group.
  String titleFor(String meUserId) {
    final others =
        participants.where((p) => p.userId != meUserId).toList();
    if (others.isEmpty) return 'Conversation';
    if (others.length == 1) return others.first.name;
    return others.map((p) => p.name.split(' ').first).join(', ');
  }

  bool get isGroup => participants.length > 2;

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString());
    }

    final rawParts = json['participants'];
    final parts = <ConversationParticipant>[];
    if (rawParts is List) {
      for (final p in rawParts) {
        if (p is Map) {
          parts.add(
            ConversationParticipant.fromJson(Map<String, dynamic>.from(p)),
          );
        }
      }
    }

    final ctx = (json['contextRequestId'] ?? '').toString();
    final lastSender = (json['lastMessageSenderId'] ?? '').toString();

    return ConversationModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      participants: parts,
      contextRequestId: ctx.isEmpty ? null : ctx,
      lastMessageText: (json['lastMessageText'] ?? '').toString(),
      lastMessageSenderId: lastSender.isEmpty ? null : lastSender,
      lastMessageAt: parseTs(json['lastMessageAt']),
      isActive: (json['isActive'] as bool?) ?? true,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  ConversationModel copyWith({int? unreadCount}) => ConversationModel(
        id: id,
        participants: participants,
        contextRequestId: contextRequestId,
        lastMessageText: lastMessageText,
        lastMessageSenderId: lastMessageSenderId,
        lastMessageAt: lastMessageAt,
        isActive: isActive,
        unreadCount: unreadCount ?? this.unreadCount,
      );

  @override
  List<Object?> get props => [
        id,
        participants,
        contextRequestId,
        lastMessageText,
        lastMessageSenderId,
        lastMessageAt,
        isActive,
        unreadCount,
      ];
}
