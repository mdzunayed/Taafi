import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/booking_attachment.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';

/// Previous medical documents the patient attached at booking time, rendered
/// above the provider pickers on every assignment surface.
///
/// The point of the placement: an admin dispatching a nurse for a post-surgery
/// dressing should be able to read the discharge summary BEFORE choosing who
/// goes, not after. So this sits above the selection controls, and it renders
/// an explicit "none attached" line rather than disappearing — an absent card
/// and an absent document are very different facts, and only one of them means
/// "go ahead and assign".
///
/// Every URL here is a presigned grant minted by the admin API, and grants
/// expire (~30 min). In practice the admin queue's background poll re-reads
/// `GET /admin/requests` and re-mints them long before that, so expiry only
/// bites a surface left open with polling stopped — which is what the
/// lightbox's expired-link state is worded for.
class PatientDocumentsCard extends StatelessWidget {
  final List<BookingAttachment> attachments;

  const PatientDocumentsCard({super.key, required this.attachments});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_shared_outlined,
                  size: 18, color: MtColors.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PATIENT MEDICAL DOCUMENTS (${attachments.length})',
                  style: MtTextStyles.sectionLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (attachments.isEmpty)
            Text(
              'No medical documents attached by patient.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in attachments)
                  _AttachmentTile(attachment: attachment),
              ],
            ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final BookingAttachment attachment;

  const _AttachmentTile({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final meta = [
      attachment.uploadedLabel,
      attachment.readableSize,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      width: 268,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AttachmentThumb(attachment: attachment),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      style: MtTextStyles.labelMd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: MtTextStyles.labelSm.copyWith(
                          color: MtColors.ink3,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TileAction(
                  icon: Icons.visibility_outlined,
                  label: 'Preview',
                  onPressed: () => _preview(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _TileAction(
                  icon: Icons.download_outlined,
                  label: 'Download',
                  onPressed: () => _download(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Images open in an in-app lightbox — the admin stays in the assignment
  /// flow, which is the whole reason to look at the file here rather than in
  /// a separate tab. PDFs go to the browser/native viewer, which already has
  /// paging, zoom, and search that an embedded widget would only approximate.
  void _preview(BuildContext context) {
    if (attachment.isImage) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _ImageLightbox(
          attachment: attachment,
          onDownload: () => _download(context),
        ),
      );
      return;
    }
    _open(context, attachment.fileUrl, 'Could not open this document.');
  }

  void _download(BuildContext context) {
    _open(context, attachment.downloadUrl, 'Could not download this document.');
  }

  Future<void> _open(
    BuildContext context,
    String url,
    String failureMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

/// PDF → a type badge. Image → the real thing, so an admin can recognise a
/// wound photo without opening anything.
class _AttachmentThumb extends StatelessWidget {
  final BookingAttachment attachment;

  const _AttachmentThumb({required this.attachment});

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          attachment.fileUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          // Decode at thumbnail size: these are up to 8 MB, and decoding a
          // dozen of them at full resolution to fill a 40 px box is how a
          // busy queue starts dropping frames.
          cacheWidth: 120,
          errorBuilder: (_, _, _) => const _TypeBadge(
            icon: Icons.broken_image_outlined,
            color: MtColors.ink3,
          ),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
        ),
      );
    }
    return _TypeBadge(
      icon: attachment.isPdf
          ? Icons.picture_as_pdf_outlined
          : Icons.insert_drive_file_outlined,
      color: attachment.isPdf ? MtColors.rejected : MtColors.ink2,
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _TypeBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _TileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TileAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: MtTextStyles.labelSm),
      style: OutlinedButton.styleFrom(
        foregroundColor: MtColors.ink,
        side: const BorderSide(color: MtColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(0, 32),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Full-screen image overlay with pinch/scroll zoom.
class _ImageLightbox extends StatelessWidget {
  final BookingAttachment attachment;
  final VoidCallback onDownload;

  const _ImageLightbox({required this.attachment, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
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
                tooltip: 'Download',
                icon: const Icon(Icons.download_outlined, color: Colors.white),
                onPressed: onDownload,
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
                // A grant that aged out is the expected failure here, and it
                // is not something a retry of the same URL can fix — say so
                // in the words that name the actual next step.
                errorBuilder: (_, _, _) => Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: MtColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off,
                          size: 32, color: MtColors.ink3),
                      const SizedBox(height: 12),
                      Text(
                        'This document link has expired.',
                        style: MtTextStyles.labelMd,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Close and reopen the booking to get a fresh link.',
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
