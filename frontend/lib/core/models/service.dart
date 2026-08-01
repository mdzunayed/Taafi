import 'package:equatable/equatable.dart';

enum ServiceType { postSurgery, woundDressing, vitalsCheck, elderlyCare }

enum ServiceStatusType {
  pendingReview,
  doctorAssigned,
  enroute,
  arrived,
  inService,
  completed
}

class Service extends Equatable {
  final String id;
  final String requestId;
  final String patientId;
  final String patientName;
  final int patientAge;
  final String? patientGender;
  final ServiceType serviceType;
  final ServiceStatusType status;
  final String doctorId;
  final String doctorName;
  final String? doctorPhone;
  final String? vehicleInfo;
  final DateTime requestedTime;
  final DateTime? startTime;
  final DateTime? endTime;
  final double price;
  final int durationHours;
  final String location;
  final double? latitude;
  final double? longitude;
  final int? estimatedMinutes;
  final bool withHelper;
  final List<String>? notes;

  const Service({
    required this.id,
    required this.requestId,
    required this.patientId,
    required this.patientName,
    required this.patientAge,
    this.patientGender,
    required this.serviceType,
    required this.status,
    required this.doctorId,
    required this.doctorName,
    this.doctorPhone,
    this.vehicleInfo,
    required this.requestedTime,
    this.startTime,
    this.endTime,
    required this.price,
    required this.durationHours,
    required this.location,
    this.latitude,
    this.longitude,
    this.estimatedMinutes,
    this.withHelper = false,
    this.notes,
  });

  @override
  List<Object?> get props => [
    id,
    requestId,
    patientId,
    patientName,
    patientAge,
    patientGender,
    serviceType,
    status,
    doctorId,
    doctorName,
    doctorPhone,
    vehicleInfo,
    requestedTime,
    startTime,
    endTime,
    price,
    durationHours,
    location,
    latitude,
    longitude,
    estimatedMinutes,
    withHelper,
    notes,
  ];

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] ?? '',
      requestId: json['requestId'] ?? '',
      patientId: json['patientId'] ?? '',
      patientName: json['patientName'] ?? '',
      patientAge: json['patientAge'] ?? 0,
      patientGender: json['patientGender'],
      serviceType: _parseServiceType(json['serviceType']),
      status: _parseStatusType(json['status']),
      doctorId: json['doctorId'] ?? '',
      doctorName: json['doctorName'] ?? '',
      doctorPhone: json['doctorPhone'],
      vehicleInfo: json['vehicleInfo'],
      requestedTime: DateTime.tryParse(json['requestedTime'] ?? '') ?? DateTime.now(),
      startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.tryParse(json['endTime']) : null,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      durationHours: json['durationHours'] ?? 1,
      location: json['location'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      estimatedMinutes: json['estimatedMinutes'],
      withHelper: json['withHelper'] ?? false,
      notes: (json['notes'] as List?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'requestId': requestId,
    'patientId': patientId,
    'patientName': patientName,
    'patientAge': patientAge,
    'patientGender': patientGender,
    'serviceType': serviceType.toString().split('.').last,
    'status': status.toString().split('.').last,
    'doctorId': doctorId,
    'doctorName': doctorName,
    'doctorPhone': doctorPhone,
    'vehicleInfo': vehicleInfo,
    'requestedTime': requestedTime.toIso8601String(),
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'price': price,
    'durationHours': durationHours,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'estimatedMinutes': estimatedMinutes,
    'withHelper': withHelper,
    'notes': notes,
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

  static ServiceStatusType _parseStatusType(String? statusStr) {
    switch (statusStr?.toLowerCase()) {
      case 'doctorassigned':
        return ServiceStatusType.doctorAssigned;
      case 'enroute':
        return ServiceStatusType.enroute;
      case 'arrived':
        return ServiceStatusType.arrived;
      case 'inservice':
        return ServiceStatusType.inService;
      case 'completed':
        return ServiceStatusType.completed;
      default:
        return ServiceStatusType.pendingReview;
    }
  }
}
