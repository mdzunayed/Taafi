import 'dart:async';

import 'package:dio/dio.dart';

import '../models/home_category.dart';

/// REST-backed CRUD for the admin-managed Home filter pills.
///
/// Mirrors [HomeSectionRepository]: an in-memory cache exposed as a Stream,
/// with every mutation triggering a refetch that re-emits the list, because
/// the REST API doesn't push. The write endpoints are admin-gated on the
/// backend, so this is constructed with the **authenticated** Dio.
class CategoryRepository {
  final Dio _dio;
  final StreamController<List<HomeCategory>> _allCtrl =
      StreamController<List<HomeCategory>>.broadcast();

  List<HomeCategory> _cache = const [];

  /// The failure from the constructor-time fetch, if it happened before any
  /// watcher subscribed. Broadcast controllers drop events with no listener,
  /// so without replaying this in [watchAll] a boot-time failure surfaces as a
  /// silently-empty list instead of an error state. (Same guard as
  /// [HomeSectionRepository].)
  Object? _initialError;

  CategoryRepository(this._dio) {
    unawaited(refresh().catchError((_) => const <HomeCategory>[]));
  }

  Stream<List<HomeCategory>> watchAll() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<HomeCategory>>.error(initialError);
    } else {
      yield _sorted(_cache);
    }
    yield* _allCtrl.stream;
  }

  Future<List<HomeCategory>> refresh() async {
    try {
      final res = await _dio.get<List<dynamic>>('/api/categories');
      final list = (res.data ?? const [])
          .map((e) => HomeCategory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _cache = list;
      _initialError = null;
      _allCtrl.add(_sorted(list));
      return list;
    } on DioException catch (e) {
      if (_cache.isEmpty) _initialError = _toMessage(e);
      _allCtrl.addError(_toMessage(e));
      rethrow;
    }
  }

  List<HomeCategory> _sorted(List<HomeCategory> src) {
    final list = [...src]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return List.unmodifiable(list);
  }

  Future<HomeCategory> create(HomeCategory draft) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/categories',
      data: draft.toJson(),
    );
    final created = HomeCategory.fromJson(res.data!);
    await refresh();
    return created;
  }

  Future<HomeCategory> update(HomeCategory category) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/api/categories/${category.id}',
      data: category.toJson(),
    );
    final updated = HomeCategory.fromJson(res.data!);
    await refresh();
    return updated;
  }

  Future<void> delete(HomeCategory category) async {
    await _dio.delete('/api/categories/${category.id}');
    await refresh();
  }

  Future<void> setStatus(String id, bool isActive) async {
    await _dio.patch(
      '/api/categories/$id/status',
      data: {'isActive': isActive},
    );
    await refresh();
  }

  /// Persists a new rail order — [ids] is the full list in its desired
  /// left-to-right sequence; the backend renumbers `displayOrder` (0..n-1).
  Future<void> reorder(List<String> ids) async {
    await _dio.patch('/api/categories/reorder', data: {'ids': ids});
    await refresh();
  }

  String _toMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    return e.message ?? 'Network error';
  }

  void dispose() => _allCtrl.close();
}
