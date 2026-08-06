import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/booking_attachment.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../auth/auth_provider.dart';

/// Opens one patient-attached medical record without leaving the console.
///
/// Staying in-app is the point. A clinician opens this standing at a patient's
/// door, mid-visit, with a checklist and a completion flow behind it — bouncing
/// them into a browser or a system PDF app loses that place, and on Android the
/// way back is a Back button that may not return to where they were.
///
/// Two shapes, because the two file kinds fail differently:
///   • image → a zoomable overlay dialog. The bytes stream straight into
///     `Image.network`; there is nothing to stage on disk.
///   • PDF   → a pushed route. `flutter_pdfview` renders from a local file
///     path, not a URL, so the grant's bytes are fetched to the cache
///     directory first and the route owns that file's lifetime.
Future<void> openPatientDocument(
  BuildContext context,
  BookingAttachment attachment,
) {
  if (attachment.isImage) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ImageLightbox(attachment: attachment),
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => _PdfViewerScreen(attachment: attachment)),
  );
}

// ---------------------------------------------------------------------------
// Images — zoomable overlay
// ---------------------------------------------------------------------------

/// Pinch/double-tap zoom via [InteractiveViewer], which is what the admin
/// console's lightbox already uses. A dedicated gallery package would add a
/// dependency for gestures Flutter ships, and this surface shows exactly one
/// image with no paging.
class _ImageLightbox extends StatelessWidget {
  final BookingAttachment attachment;

  const _ImageLightbox({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  attachment.fileName,
                  style: MtTextStyles.labelLg.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(
                attachment.fileUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                errorBuilder: (_, _, _) => const _ExpiredLinkNotice(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDFs — embedded native viewer
// ---------------------------------------------------------------------------

/// Sentinel for the one failure with a specific remedy, kept distinct from the
/// free-text errors so `_body` can branch on identity rather than on wording.
const String _kExpired = '__grant_expired__';

class _PdfViewerScreen extends ConsumerStatefulWidget {
  final BookingAttachment attachment;

  const _PdfViewerScreen({required this.attachment});

  @override
  ConsumerState<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<_PdfViewerScreen> {
  /// Staged copy of the document. Null until the download lands.
  File? _file;
  String? _error;
  int _pageCount = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _download();
  }

  @override
  void dispose() {
    // Medical records must not accumulate in the cache directory after the
    // clinician closes the visit. Fire-and-forget: the route is going away and
    // a failed unlink is not something the user can act on.
    _file?.delete().ignore();
    super.dispose();
  }

  Future<void> _download() async {
    try {
      // Null means the grant aged out (403) — the one failure the clinician
      // can actually act on, so it gets its own state rather than a generic
      // error string.
      final bytes = await ref
          .read(dioClientProvider)
          .fetchDocumentBytes(widget.attachment.fileUrl);
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _error = _kExpired);
        return;
      }
      if (bytes.isEmpty) {
        setState(() => _error = 'The server returned an empty file.');
        return;
      }
      final dir = await getTemporaryDirectory();
      // Name it off the attachment id, not the patient's filename: two
      // documents on one booking can share a name, and the id is unique
      // within the booking by construction.
      final file = File('${dir.path}/taafi-doc-${widget.attachment.id}.pdf');
      await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
      if (!mounted) {
        // Raced with a back-press: nothing will render these bytes, and a
        // medical record must not be left behind in the cache directory.
        file.delete().ignore();
        return;
      }
      setState(() => _file = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPager = _file != null && _pageCount > 1;
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: Text(
          widget.attachment.fileName,
          style: MtTextStyles.labelLg,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: _body(),
      // Page position matters on a discharge summary — a clinician skimming
      // for a medication list needs to know whether there is more below.
      bottomNavigationBar: showPager
          ? SafeArea(
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: MtColors.surface,
                  border: Border(top: BorderSide(color: MtColors.line)),
                ),
                child: Text(
                  'Page ${_page + 1} of $_pageCount',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    final error = _error;
    if (error == _kExpired) return const _ExpiredLinkNotice();
    if (error != null) {
      return _Notice(
        icon: Icons.error_outline,
        title: 'This document could not be opened.',
        detail: error,
      );
    }
    final file = _file;
    if (file == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PDFView(
      filePath: file.path,
      swipeHorizontal: false,
      autoSpacing: false,
      pageFling: false,
      onRender: (pages) {
        if (mounted) setState(() => _pageCount = pages ?? 0);
      },
      onPageChanged: (page, _) {
        if (mounted) setState(() => _page = page ?? 0);
      },
      // A PDF that renders on one platform and not the other is a real
      // outcome here (patients upload whatever their clinic emailed them),
      // so surface it instead of leaving a blank grey page.
      onError: (e) {
        if (mounted) setState(() => _error = '$e');
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared failure states
// ---------------------------------------------------------------------------

/// The expected failure: grants live ~30 minutes, and a console left open
/// through a long visit will outlast one. Retrying the same URL cannot fix it,
/// so the copy names the action that can.
class _ExpiredLinkNotice extends StatelessWidget {
  const _ExpiredLinkNotice();

  @override
  Widget build(BuildContext context) {
    return const _Notice(
      icon: Icons.link_off,
      title: 'This document link has expired.',
      detail: 'Go back and reopen the visit to get a fresh link.',
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: MtColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: MtColors.ink3),
            const SizedBox(height: 12),
            Text(title, style: MtTextStyles.labelMd, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              detail,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
