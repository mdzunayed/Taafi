// Regression tests for the "CARE SERVICES — Couldn't load / Network error"
// defect on the patient Home screen.
//
// The catalog is read by every patient, and the old pipeline was all-or-
// nothing: `ServiceCatalogItem.fromJson` used unchecked casts (`as String`,
// `as num?`), and the repository mapped the whole list eagerly, so ONE
// malformed Mongo document threw a TypeError that blanked Care Services for
// everyone. These tests pin the coercion rules and the per-row isolation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/api/service_catalog_repository.dart';
import 'package:taafi/core/models/service_catalog_item.dart';

/// Minimal fake transport so the repository can be exercised without a server.
/// Returns [body] for `GET /api/services`, or throws [error] when set.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.body, this.statusCode = 200});

  final Object? body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioReturning(Object? body, {int statusCode = 200}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _StubAdapter(body: body, statusCode: statusCode);
  return dio;
}

Map<String, dynamic> _row(Map<String, dynamic> overrides) => {
      'id': 's1',
      'title': 'Lab sample collection',
      'price': 1200,
      'status': 'active',
      ...overrides,
    };

void main() {
  group('ServiceCatalogItem.fromJson never throws', () {
    test('price accepts a String, including grouped and currency-prefixed', () {
      expect(ServiceCatalogItem.fromJson(_row({'price': '1200'})).price, 1200);
      expect(ServiceCatalogItem.fromJson(_row({'price': '1,200'})).price, 1200);
      expect(ServiceCatalogItem.fromJson(_row({'price': '৳1200'})).price, 1200);
      expect(ServiceCatalogItem.fromJson(_row({'price': 1200.5})).price, 1200.5);
    });

    test('price falls back to 0 rather than throwing', () {
      expect(ServiceCatalogItem.fromJson(_row({'price': null})).price, 0);
      expect(ServiceCatalogItem.fromJson(_row({'price': 'free'})).price, 0);
      expect(ServiceCatalogItem.fromJson(_row({'price': -50})).price, 0);
      expect(ServiceCatalogItem.fromJson(_row({'price': {}})).price, 0);
    });

    test('non-String text fields are coerced, not cast', () {
      final item = ServiceCatalogItem.fromJson(_row({
        'title': 42,
        'description': 7,
        'category': 99,
      }));
      expect(item.title, '42');
      expect(item.description, '7');
      expect(item.category, '99');
    });

    test('missing optional fields collapse to null / defaults', () {
      final item = ServiceCatalogItem.fromJson({'id': 'x'});
      expect(item.title, '');
      expect(item.price, 0);
      expect(item.description, '');
      expect(item.imageUrl, isNull);
      expect(item.duration, isNull);
      expect(item.status, ServiceCatalogStatus.active);
    });

    test('blank strings become null for nullable fields', () {
      final item = ServiceCatalogItem.fromJson(
        _row({'imageUrl': '   ', 'duration': ''}),
      );
      expect(item.imageUrl, isNull);
      expect(item.duration, isNull);
    });

    test('status parsing is case-insensitive so inactive never leaks', () {
      expect(
        ServiceCatalogItem.fromJson(_row({'status': 'Inactive'})).status,
        ServiceCatalogStatus.inactive,
      );
      expect(
        ServiceCatalogItem.fromJson(_row({'status': ' inactive '})).status,
        ServiceCatalogStatus.inactive,
      );
    });

    test('a wholly malformed map still yields a renderable item', () {
      expect(
        () => ServiceCatalogItem.fromJson({
          'id': [],
          'title': {'a': 'b'},
          'price': [1, 2],
          'createdAt': 12345,
          'status': 99,
        }),
        returnsNormally,
      );
    });
  });

  group('ServiceCatalogRepository.refresh', () {
    test('one malformed row is dropped, the rest still load', () async {
      final repo = ServiceCatalogRepository(_dioReturning([
        _row({'id': 'good-1'}),
        'not-a-map-at-all',
        _row({'id': 'good-2', 'price': '900'}),
      ]));
      addTearDown(repo.dispose);

      final items = await repo.refresh();
      expect(items.map((e) => e.id), ['good-1', 'good-2']);
      expect(items.last.price, 900);
    });

    test('a non-list body raises a typed error, not "Network error"', () async {
      final repo = ServiceCatalogRepository(
        _dioReturning({'message': 'Too many requests'}, statusCode: 429),
      );
      addTearDown(repo.dispose);

      await expectLater(
        repo.refresh(),
        throwsA(
          isA<ServiceCatalogException>()
              .having((e) => e.kind, 'kind', ServiceCatalogFailure.throttled)
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });

    test('an enveloped list is still understood', () async {
      final repo = ServiceCatalogRepository(_dioReturning({
        'data': [_row({'id': 'enveloped'})],
      }));
      addTearDown(repo.dispose);

      final items = await repo.refresh();
      expect(items.single.id, 'enveloped');
    });

    test('a successful refresh clears a prior error on the watched stream',
        () async {
      // The Retry button's contract: after a failed boot fetch, calling
      // refresh() must push data onto the stream so the UI leaves its error
      // state. `ref.refresh(activeServicesProvider)` could not do this.
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _StubAdapter(body: {'oops': true});
      final repo = ServiceCatalogRepository(dio);
      addTearDown(repo.dispose);

      await repo.refreshQuietly();
      final emissions = <Object>[];
      final sub = repo.watchActive().listen(
            (v) => emissions.add(v),
            onError: (Object e) => emissions.add(e),
          );
      await Future<void>.delayed(Duration.zero);
      expect(emissions.single, isA<ServiceCatalogException>());

      // Server recovers; a real re-fetch must flip the stream back to data.
      dio.httpClientAdapter = _StubAdapter(body: [_row({'id': 'recovered'})]);
      await repo.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last, isA<List<ServiceCatalogItem>>());
      expect((emissions.last as List<ServiceCatalogItem>).single.id, 'recovered');
      await sub.cancel();
    });
  });
}
