import 'dart:async';

import 'package:dio/dio.dart';

import '../models/home_section.dart';
import '../utils/image_upload.dart';

/// REST-backed CRUD for admin-managed dynamic home sections.
///
/// Like [PromoBannerRepository], the REST API doesn't push changes, so we
/// keep an in-memory cache and expose it as a Stream. Every mutation
/// (create/update/delete/setStatus/reorder) triggers a refetch that re-emits
/// the latest list. Callers can also pull a fresh snapshot with [refresh].
///
/// The write endpoints are admin-gated on the backend, so this repository is
/// constructed with the **authenticated** Dio (JWT interceptor).
class HomeSectionRepository {
  final Dio _dio;
  final StreamController<List<HomeSection>> _allCtrl =
      StreamController<List<HomeSection>>.broadcast();
  final StreamController<List<HomeSection>> _activeCtrl =
      StreamController<List<HomeSection>>.broadcast();

  List<HomeSection> _cache = const [];

  /// The failure from the constructor-time fetch, if it happened before any
  /// watcher subscribed. Broadcast controllers drop events with no listener,
  /// so without replaying this in [watchAll]/[watchActive] a boot-time
  /// failure surfaces as a silently-empty list instead of an error state.
  /// (Same guard as [ServiceCatalogRepository].)
  Object? _initialError;

  HomeSectionRepository(this._dio) {
    // Fire-and-forget initial fetch — swallow its error so a failed/absent
    // `/api/home-sections` (e.g. 404 when the route isn't deployed) can't
    // surface as an uncaught error at app boot. The failure is kept in
    // [_initialError] for the watchers to replay.
    unawaited(refresh().catchError((_) => const <HomeSection>[]));
  }

  Stream<List<HomeSection>> watchAll() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<HomeSection>>.error(initialError);
    } else {
      yield _sortedAll(_cache);
    }
    yield* _allCtrl.stream;
  }

  Stream<List<HomeSection>> watchActive() async* {
    final initialError = _initialError;
    if (initialError != null && _cache.isEmpty) {
      yield* Stream<List<HomeSection>>.error(initialError);
    } else {
      yield _sortedActive(_cache);
    }
    yield* _activeCtrl.stream;
  }

  Future<List<HomeSection>> refresh() async {
    try {
      final res = await _dio.get<List<dynamic>>('/api/home-sections');
      final list = (res.data ?? const [])
          .map((e) => HomeSection.fromJson(Map<String, dynamic>.from(e as Map)))
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

  List<HomeSection> _sortedAll(List<HomeSection> src) {
    final list = [...src]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return List.unmodifiable(list);
  }

  List<HomeSection> _sortedActive(List<HomeSection> src) =>
      _sortedAll(src.where((s) => s.isActive).toList());

  void _broadcast() {
    _allCtrl.add(_sortedAll(_cache));
    _activeCtrl.add(_sortedActive(_cache));
  }

  Future<HomeSection> create(HomeSection draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/home-sections',
        data: draft.toJson(),
      );
      final created = HomeSection.fromJson(res.data!);
      await refresh();
      return created;
    } on DioException {
      // Rethrow with status code intact so the form dialog can surface a
      // specific message (409 duplicate key, 401/403 auth, ...).
      rethrow;
    }
  }

  Future<HomeSection> update(HomeSection section) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/home-sections/${section.id}',
        data: section.toJson(),
      );
      final updated = HomeSection.fromJson(res.data!);
      await refresh();
      return updated;
    } on DioException {
      rethrow;
    }
  }

  Future<void> delete(HomeSection section) async {
    try {
      await _dio.delete('/api/home-sections/${section.id}');
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  Future<void> setStatus(String id, bool isActive) async {
    try {
      await _dio.patch(
        '/api/home-sections/$id/status',
        data: {'isActive': isActive},
      );
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  /// Switches how a section arranges its cards.
  ///
  /// Separate from [update] so changing a layout can't clobber `contentData`
  /// from a stale editor — the same reasoning as [setStatus].
  Future<void> setLayout(String id, HomeLayoutType layoutType) async {
    try {
      await _dio.patch(
        '/api/home-sections/$id/layout',
        data: {'layoutType': layoutType.wire},
      );
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  /// Sets the Care Services layout, creating the reserved `CARE_SERVICES`
  /// section if this deployment doesn't have one yet.
  ///
  /// Care Services predates the CMS — it has always rendered the live catalog
  /// — so on an existing install there is no document to [setLayout] onto.
  /// Rather than make an operator hand-create a section with a magic key
  /// before the layout selector does anything, the backend upserts it. See
  /// `PUT /api/home-sections/care-services`.
  Future<HomeSection> setCareServicesLayout(HomeLayoutType layoutType) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/home-sections/care-services',
        data: {'layoutType': layoutType.wire},
      );
      final saved = HomeSection.fromJson(res.data!);
      await refresh();
      return saved;
    } on DioException {
      rethrow;
    }
  }

  /// Persists a new section order — [ids] is the full list of section ids in
  /// their desired top-to-bottom sequence; the backend renumbers
  /// `orderIndex` to match (0..n-1).
  Future<void> reorder(List<String> ids) async {
    try {
      await _dio.patch('/api/home-sections/reorder', data: {'ids': ids});
      await refresh();
    } on DioException {
      rethrow;
    }
  }

  /// Upload-first image flow: stores the picked image under a public_id
  /// derived from [itemId] and returns the URL the draft item should
  /// reference in `contentData` when the section is saved.
  Future<String> uploadItemImage(PreparedImage image, String itemId) async {
    final form = FormData.fromMap({
      'itemId': itemId,
      'image': image.toMultipart(),
    });
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/home-sections/images',
        data: form,
      );
      return res.data!['imageUrl'] as String;
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
