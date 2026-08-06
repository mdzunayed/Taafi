import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/booking_attachment.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../providers/booking_attachments_provider.dart';
import '../patient_document_viewer.dart';

/// Previous medical records the patient attached at booking time, on the
/// assigned clinician's console.
///
/// Placed directly under the patient card, above the vitals / vault / task
/// surfaces, for the same reason the admin console puts it above the provider
/// pickers: a nurse arriving for a post-surgery dressing change needs the
/// discharge summary BEFORE they start, not filed under a disclosure below the
/// work they came to do.
///
/// Renders an explicit "none attached" line rather than disappearing. An
/// absent card and an absent document are different facts, and a clinician who
/// sees nothing cannot tell whether the patient uploaded nothing or the app
/// failed to ask.
class PatientDocumentsPanel extends ConsumerWidget {
  /// `care_requests._id` for the visit. Same id the payment posture is keyed
  /// by; both read `GET /doctor/bookings/:id`.
  final String bookingId;

  const PatientDocumentsPanel({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingAttachmentsProvider(bookingId));
    return async.when(
      loading: () => const _Shell(
        count: null,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading patient documents…', style: MtTextStyles.bodySm),
          ],
        ),
      ),
      // A read failure is NOT "no documents". Saying so — and offering the
      // retry — keeps a clinician from walking into a visit believing there
      // was nothing to read.
      error: (err, _) => _Shell(
        count: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not load the patient\'s documents.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(bookingAttachmentsProvider(bookingId)),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.ink,
                side: const BorderSide(color: MtColors.line),
                minimumSize: const Size(0, 34),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
      data: (attachments) => _Shell(
        count: attachments.length,
        child: attachments.isEmpty
            ? Text(
                'No medical documents attached by patient.',
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              )
            : Column(
                children: [
                  for (final attachment in attachments)
                    _DocumentRow(attachment: attachment),
                ],
              ),
      ),
    );
  }
}

/// Card chrome shared by all three states, so the panel keeps one footprint
/// and the console below it doesn't jump as the fetch settles.
class _Shell extends StatelessWidget {
  final int? count;
  final Widget child;

  const _Shell({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
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
                  count == null
                      ? 'PATIENT ATTACHED DOCUMENTS'
                      : 'PATIENT ATTACHED DOCUMENTS ($count)',
                  style: MtTextStyles.sectionLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final BookingAttachment attachment;

  const _DocumentRow({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final meta = [
      attachment.uploadedLabel.isEmpty
          ? ''
          : 'Uploaded ${attachment.uploadedLabel}',
      attachment.readableSize,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          _TypeBadge(attachment: attachment),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  style: MtTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: MtTextStyles.labelSm
                        .copyWith(color: MtColors.ink3, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => openPatientDocument(context, attachment),
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('View'),
            style: TextButton.styleFrom(
              foregroundColor: MtColors.brand,
              textStyle: MtTextStyles.labelSm,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kind at a glance. Images get a real thumbnail — a nurse can recognise a
/// wound photo without opening it — PDFs get a badge.
class _TypeBadge extends StatelessWidget {
  final BookingAttachment attachment;

  const _TypeBadge({required this.attachment});

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          attachment.fileUrl,
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          // Decode at thumbnail size: these run to several MB, and decoding
          // them at full resolution to fill a 38 px box is how a console on a
          // mid-range handset starts dropping frames.
          cacheWidth: 114,
          errorBuilder: (_, _, _) => const _Badge(
            icon: Icons.broken_image_outlined,
            color: MtColors.ink3,
          ),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
        ),
      );
    }
    return _Badge(
      icon: attachment.isPdf
          ? Icons.picture_as_pdf_outlined
          : Icons.insert_drive_file_outlined,
      color: attachment.isPdf ? MtColors.rejected : MtColors.ink2,
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
