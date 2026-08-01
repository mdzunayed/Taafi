import 'dart:async';

import 'package:dio/dio.dart';

import '../models/service_catalog_item.dart';
import '../utils/image_upload.dart';

/// REST-backed CRUD for the service catalog.
///
/// The REST API doesn't push changes, so we maintain an in-memory cache and
/// expose it as a Stream. Every mutation (create/update/delete/setStatus)
/// triggers a refetch which re-emits the latest list. Callers can also pull
/// a fresh snapshot with [refresh].
class ServiceCatalogRepository {
  final Dio _dio;
  final StreamController<List<ServiceCatalogItem>> _allCtrl =
      StreamController<List<ServiceCatalogItem>>.broadcast();
  final StreamController<List<ServiceCatalogItem>> _activeCtrl =
      StreamController<List<ServiceCatalogItem>>.broadcast();

  List<ServiceCatalogItem> _cache = const [];

  /// The failure from the constructor-time fetch, if it happened before any
  /// watcher subscribed. Broadcast controllers drop events with no listener,
  /// so without replaying this in [watchAll]/[watchActive] a boot-time
  /// failure surfaces as a silently-empty catalog instead of an error state.
  Object? _initialError;

  ServiceCatalogRepository(this._dio) {
    // Kick off an initial fetch so subscribers don't sit empty. Fire-and-
    // forget must swallow the rejection: refresh() rethrows, and an
    // unawaited throw here becomes an uncaught async error at app boot
    // whenever the backend is unreachable (the same defect
    // PromoBannerRepository already guards against). The failure is kept in
    // [_initialError] for the watchers to replay.
    unawaited(refresh().catchError((_) => const <ServiceCatalogItem>[]));
  }

  Stream<List<ServiceCatalogItem>> watchAll() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<ServiceCatalogItem>>.error(initialError);
    } else {
      yield _cache;
    }
    yield* _allCtrl.stream;
  }

  Stream<List<ServiceCatalogItem>> watchActive() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<ServiceCatalogItem>>.error(initialError);
    } else {
      yield _cache.where((s) => s.isActive).toList();
    }
    yield* _activeCtrl.stream;
  }

  Future<List<ServiceCatalogItem>> refresh() async {
    try {
      final res = await _dio.get<List<dynamic>>('/api/services');
      final list = (res.data ?? const [])
          .map((e) => ServiceCatalogItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache = list;
      _initialError = null;
      _broadcast();
      return list;
    } on DioException catch (e) {
      if (_cache.isEmpty) _initialError = _toMessage(e);
      _allCtrl.addError(_toMessage(e));
      _activeCtrl.addError(_toMessage(e));
      rethrow;
    }
  }

  void _broadcast() {
    _allCtrl.add(List.unmodifiable(_cache));
    _activeCtrl.add(List.unmodifiable(_cache.where((s) => s.isActive)));
  }

  Future<ServiceCatalogItem> create({
    required String title,
    required double price,
    String description = '',
    String category = '',
    String? duration,
    ServiceCatalogStatus status = ServiceCatalogStatus.active,
    required PreparedImage image,
  }) async {
    final form = FormData.fromMap({
      'title': title,
      'price': price.toString(),
      'description': description,
      'category': category,
      if (duration != null) 'duration': duration,
      'status': status.name,
      'image': image.toMultipart(),
    });
    try {
      final res = await _dio.post<Map<String, dynamic>>('/api/services', data: form);
      final created = ServiceCatalogItem.fromJson(res.data!);
      await refresh();
      return created;
    } on DioException catch (e) {
      throw _toMessage(e);
    }
  }

  Future<ServiceCatalogItem> update(
    ServiceCatalogItem item, {
    PreparedImage? newImage,
  }) async {
    final form = FormData.fromMap({
      'title': item.title,
      'price': item.price.toString(),
      'description': item.description,
      'category': item.category,
      'duration': item.duration ?? '',
      'status': item.status.name,
      if (newImage != null) 'image': newImage.toMultipart(),
    });
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/services/${item.id}',
        data: form,
      );
      final updated = ServiceCatalogItem.fromJson(res.data!);
      await refresh();
      return updated;
    } on DioException catch (e) {
      throw _toMessage(e);
    }
  }

  Future<void> delete(ServiceCatalogItem item) async {
    try {
      await _dio.delete('/api/services/${item.id}');
      await refresh();
    } on DioException catch (e) {
      throw _toMessage(e);
    }
  }

  Future<void> setStatus(String id, ServiceCatalogStatus status) async {
    try {
      await _dio.patch(
        '/api/services/$id/status',
        data: {'status': status.name},
      );
      await refresh();
    } on DioException catch (e) {
      throw _toMessage(e);
    }
  }

  String _toMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    return e.message ?? 'Network error';
  }

  void dispose() {
    _allCtrl.close();
    _activeCtrl.close();
  }
}
