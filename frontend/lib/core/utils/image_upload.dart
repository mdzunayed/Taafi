import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// The only image formats the backend accepts
/// (backend/src/middleware/upload.js). Shared with every picker call site so
/// the dialog's filter and the guard below can never drift apart.
const List<String> kAllowedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// Thrown when a picked file isn't a JPEG, PNG or WEBP and can't be converted
/// into one. Carries a message meant to be shown to the user verbatim.
///
/// Worth a dedicated type: the picker's `allowedExtensions` is a *filter*, not
/// a guarantee — most desktop file dialogs let the user switch to "All files"
/// — so this is a real path, and it deserves a specific message rather than
/// the generic "could not read the image" the call sites use for I/O failures.
class UnsupportedImageException implements Exception {
  final String message;
  const UnsupportedImageException(this.message);

  @override
  String toString() => message;
}

/// A picked image, normalized and ready to attach to a multipart request.
///
/// Bundling the three fields together is deliberate: every upload call site
/// previously passed `bytes` and `filename` separately and then hardcoded
/// `DioMediaType('image', 'jpeg')` regardless of what the bytes actually
/// were. That mislabelling is what forced the server to magic-byte sniff
/// `/uploads` responses (backend/src/utils/imageMime.js) to avoid Flutter
/// Web's `EncodingError`. Carrying the real type alongside the bytes makes
/// the mismatch unrepresentable.
class PreparedImage {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const PreparedImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  int get sizeBytes => bytes.lengthInBytes;

  MultipartFile toMultipart() => MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      );
}

/// The image formats we can hand to the server untouched.
enum _ImageKind {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const _ImageKind(this.mimeType, this.extension);
  final String mimeType;
  final String extension;
}

/// Identifies the format from the bytes themselves.
///
/// Deliberately not derived from `XFile.mimeType` or the filename: the browser
/// reports an **empty string** for files it can't type (which `??` does not
/// catch, so the old code passed `''` straight into `DioMediaType.parse` and
/// threw at save time), and an extension is just a user-editable label. The
/// header is the only part that can't lie.
_ImageKind? _sniff(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return _ImageKind.jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return _ImageKind.png;
  }
  // RIFF....WEBP — the four size bytes at 4..7 are skipped.
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return _ImageKind.webp;
  }
  return null;
}

const _unsupportedMessage =
    "That file isn't a supported image. Use a JPEG, PNG or WebP.";

/// Downscales and re-encodes a picked image so web uploads match what mobile
/// already sends, and guarantees the result is a format the backend accepts.
///
/// `image_picker` applies `maxWidth`/`imageQuality` natively on Android and
/// iOS, but `image_picker_for_web` **silently ignores both** — on web you get
/// the untouched original. Multer caps uploads at 8 MB, so the same photo
/// that uploads fine from a phone is rejected from the browser. This closes
/// that gap in Dart, which runs identically on both.
///
/// Cheap by default: images already under [skipBelowBytes] are returned
/// with only their header read, so the common case (an icon, an
/// already-compressed asset) costs nothing. That threshold matters —
/// `package:image` is pure Dart with no isolates on web, so a decode runs on
/// the UI thread.
///
/// Throws [UnsupportedImageException] for empty files and for anything that is
/// neither a supported format nor convertible into one (HEIC, AVIF and SVG all
/// land here — `package:image` cannot decode them, which is exactly why they
/// used to reach the server unconverted and come back as a 415).
Future<PreparedImage> prepareImageBytesForUpload({
  required Uint8List bytes,
  required String filename,
  int maxWidth = 1600,
  int quality = 85,
  int skipBelowBytes = 1200 * 1024,
}) async {
  if (bytes.isEmpty) {
    throw const UnsupportedImageException(
      "That file is empty. Pick an image that isn't 0 bytes.",
    );
  }

  // Not every source carries a usable name — `XFile.name` and
  // `PlatformFile.name` can both come back empty depending on the platform
  // implementation. An empty multipart filename gives the server nothing to
  // log and nothing to derive an extension from.
  final sourceName = filename.trim().isEmpty ? 'upload' : filename.trim();

  final kind = _sniff(bytes);

  // Unrecognised header. `package:image` still decodes GIF/BMP/TIFF, so try a
  // conversion before giving up — rejecting a file the user can plainly see is
  // an image would be its own kind of wrong.
  if (kind == null) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const UnsupportedImageException(_unsupportedMessage);
    return _encodeAsJpeg(decoded, sourceName, maxWidth, quality);
  }

  PreparedImage asIs() => PreparedImage(
        bytes: bytes,
        // Normalised so the extension agrees with the bytes. The backend now
        // checks both, so a genuine JPEG that a user renamed `photo.heic`
        // would otherwise be rejected on the extension alone.
        filename: _withExtension(sourceName, kind.extension),
        mimeType: kind.mimeType,
      );

  if (bytes.lengthInBytes <= skipBelowBytes) return asIs();

  // A decode failure is not worth failing the upload over — the header already
  // proved the format, the server validates the bytes anyway, and sending the
  // original is strictly better than an error for a file we know is supported.
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return asIs();
  if (decoded.width <= maxWidth) return asIs();

  final shrunk = _encodeAsJpeg(decoded, sourceName, maxWidth, quality);
  // Re-encoding can inflate an already well-compressed source (a small PNG
  // with flat colour, say). Only take the result when it actually helped.
  return shrunk.sizeBytes >= bytes.lengthInBytes ? asIs() : shrunk;
}

/// [XFile]-shaped wrapper over [prepareImageBytesForUpload], for call sites
/// still going through `image_picker`.
Future<PreparedImage> prepareImageForUpload(
  XFile picked, {
  int maxWidth = 1600,
  int quality = 85,
  int skipBelowBytes = 1200 * 1024,
}) async =>
    prepareImageBytesForUpload(
      bytes: await picked.readAsBytes(),
      filename: picked.name,
      maxWidth: maxWidth,
      quality: quality,
      skipBelowBytes: skipBelowBytes,
    );

PreparedImage _encodeAsJpeg(
  img.Image decoded,
  String sourceName,
  int maxWidth,
  int quality,
) {
  final resized = decoded.width > maxWidth
      ? img.copyResize(decoded, width: maxWidth)
      : decoded;
  return PreparedImage(
    bytes: Uint8List.fromList(img.encodeJpg(resized, quality: quality)),
    filename: _withExtension(sourceName, 'jpg'),
    mimeType: 'image/jpeg',
  );
}

// Keep the stem so the upload stays recognisable in logs, but force the
// extension to match the bytes we're actually sending.
String _withExtension(String filename, String extension) {
  final dot = filename.lastIndexOf('.');
  final stem = dot <= 0 ? filename : filename.substring(0, dot);
  return '$stem.$extension';
}
