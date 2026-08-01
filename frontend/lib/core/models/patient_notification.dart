import 'package:equatable/equatable.dart';

enum PatientNotificationKind { request, provider, system }

extension PatientNotificationKindX on PatientNotificationKind {
  String toWire() {
    switch (this) {
      case PatientNotificationKind.request:
        return 'request';
      case PatientNotificationKind.provider:
        return 'provider';
      case PatientNotificationKind.system:
        return 'system';
    }
  }

  static PatientNotificationKind fromWire(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'request':
        return PatientNotificationKind.request;
      case 'provider':
        return PatientNotificationKind.provider;
      default:
        return PatientNotificationKind.system;
    }
  }
}

class PatientNotification extends Equatable {
  final String id;
  final PatientNotificationKind kind;
  final String titleEn;
  final String? titleBn;
  final String bodyEn;
  final String? bodyBn;
  final DateTime createdAt;
  final bool read;
  final Map<String, dynamic>? payload;

  const PatientNotification({
    required this.id,
    required this.kind,
    required this.titleEn,
    required this.bodyEn,
    required this.createdAt,
    this.read = false,
    this.titleBn,
    this.bodyBn,
    this.payload,
  });

  PatientNotification copyWith({bool? read}) {
    return PatientNotification(
      id: id,
      kind: kind,
      titleEn: titleEn,
      titleBn: titleBn,
      bodyEn: bodyEn,
      bodyBn: bodyBn,
      createdAt: createdAt,
      read: read ?? this.read,
      payload: payload,
    );
  }

  @override
  List<Object?> get props =>
      [id, kind, titleEn, titleBn, bodyEn, bodyBn, createdAt, read, payload];

  factory PatientNotification.fromJson(Map<String, dynamic> json) {
    return PatientNotification(
      id: json['id']?.toString() ?? '',
      kind: PatientNotificationKindX.fromWire(json['kind']?.toString()),
      titleEn: json['titleEn']?.toString() ?? '',
      titleBn: json['titleBn']?.toString(),
      bodyEn: json['bodyEn']?.toString() ?? '',
      bodyBn: json['bodyBn']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.toWire(),
        'titleEn': titleEn,
        'titleBn': titleBn,
        'bodyEn': bodyEn,
        'bodyBn': bodyBn,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'payload': payload,
      };
}
