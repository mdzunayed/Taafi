// Covers resolveImageUrl, the guard in front of every network image:
//   1. Empty/null/whitespace resolve to null, so callers render a placeholder
//      instead of constructing a CachedNetworkImage with an empty imageUrl
//      (which asserts) — the live bug on the App-Open Ad summary card, where
//      AppOpenAd.imageUrl is non-nullable and defaults to ''.
//   2. Absolute http(s) URLs pass through untouched (the normal API shape).
//   3. Relative paths and bare filenames are absolutized against the API
//      origin, with no doubled or missing slash.
//   4. Non-http schemes are rejected rather than handed to the image pipeline,
//      since the admin home-sections panel accepts a hand-pasted URL.

import 'package:flutter_test/flutter_test.dart';

import 'package:taafi/core/api/dio_client.dart';
import 'package:taafi/core/utils/image_url.dart';

void main() {
  final base = DioClient.baseUrl.replaceAll(RegExp(r'/+$'), '');

  group('resolveImageUrl returns null when there is nothing to render', () {
    test('null, empty and whitespace-only', () {
      expect(resolveImageUrl(null), isNull);
      expect(resolveImageUrl(''), isNull);
      expect(resolveImageUrl('   '), isNull);
    });
  });

  group('absolute URLs', () {
    test('http and https pass through unchanged', () {
      const https = 'https://res.cloudinary.com/demo/image/upload/x.jpg';
      const http = 'http://localhost:5000/uploads/x.jpg';
      expect(resolveImageUrl(https), https);
      expect(resolveImageUrl(http), http);
    });

    test('surrounding whitespace is trimmed', () {
      expect(
        resolveImageUrl('  https://example.com/a.png  '),
        'https://example.com/a.png',
      );
    });

    test('data: URIs are preserved', () {
      const uri = 'data:image/png;base64,iVBORw0KGgo=';
      expect(resolveImageUrl(uri), uri);
    });
  });

  group('relative references are absolutized against the API origin', () {
    test('a rooted /uploads path', () {
      expect(resolveImageUrl('/uploads/x.jpg'), '$base/uploads/x.jpg');
    });

    test('a bare filename gains the missing slash', () {
      expect(resolveImageUrl('x.jpg'), '$base/x.jpg');
    });

    test('no doubled slash at the join', () {
      expect(resolveImageUrl('/uploads/x.jpg'), isNot(contains('//uploads')));
    });
  });

  group('unsafe schemes are rejected', () {
    test('javascript:, file: and blob: resolve to null', () {
      expect(resolveImageUrl('javascript:alert(1)'), isNull);
      expect(resolveImageUrl('file:///etc/passwd'), isNull);
      expect(resolveImageUrl('blob:https://example.com/abc'), isNull);
    });
  });
}
