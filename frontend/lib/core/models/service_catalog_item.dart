import 'package:equatable/equatable.dart';

enum ServiceCatalogStatus { active, inactive }

class ServiceCatalogItem extends Equatable {
  final String id;
  final String title;
  final double price;
  final String description;
  final String category;
  final String? duration;
  final String? imageUrl;
  final ServiceCatalogStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServiceCatalogItem({
    required this.id,
    required this.title,
    required this.price,
    this.description = '',
    this.category = '',
    this.duration,
    this.imageUrl,
    this.status = ServiceCatalogStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == ServiceCatalogStatus.active;

  ServiceCatalogItem copyWith({
    String? id,
    String? title,
    double? price,
    String? description,
    String? category,
    String? duration,
    String? imageUrl,
    ServiceCatalogStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceCatalogItem(
      id: id ?? this.id,
      title: title ?? this.title,
      price: price ?? this.price,
      description: description ?? this.description,
      category: category ?? this.category,
      duration: duration ?? this.duration,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ServiceCatalogItem.fromJson(Map<String, dynamic> json) {
    return ServiceCatalogItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      description: (json['description'] ?? '') as String,
      category: (json['category'] ?? '') as String,
      duration: json['duration'] as String?,
      imageUrl: json['imageUrl'] as String?,
      status: _parseStatus(json['status'] as String?),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  static ServiceCatalogStatus _parseStatus(String? raw) {
    if (raw == ServiceCatalogStatus.inactive.name) {
      return ServiceCatalogStatus.inactive;
    }
    return ServiceCatalogStatus.active;
  }

  @override
  List<Object?> get props => [
        id,
        title,
        price,
        description,
        category,
        duration,
        imageUrl,
        status,
        createdAt,
        updatedAt,
      ];
}
