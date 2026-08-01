import 'package:equatable/equatable.dart';

/// The admin-managed full-screen interstitial shown once when the patient
/// app launches. Mirrors the backend `AppOpenAd` singleton document (which
/// emits camelCase keys + an `id` via its `toJSON` transform).
class AppOpenAd extends Equatable {
  final String id;
  final String imageUrl;

  /// Seconds the interstitial holds the screen before auto-dismissing to
  /// Home. The backend clamps this to 1..60.
  final int durationInSeconds;
  final bool isActive;
  final DateTime? updatedAt;

  const AppOpenAd({
    required this.id,
    required this.imageUrl,
    this.durationInSeconds = 5,
    this.isActive = false,
    this.updatedAt,
  });

  factory AppOpenAd.fromJson(Map<String, dynamic> json) {
    return AppOpenAd(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '') as String,
      durationInSeconds: (json['durationInSeconds'] as num?)?.toInt() ?? 5,
      isActive: json['isActive'] as bool? ?? false,
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, imageUrl, durationInSeconds, isActive, updatedAt];
}
