import 'dart:async';

import 'package:dio/dio.dart';

import '../models/patient_home_data.dart';

/// Reads the one-shot patient Home payload (`GET /api/home-data`).
///
/// Same in-memory-cache-as-a-Stream shape as [HomeSectionRepository] and
/// [PromoBannerRepository]: the REST API doesn't push, so a snapshot is held
/// and re-emitted, and [refresh] pulls a fresh one for pull-to-refresh.
///
/// It differs from its siblings in one deliberate way: a failed fetch is NOT
/// an error state. Home renders the categories and the Care Services layout
/// from this endpoint, but the cards themselves are still available from
/// `/api/services`, so a 404 (a backend that predates this route) or a network
/// blip degrades to [PatientHomeData.fallback] — the compiled chip rail and
/// the catalog — instead of replacing the top of Home with a retry card.
/// Anything that genuinely can't render is handled by the providers that own
/// it.
class HomeDataRepository {
  final Dio _dio;
  final StreamController<PatientHomeData> _ctrl =
      StreamController<PatientHomeData>.broadcast();

  PatientHomeData _cache = PatientHomeData.fallback;

  /// False until the first fetch settles, either way.
  bool _loaded = false;

  HomeDataRepository(this._dio) {
    unawaited(refresh());
  }

  Stream<PatientHomeData> watch() async* {
    // Deliberately silent until the first fetch settles, so watchers sit in
    // `AsyncLoading` and render a skeleton. Yielding the fallback immediately
    // would paint the compiled two-chip rail and the unfiltered catalog for a
    // frame, then swap both for the live ones — a visible flash on every cold
    // start, and the exact thing the aggregate endpoint exists to avoid.
    if (_loaded) yield _cache;
    yield* _ctrl.stream;
  }

  Future<PatientHomeData> refresh() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/home-data');
      _cache = PatientHomeData.fromJson(res.data ?? const {});
    } on DioException {
      // Degrade, don't error — see the class doc. The previous snapshot is
      // kept when there is one, so a transient failure mid-session doesn't
      // collapse a live rail back to the compiled two.
      if (!_loaded) _cache = PatientHomeData.fallback;
    } catch (_) {
      if (!_loaded) _cache = PatientHomeData.fallback;
    }
    _loaded = true;
    _ctrl.add(_cache);
    return _cache;
  }

  void dispose() => _ctrl.close();
}
