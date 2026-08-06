import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// One previous medical document (discharge summary, old prescription, lab
/// report) the patient attached when they booked — as the admin console sees
/// it.
///
/// Distinct from `RequestDocument`, which is the patient-side *upload*
/// descriptor (`{name, url, mime, size}`) produced by
/// `POST /patient/documents`. This is the read side, and the difference that
/// matters is [fileUrl]: the admin payload never carries the raw Cloudinary /
/// uploads location. It carries a presigned, expiring grant minted by
/// `utils/bookingAttachments.js`, which is what makes an `<img>` tag and a
/// browser tab — neither of which can send an `Authorization` header — able to
/// open a medical record without the record being world-readable.
///
/// Links go stale. Grants last 30 minutes from whichever admin response
/// carried them, so a drawer left open all afternoon must re-read the booking
/// rather than retry the same URL.
class BookingAttachment extends Equatable {
  /// Stable within a booking (`<requestId>-<index>`). Position IS the identity:
  /// the stored subdocuments carry no `_id`.
  final String id;

  final String fileName;

  /// Sanitised server-side to a known-safe set (PDF / JPEG / PNG / WEBP), so
  /// anything unrecognised arrives as `application/octet-stream` rather than
  /// as whatever the upload announced.
  final String fileType;

  /// Presigned URL for inline viewing.
  final String fileUrl;

  /// The same grant with `?download=1`, which flips the server's
  /// `Content-Disposition` to `attachment`.
  final String downloadUrl;

  /// Bytes. 0 when the server didn't record a size.
  final int sizeBytes;

  final DateTime? uploadedAt;

  const BookingAttachment({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.fileUrl,
    required this.downloadUrl,
    this.sizeBytes = 0,
    this.uploadedAt,
  });

  bool get isPdf => fileType.toLowerCase() == 'application/pdf';

  /// Only these render in the in-app lightbox — `Image.network` cannot decode
  /// a PDF, and an unrecognised type is deliberately not fed to the decoder.
  bool get isImage => const {
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/webp',
      }.contains(fileType.toLowerCase());

  /// "1.4 MB" / "812 KB". Empty when unknown, so callers omit the line rather
  /// than printing a bogus "0 KB".
  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// "7 Aug 2026, 1:30 AM" in the viewer's local zone. Empty when the row
  /// predates the timestamp.
  String get uploadedLabel {
    final at = uploadedAt;
    if (at == null) return '';
    return DateFormat('d MMM yyyy, h:mm a').format(at.toLocal());
  }

  /// Total-function parser: one malformed descriptor must degrade to a
  /// renderable tile rather than throw inside the assignment drawer and blank
  /// the whole booking.
  factory BookingAttachment.fromJson(Map<String, dynamic> json) {
    final size = json['size_bytes'] ?? json['sizeBytes'] ?? json['size'];
    final fileUrl = (json['file_url'] ?? json['fileUrl'] ?? '').toString();
    final downloadUrl =
        (json['download_url'] ?? json['downloadUrl'] ?? '').toString();
    return BookingAttachment(
      id: (json['id'] ?? '').toString(),
      fileName:
          (json['file_name'] ?? json['fileName'] ?? 'Document').toString(),
      fileType: (json['file_type'] ?? json['fileType'] ?? '').toString(),
      fileUrl: fileUrl,
      // Older backends ship only `file_url`; appending the flag client-side
      // keeps Download working against them instead of opening nothing.
      downloadUrl: downloadUrl.isNotEmpty
          ? downloadUrl
          : (fileUrl.isEmpty
              ? ''
              : '$fileUrl${fileUrl.contains('?') ? '&' : '?'}download=1'),
      sizeBytes: size is num ? size.toInt() : int.tryParse('$size') ?? 0,
      uploadedAt: DateTime.tryParse(
        (json['uploaded_at'] ?? json['uploadedAt'] ?? '').toString(),
      ),
    );
  }

  /// Parses the `attachments` array off an admin booking payload. Skips
  /// entries with no usable URL — a tile whose buttons can only fail is worse
  /// than no tile.
  static List<BookingAttachment> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <BookingAttachment>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final attachment =
          BookingAttachment.fromJson(Map<String, dynamic>.from(entry));
      if (attachment.fileUrl.isEmpty) continue;
      out.add(attachment);
    }
    return out;
  }

  @override
  List<Object?> get props =>
      [id, fileName, fileType, fileUrl, downloadUrl, sizeBytes, uploadedAt];
}
