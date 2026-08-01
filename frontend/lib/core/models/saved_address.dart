import 'package:equatable/equatable.dart';

/// One entry in the patient's saved-address ledger (`GET /api/addresses`).
class SavedAddress extends Equatable {
  final String id;
  final String label;
  final String fullAddressText;
  final String flatFloorHolding;
  final String landmarkInstructions;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  const SavedAddress({
    required this.id,
    this.label = 'Home',
    this.fullAddressText = '',
    this.flatFloorHolding = '',
    this.landmarkInstructions = '',
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// A single-line summary for list rows.
  String get summary {
    final parts = <String>[
      if (flatFloorHolding.trim().isNotEmpty) flatFloorHolding.trim(),
      if (fullAddressText.trim().isNotEmpty) fullAddressText.trim(),
    ];
    return parts.isEmpty ? 'No address details' : parts.join(', ');
  }

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      label: (json['label'] ?? 'Home').toString(),
      fullAddressText: (json['full_address_text'] ?? '').toString(),
      flatFloorHolding: (json['flat_floor_holding'] ?? '').toString(),
      landmarkInstructions: (json['landmark_instructions'] ?? '').toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isDefault: (json['is_default'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        label,
        fullAddressText,
        flatFloorHolding,
        landmarkInstructions,
        latitude,
        longitude,
        isDefault,
      ];
}
