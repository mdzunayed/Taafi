import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/promo_banner.dart';
import '../utils/image_upload.dart';

/// REST-backed CRUD for admin-managed promo banners.
///
/// Like [ServiceCatalogRepository], the REST API doesn't push changes, so we
/// keep an in-memory cache and expose it as a Stream. Every mutation
/// (create/update/delete/setStatus/reorder) triggers a refetch that re-emits
/// the latest list. Callers can also pull a fresh snapshot with [refresh].
///
/// The write endpoints are admin-gated on the backend, so this repository is
/// constructed with the **authenticated** Dio (JWT interceptor).
class PromoBannerRepository {
  final Dio _dio;
  final StreamController<List<PromoBanner>> _allCtrl =
      StreamController<List<PromoBanner>>.broadcast();
  final StreamController<List<PromoBanner>> _activeCtrl =
      StreamController<List<PromoBanner>>.broadcast();

  List<PromoBanner> _cache = const [];

  /// The failure from the constructor-time fetch, if it happened before any
  /// watcher subscribed. Broadcast controllers drop events with no listener,
  /// so without replaying this in [watchAll]/[watchActive] a boot-time
  /// failure surfaces as a silently-empty list instead of an error state.
  /// (Same guard as [ServiceCatalogRepository].)
  Object? _initialError;

  PromoBannerRepository(this._dio) {
    // Kick off an initial fetch so subscribers don't sit empty. `refresh()`
    // rethrows on failure for explicit callers (pull-to-refresh), but this one
    // is fire-and-forget — swallow its error here so a failed/absent
    // `/api/promo-banners` (e.g. 404 when the route isn't deployed) can't
    // surface as an "Uncaught (in promise)" error at app boot. The failure is
    // kept in [_initialError] for the watchers to replay.
    unawaited(refresh().catchError((_) => const <PromoBanner>[]));
  }

  Stream<List<PromoBanner>> watchAll() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<PromoBanner>>.error(initialError);
    } else {
      yield _sortedAll(_cache);
    }
    yield* _allCtrl.stream;
  }

  Stream<List<PromoBanner>> watchActive() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<PromoBanner>>.error(initialError);
    } else {
      yield _sortedActive(_cache);
    }
    yield* _activeCtrl.stream;
  }

  Future<List<PromoBanner>> refresh() async {
    try {
      final res = await _dio.get<List<dynamic>>('/api/promo-banners');
      final list = (res.data ?? const [])
          .map((e) => PromoBanner.fromJson(Map<String, dynamic>.from(e as Map)))
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

  List<PromoBanner> _sortedAll(List<PromoBanner> src) {
    final list = [...src]
      ..sort((a, b) => a.priorityOrder.compareTo(b.priorityOrder));
    return List.unmodifiable(list);
  }

  List<PromoBanner> _sortedActive(List<PromoBanner> src) =>
      _sortedAll(src.where((b) => b.isActive).toList());

  void _broadcast() {
    _allCtrl.add(_sortedAll(_cache));
    _activeCtrl.add(_sortedActive(_cache));
  }

  Future<PromoBanner> create({
    required String tagText,
    required String title,
    required String buttonText,
    required List<String> gradientColors,
    bool isActive = true,
    BannerActionType actionType = BannerActionType.service,
    String? targetServiceId,
    String? targetCategoryId,
    String targetUrl = '',
    String promoCode = '',
    PreparedImage? image,
  }) async {
    final form = FormData.fromMap({
      'tagText': tagText,
      'title': title,
      'buttonText': buttonText,
      'gradientColors': jsonEncode(gradientColors),
      'isActive': isActive.toString(),
      'actionType': actionType.wireValue,
      'targetServiceId': targetServiceId ?? '',
      'targetCategoryId': targetCategoryId ?? '',
      'targetUrl': targetUrl,
      'promoCode': promoCode,
      if (image != null) 'image': image.toMultipart(),
    });
    try {
      final res =
          await _dio.post<Map<String, dynamic>>('/api/promo-banners', data: form);
      final created = PromoBanner.fromJson(res.data!);
      await refresh();
      return created;
    } on DioException {
      // Rethrow the raw DioException (status code intact) so the form can map
      // 404/401/500 to a specific, human-readable toast via [mapBannerError].
      // The stream-error paths (refresh) still stringify via [_toMessage].
      rethrow;
    }
  }

  Future<PromoBanner> update(
    PromoBanner banner, {
    PreparedImage? newImage,
  }) async {
    final form = FormData.fromMap({
      'tagText': banner.tagText,
      'title': banner.title,
      'buttonText': banner.buttonText,
      'gradientColors': jsonEncode(banner.gradientColors),
      'isActive': banner.isActive.toString(),
      'actionType': banner.actionType.wireValue,
      'targetServiceId': banner.targetServiceId ?? '',
      'targetCategoryId': banner.targetCategoryId ?? '',
      'targetUrl': banner.targetUrl,
      'promoCode': banner.promoCode,
      if (newImage != null) 'image': newImage.toMultipart(),
    });
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/promo-banners/${banner.id}',
        data: form,
      );
      final updated = PromoBanner.fromJson(res.data!);
      await refresh();
      return updated;
    } on DioException {
      rethrow;
    }
  }

  Future<void> delete(PromoBanner banner) async {
    try {
      await _dio.delete('/api/promo-banners/${banner.id}');
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  Future<void> setStatus(String id, bool isActive) async {
    try {
      await _dio.patch(
        '/api/promo-banners/$id/status',
        data: {'isActive': isActive},
      );
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  /// Persists a new banner order — [ids] is the full list of banner ids in
  /// their desired top-to-bottom sequence; the backend renumbers
  /// `priorityOrder` to match (0..n-1).
  Future<void> reorder(List<String> ids) async {
    try {
      await _dio.patch('/api/promo-banners/reorder', data: {'ids': ids});
      await refresh();
    } on DioException {
      rethrow;
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
