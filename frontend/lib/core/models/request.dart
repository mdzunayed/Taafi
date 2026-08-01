import 'package:equatable/equatable.dart';
import 'service.dart';

class CareRequest extends Equatable {
  final String id;
  final String patientId;
  final ServiceType serviceType;
  final String location;
  final double? latitude;
  final double? longitude;
  final int durationHours;
  final bool asap;
  final DateTime? scheduledTime;
  final String status;
  final DateTime createdAt;
  final String? assignedDoctorId;

  const CareRequest({
    required this.id,
    required this.patientId,
    required this.serviceType,
    required this.location,
    this.latitude,
    this.longitude,
    required this.durationHours,
    this.asap = true,
    this.scheduledTime,
    this.status = 'pending',
    required this.createdAt,
    this.assignedDoctorId,
  });

  @override
  List<Object?> get props => [
    id,
    patientId,
    serviceType,
    location,
    latitude,
    longitude,
    durationHours,
    asap,
    scheduledTime,
    status,
    createdAt,
    assignedDoctorId,
  ];

  factory CareRequest.fromJson(Map<String, dynamic> json) {
    return CareRequest(
      id: json['id'] ?? '',
      patientId: json['patientId'] ?? '',
      serviceType: _parseServiceType(json['serviceType']),
      location: json['location'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      durationHours: json['durationHours'] ?? 1,
      asap: json['asap'] ?? true,
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.tryParse(json['scheduledTime'])
          : null,
      status: json['status'] ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      assignedDoctorId: json['assignedDoctorId'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'serviceType': serviceType.toString().split('.').last,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'durationHours': durationHours,
    'asap': asap,
    'scheduledTime': scheduledTime?.toIso8601String(),
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'assignedDoctorId': assignedDoctorId,
  };

  static ServiceType _parseServiceType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'wounddressing':
        return ServiceType.woundDressing;
      case 'vitalscheck':
        return ServiceType.vitalsCheck;
      case 'elderlycare':
        return ServiceType.elderlyCare;
      default:
        return ServiceType.postSurgery;
    }
  }
}
