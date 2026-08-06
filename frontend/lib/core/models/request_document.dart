import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One previous medical document the patient attached to a care request —
/// a discharge summary, an old prescription, a lab report.
///
/// Uploaded through `POST /patient/documents` **before** the booking exists
/// (the patient attaches on the service step; the booking is only created at
/// checkout), so this is the descriptor the upload returns and the create
/// payload carries back in.
@immutable
class RequestDocument extends Equatable {
  /// Original filename, shown on the attachment chip.
  final String name;

  /// Cloudinary https URL, or a bare filename served off the API's
  /// `/uploads` mount in local dev — resolve with `resolveImageUrl()` before
  /// display, exactly like `Service.imageUrl`.
  final String url;

  final String mime;

  /// Bytes. 0 when the server didn't report a size.
  final int size;

  const RequestDocument({
    required this.name,
    required this.url,
    this.mime = '',
    this.size = 0,
  });

  bool get isPdf => mime.toLowerCase() == 'application/pdf';

  /// "1.4 MB" / "812 KB". Empty when the size is unknown, so callers can
  /// omit the line rather than print a bogus "0 KB".
  String get readableSize {
    if (size <= 0) return '';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Total-function parser — the upload response is a small, server-built
  /// object, but a malformed field must degrade to a renderable chip rather
  /// than throw inside the attach flow.
  factory RequestDocument.fromJson(Map<String, dynamic> json) {
    final size = json['size'];
    return RequestDocument(
      name: (json['name'] ?? 'Document').toString(),
      url: (json['url'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      size: size is num ? size.toInt() : int.tryParse('$size') ?? 0,
    );
  }

  Map<String, dynamic> toPayload() => {
        'name': name,
        'url': url,
        'mime': mime,
        'size': size,
      };

  @override
  List<Object?> get props => [name, url, mime, size];
}
