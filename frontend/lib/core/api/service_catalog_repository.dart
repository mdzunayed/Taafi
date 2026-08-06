import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/provider_type.dart';
import '../models/service_catalog_item.dart';
import '../utils/image_upload.dart';

/// Why a catalog read failed, split so the UI (and a bug report) can tell a
/// genuinely offline phone from a server fault from a client-side parse bug.
/// The old code collapsed all three into the literal string `'Network error'`,
/// which is why the Home screen's failure was undiagnosable in the field.
enum ServiceCatalogFailure {
  /// No usable connection: DNS, TLS, socket, or a timeout.
  network,

  /// We reached the server and it answered with a 4xx/5xx.
  server,

  /// Rate limiter (HTTP 429) — retryable, but not by hammering.
  throttled,

  /// The response arrived but wasn't the shape we expect.
  malformedResponse,

  /// Anything unclassified.
  unknown,
}

/// Typed catalog error. Thrown as an object (never a bare String) so
/// `AsyncValue.error` carries a real stack trace to the error boundary.
class ServiceCatalogException implements Exception {
  /// User-facing copy. Safe to render verbatim.
  final String message;
  final ServiceCatalogFailure kind;
  final int? statusCode;

  /// The underlying error, kept for logs/telemetry — never shown to the user.
  final Object? cause;

  const ServiceCatalogException(
    this.message, {
    this.kind = ServiceCatalogFailure.unknown,
    this.statusCode,
    this.cause,
  });

  /// Whether a plain "Retry" tap has a realistic chance of succeeding.
  bool get isRetryable =>
      kind == ServiceCatalogFailure.network ||
      kind == ServiceCatalogFailure.throttled ||
      (statusCode != null && statusCode! >= 500);

  /// Message-only, so existing call sites that stringify the error (the
  /// shared [MtErrorState] renders `e.toString()`) show clean copy rather than
  /// an exception dump.
  @override
  String toString() => message;
}

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

  /// Dedupes concurrent refreshes. Home mounts several consumers at once
  /// (the Care Services rail, the dynamic home sections, the route
  /// dispatcher) and a pull-to-refresh can land on top of the boot fetch —
  /// without this they each issue their own GET and race to write [_cache],
  /// which also burns the per-IP rate-limit budget several times over.
  Future<List<ServiceCatalogItem>>? _inFlight;

  Future<List<ServiceCatalogItem>> refresh() {
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  /// [refresh] for fire-and-forget callers — Retry buttons and pull-to-refresh.
  ///
  /// The failure has already been pushed onto the watched streams (or, when a
  /// stale list is still on screen, deliberately suppressed), so the rejection
  /// here carries no new information; letting it escape a `VoidCallback` would
  /// just raise an unhandled async error.
  Future<void> refreshQuietly() async {
    try {
      await refresh();
    } catch (_) {
      // Already surfaced through watchAll/watchActive.
    }
  }

  Future<List<ServiceCatalogItem>> _refresh() async {
    try {
      // Deliberately `dynamic`, NOT `List<dynamic>`. Dio casts `response.data`
      // to the type argument internally, so asking for a List meant any
      // non-list body (an error envelope, an HTML 502 page from the proxy, a
      // future `{data: [...]}` wrapper) threw a TypeError *inside* Dio that
      // resurfaced as a DioExceptionType.unknown with a NULL message — which
      // the old `_toMessage` then reported as the bare "Network error" seen on
      // Home. We take the body untyped and validate its shape ourselves.
      final res = await _dio.get<dynamic>('/api/services');
      final rows = _extractRows(res.data);

      final list = <ServiceCatalogItem>[];
      var skipped = 0;
      for (final row in rows) {
        if (row is! Map) {
          skipped++;
          continue;
        }
        try {
          list.add(ServiceCatalogItem.fromJson(Map<String, dynamic>.from(row)));
        } catch (e, st) {
          // Per-row isolation: one unparseable document must never blank the
          // catalog for every user. Drop it, keep the rest.
          skipped++;
          _logDev('dropped a malformed service row', e, st);
        }
      }

      if (skipped > 0) {
        _logDev('skipped $skipped/${rows.length} malformed service row(s)');
      }

      // Every row failing to parse is a real fault, not an empty catalog —
      // surface it instead of rendering a bogus "no services" state.
      if (list.isEmpty && rows.isNotEmpty) {
        throw const ServiceCatalogException(
          'Services are temporarily unavailable. Please try again.',
          kind: ServiceCatalogFailure.malformedResponse,
        );
      }

      _cache = list;
      _initialError = null;
      _broadcast();
      return list;
    } catch (e, st) {
      final failure = _toException(e);
      _logDev('catalog refresh failed', e, st);

      // Stale-while-error: a failed refresh must not wipe a list that is
      // already on screen. Re-emit what we have and let the returned Future
      // carry the failure to whoever asked for the refresh.
      if (_cache.isNotEmpty) {
        _broadcast();
        throw failure;
      }

      _initialError = failure;
      _allCtrl.addError(failure, st);
      _activeCtrl.addError(failure, st);
      throw failure;
    }
  }

  /// Accepts the bare JSON array the API returns today, and tolerates the
  /// common envelope shapes so a backend change can't blank the Home screen
  /// of every already-installed app build.
  static List<dynamic> _extractRows(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      for (final key in const ['data', 'services', 'items', 'results']) {
        final nested = body[key];
        if (nested is List) return nested;
      }
    }
    if (body == null) return const [];
    throw ServiceCatalogException(
      'Services are temporarily unavailable. Please try again.',
      kind: ServiceCatalogFailure.malformedResponse,
      cause: 'Expected a JSON array, got ${body.runtimeType}',
    );
  }

  /// Dev-only diagnostics. `assert` keeps the whole call out of release
  /// builds while making parse bugs impossible to miss in debug — the failure
  /// mode this fix exists to stop is a model bug masquerading as a dropout.
  void _logDev(String label, [Object? error, StackTrace? st]) {
    assert(() {
      debugPrint('[services] $label${error == null ? '' : ': $error'}');
      if (st != null) debugPrintStack(stackTrace: st, maxFrames: 12);
      return true;
    }());
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
    List<String> categoryIds = const [],
    bool isUrgentAvailable = false,
    ProviderType? providerType,
    String? duration,
    ServiceCatalogStatus status = ServiceCatalogStatus.active,
    required PreparedImage image,
  }) async {
    final form = FormData.fromMap({
      'title': title,
      'price': price.toString(),
      'description': description,
      'category': category,
      'categoryIds': jsonEncode(categoryIds),
      'isUrgentAvailable': isUrgentAvailable.toString(),
      // Empty means "leave untagged" — the API keeps inferring a role from the
      // title/category rather than freezing an unreviewed guess.
      'provider_type': providerType?.toWire() ?? '',
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
      throw _toException(e);
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
      // Always sent, even when empty. Multipart drops an absent key, and the
      // API reads "absent" as "leave the assignment alone" — so omitting it
      // would make un-ticking every pill impossible. A JSON string rather than
      // repeated fields for the same reason: `[]` has to survive the wire.
      'categoryIds': jsonEncode(item.categoryIds),
      'isUrgentAvailable': item.isUrgentAvailable.toString(),
      'provider_type': item.providerType?.toWire() ?? '',
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
      throw _toException(e);
    }
  }

  Future<void> delete(ServiceCatalogItem item) async {
    try {
      await _dio.delete('/api/services/${item.id}');
      await refresh();
    } on DioException catch (e) {
      throw _toException(e);
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
      throw _toException(e);
    }
  }

  /// Classifies any thrown object into a typed [ServiceCatalogException] with
  /// copy a patient can act on.
  ///
  /// The previous version returned `e.message ?? 'Network error'`, which had
  /// two defects: `DioException.message` is null for
  /// `DioExceptionType.unknown`, so real client-side faults were mislabelled
  /// as connectivity problems; and a timeout, a 500 and a 429 were all
  /// indistinguishable on screen.
  ServiceCatalogException _toException(Object e) {
    if (e is ServiceCatalogException) return e;

    if (e is DioException) {
      final status = e.response?.statusCode;

      // Prefer the server's own copy when it sent a JSON envelope.
      final data = e.response?.data;
      String? serverMessage;
      if (data is Map && data['message'] is String) {
        final m = (data['message'] as String).trim();
        if (m.isNotEmpty) serverMessage = m;
      }

      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ServiceCatalogException(
            'The server took too long to respond. Check your connection and try again.',
            kind: ServiceCatalogFailure.network,
            cause: e,
          );
        case DioExceptionType.connectionError:
        case DioExceptionType.badCertificate:
          return ServiceCatalogException(
            "Can't reach the server. Check your internet connection and try again.",
            kind: ServiceCatalogFailure.network,
            cause: e,
          );
        case DioExceptionType.cancel:
          return ServiceCatalogException(
            'The request was cancelled.',
            kind: ServiceCatalogFailure.unknown,
            cause: e,
          );
        case DioExceptionType.badResponse:
          if (status == 429) {
            return ServiceCatalogException(
              serverMessage ?? 'Too many requests — please wait a moment and try again.',
              kind: ServiceCatalogFailure.throttled,
              statusCode: status,
              cause: e,
            );
          }
          return ServiceCatalogException(
            serverMessage ??
                (status != null && status >= 500
                    ? 'The server is having trouble right now. Please try again shortly.'
                    : 'Services are temporarily unavailable. Please try again.'),
            kind: ServiceCatalogFailure.server,
            statusCode: status,
            cause: e,
          );
        case DioExceptionType.unknown:
          // Almost always a client-side fault wrapped by Dio (a response cast,
          // a JSON decode). `e.message` is null here — the old code's blind
          // spot — so never fall back to it.
          return ServiceCatalogException(
            serverMessage ?? 'Services are temporarily unavailable. Please try again.',
            kind: e.error == null
                ? ServiceCatalogFailure.network
                : ServiceCatalogFailure.malformedResponse,
            statusCode: status,
            cause: e.error ?? e,
          );
      }
    }

    // A TypeError / FormatException escaping the parser lands here. It is a
    // client bug, not a dropout — say so, and keep the real cause for the log.
    return ServiceCatalogException(
      'Services are temporarily unavailable. Please try again.',
      kind: ServiceCatalogFailure.malformedResponse,
      cause: e,
    );
  }

  void dispose() {
    _allCtrl.close();
    _activeCtrl.close();
  }
}
