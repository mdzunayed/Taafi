// Covers prepareImageBytesForUpload, which does two jobs.
//
// The first is the web/mobile upload divergence: image_picker applies
// maxWidth/imageQuality natively on Android and iOS but image_picker_for_web
// silently ignores both, so the browser sent the full original and tripped
// multer's 8 MB cap while the same photo uploaded fine from a phone.
//
//   1. Large images are downscaled and re-encoded so web matches mobile.
//   2. Small images are passed through untouched (the common case is free).
//   3. The real MIME type survives, instead of everything being labelled
//      image/jpeg — which is what forced the server to magic-byte sniff
//      /uploads responses to avoid Flutter Web's EncodingError.
//
// The second is the format guard, added after admins hit "Only JPEG / PNG /
// WEBP images are allowed" on save. The web picker could only ask for
// `image/*`, so HEIC/AVIF reached the server and came back a 415 after a full
// round trip:
//
//   4. The format is decided by the *bytes*, never by the declared MIME type
//      or the extension — both are user-controlled and both were observed
//      lying (an empty string from the browser, a renamed file from a user).
//   5. Anything that isn't JPEG/PNG/WEBP is converted when it can be, and
//      rejected locally with a readable message when it can't.
//   6. The filename extension is normalised to agree with the bytes, because
//      the backend filter now checks both.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:taafi/core/utils/image_upload.dart';

/// A real PNG of [width]x[height] filled with deterministic pseudo-random
/// noise. Noise, not a gradient: PNG compresses structured pixels down to
/// almost nothing, which would put "large" fixtures under the size threshold
/// and make the downscale tests pass for the wrong reason.
Uint8List pngOf(int width, int height) {
  final image = img.Image(width: width, height: height);
  var seed = 0x2545F491;
  int next() {
    // xorshift32 — no dependency, and identical on every run.
    seed ^= (seed << 13) & 0xFFFFFFFF;
    seed ^= seed >> 17;
    seed ^= (seed << 5) & 0xFFFFFFFF;
    return seed & 0xFF;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, next(), next(), next());
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

// `path` is set as well as `name`: on the VM implementation XFile.name is
// derived from the path, so name alone comes back empty here.
XFile fileOf(Uint8List bytes, String name, String? mimeType) =>
    XFile.fromData(bytes, name: name, path: name, mimeType: mimeType);

/// A WEBP container header plus filler. `package:image` has no WebP encoder,
/// and none is needed: a sub-threshold image is only ever sniffed, so the
/// 12-byte `RIFF....WEBP` signature is the entire contract under test.
Uint8List webpOf(int totalBytes) {
  final bytes = Uint8List(totalBytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  final payload = totalBytes - 8;
  bytes[4] = payload & 0xFF;
  bytes[5] = (payload >> 8) & 0xFF;
  bytes[6] = (payload >> 16) & 0xFF;
  bytes[7] = (payload >> 24) & 0xFF;
  bytes.setAll(8, 'WEBPVP8 '.codeUnits);
  return bytes;
}

/// Stands in for HEIC/AVIF: a plausible-looking file that is not one of the
/// three supported signatures and that `package:image` cannot decode either.
Uint8List undecodableOf(int totalBytes) => Uint8List.fromList([
      ...'\x00\x00\x00\x20ftypheic'.codeUnits,
      ...List<int>.generate(totalBytes - 12, (i) => (i * 7) % 256),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('large images are downscaled', () {
    test('a wide image is capped at maxWidth and re-encoded as JPEG', () async {
      final source = pngOf(2400, 1200);
      // Guard the premise: the fixture must actually exceed the threshold,
      // otherwise this test would pass for the wrong reason.
      expect(source.lengthInBytes, greaterThan(1200 * 1024));

      final prepared = await prepareImageForUpload(
        fileOf(source, 'huge.png', 'image/png'),
        maxWidth: 1600,
      );

      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.filename, 'huge.jpg');
      expect(prepared.sizeBytes, lessThan(source.lengthInBytes));

      final decoded = img.decodeImage(prepared.bytes)!;
      expect(decoded.width, 1600);
      expect(decoded.height, 800); // aspect ratio preserved
    });

    test('a source over the 8 MB server cap ends up under it', () async {
      // The exact scenario that fails today: a browser upload that multer
      // rejects with LIMIT_FILE_SIZE because web skipped the downscale.
      final source = pngOf(3000, 2000);
      expect(source.lengthInBytes, greaterThan(8 * 1024 * 1024));

      final prepared = await prepareImageForUpload(
        fileOf(source, 'photo.png', 'image/png'),
      );
      expect(prepared.sizeBytes, lessThan(8 * 1024 * 1024));
    });
  });

  group('small images are passed through untouched', () {
    test('bytes, name and MIME type all survive', () async {
      final source = pngOf(64, 64);
      expect(source.lengthInBytes, lessThan(1200 * 1024));

      final prepared = await prepareImageForUpload(
        fileOf(source, 'icon.png', 'image/png'),
      );

      expect(prepared.bytes, source);
      expect(prepared.filename, 'icon.png');
      // The whole point: a PNG stays labelled image/png rather than being
      // mislabelled image/jpeg the way every call site used to hardcode.
      expect(prepared.mimeType, 'image/png');
    });

    test('a WebP keeps its type', () async {
      final source = webpOf(4096);
      final prepared = await prepareImageForUpload(
        fileOf(source, 'sticker.webp', 'image/webp'),
      );
      expect(prepared.mimeType, 'image/webp');
      expect(prepared.bytes, source);
    });

    test('MIME falls back to the extension when the picker omits it', () async {
      final prepared = await prepareImageForUpload(
        fileOf(pngOf(32, 32), 'from-picker.png', null),
      );
      expect(prepared.mimeType, 'image/png');
    });
  });

  group('the format is decided by the bytes, not the labels', () {
    test('a lying MIME type does not win over the header', () async {
      // The picker labelled it WebP; the bytes are a PNG. Trusting the label
      // is what shipped a PNG to the server announced as image/webp.
      final prepared = await prepareImageForUpload(
        fileOf(pngOf(32, 32), 'sticker.webp', 'image/webp'),
      );
      expect(prepared.mimeType, 'image/png');
    });

    test('the extension is rewritten to match the bytes', () async {
      // A genuine JPEG that a user renamed. The backend now checks the
      // extension as well as the MIME type, so shipping `photo.heic`
      // unchanged would be rejected on the extension alone.
      final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
      final prepared = await prepareImageForUpload(
        fileOf(jpeg, 'photo.heic', 'image/heic'),
      );
      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.filename, 'photo.jpg');
    });

    test('an empty declared MIME type is ignored rather than propagated',
        () async {
      // Browsers report '' for files they cannot type. `??` does not catch an
      // empty string, so it used to reach DioMediaType.parse('') and throw at
      // save time — for a perfectly valid image.
      final prepared = await prepareImageForUpload(
        fileOf(pngOf(32, 32), 'icon.png', ''),
      );
      expect(prepared.mimeType, 'image/png');
      expect(() => prepared.toMultipart(), returnsNormally);
    });
  });

  group('unsupported formats', () {
    test('a HEIC-shaped file is rejected locally, not by the server', () async {
      await expectLater(
        prepareImageForUpload(fileOf(undecodableOf(4096), 'IMG_1.heic', 'image/heic')),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('the rejection message names the formats that do work', () async {
      try {
        await prepareImageForUpload(
          fileOf(undecodableOf(4096), 'IMG_1.heic', 'image/heic'),
        );
        fail('expected an UnsupportedImageException');
      } on UnsupportedImageException catch (e) {
        expect(e.message, contains('JPEG'));
        expect(e.message, contains('PNG'));
        expect(e.message, contains('WebP'));
      }
    });

    test('an empty file is rejected', () async {
      await expectLater(
        prepareImageForUpload(fileOf(Uint8List(0), 'empty.jpg', 'image/jpeg')),
        throwsA(isA<UnsupportedImageException>()),
      );
    });

    test('a GIF is converted rather than rejected', () async {
      // Not a supported upload format, but `package:image` decodes it — and
      // rejecting a file the user can plainly see is an image would be its
      // own kind of wrong.
      final gif = Uint8List.fromList(img.encodeGif(img.Image(width: 40, height: 20)));
      final prepared = await prepareImageForUpload(fileOf(gif, 'anim.gif', 'image/gif'));

      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.filename, 'anim.jpg');
      expect(img.decodeImage(prepared.bytes), isNotNull);
    });
  });

  group('degrades safely', () {
    test('a valid header with an undecodable body is still sent as-is',
        () async {
      // The header already proved the format and the server validates the
      // bytes anyway, so a decoder that chokes is not worth failing over.
      final broken = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, // JPEG signature
        ...List<int>.generate(1500 * 1024, (i) => i % 256),
      ]);
      final prepared = await prepareImageForUpload(
        fileOf(broken, 'broken.jpg', 'image/jpeg'),
      );
      expect(prepared.bytes, broken);
      expect(prepared.filename, 'broken.jpg');
      expect(prepared.mimeType, 'image/jpeg');
    });
  });

  test('toMultipart carries the real content type', () async {
    final prepared = await prepareImageForUpload(
      fileOf(pngOf(48, 48), 'icon.png', 'image/png'),
    );
    final part = prepared.toMultipart();
    expect(part.contentType.toString(), 'image/png');
    expect(part.filename, 'icon.png');
  });
}
