import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prescription.dart';
import '../../core/theme/mt_colors.dart';
import '../../core/widgets/frosted_surface.dart';
import 'prescription_download_provider.dart';
import 'prescription_pad_widget.dart';

/// The prescription pad plus its download action layer.
///
/// Keeps [PrescriptionPadWidget] purely presentational: this wrapper owns
/// the download button (top-right of the pad header), the frosted
/// progress overlay while a transfer runs, and the error snackbar.
///
/// Platform split: native taps run the server-PDF pipeline
/// ([prescriptionDownloadProvider] → dio.download → open_filex). On web
/// that pipeline can't run (no documents dir / native viewer), so the
/// button calls [webFallback] instead — and hides entirely when the
/// caller didn't supply one (e.g. the doctor history sheet on web).
class DownloadablePrescriptionPad extends ConsumerWidget {
  final Prescription prescription;
  final bool compact;

  /// Web-only replacement action (typically the existing client-side
  /// Printing export). Ignored on native platforms.
  final Future<void> Function()? webFallback;

  const DownloadablePrescriptionPad({
    super.key,
    required this.prescription,
    this.compact = false,
    this.webFallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = prescriptionDownloadProvider(prescription.id);
    final dl = ref.watch(provider);

    // Surface failures as a snackbar on the host scaffold, then reset so
    // the same error can fire again on a retry.
    ref.listen(provider, (prev, next) {
      final message = next.errorMessage;
      if (message != null && prev?.errorMessage != message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: MtColors.rejected,
            content: Text(
              message.length > 160 ? '${message.substring(0, 160)}…' : message,
            ),
          ),
        );
        ref.read(provider.notifier).clearError();
      }
    });

    final showButton =
        !prescription.locked && (!kIsWeb || webFallback != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Utility row above the paper — keeps the action off the pad's
        // letterhead (a floating button would sit on the Taafi brand).
        if (showButton)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: dl.isDownloading
                  ? null
                  : () {
                      if (kIsWeb) {
                        webFallback?.call();
                      } else {
                        ref.read(provider.notifier).downloadAndOpen();
                      }
                    },
              style: TextButton.styleFrom(
                foregroundColor: MtColors.brand,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text(
                'PDF',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        Stack(
          children: [
            PrescriptionPadWidget(
                prescription: prescription, compact: compact),
            // Frosted progress overlay — also absorbs taps so a second
            // press can't race the in-flight transfer.
            if (dl.isDownloading)
              Positioned.fill(
                child: FrostedSurface(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white.withValues(
                        alpha: FrostedSurface.blurSupported ? .55 : .85),
                    alignment: Alignment.center,
                    child: _ProgressBadge(progress: dl.downloadProgress),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Bottom-sheet host for the pad — the doctor history surfaces open a
/// past script through this so they never re-implement the layout. Embeds
/// [DownloadablePrescriptionPad], so doctors get the same download action
/// (native only — no [DownloadablePrescriptionPad.webFallback] here, the
/// button simply hides on web).
Future<void> showPrescriptionPadSheet(
  BuildContext context,
  Prescription prescription,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: kPadLineColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              DownloadablePrescriptionPad(
                prescription: prescription,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProgressBadge extends StatelessWidget {
  final double progress;
  const _ProgressBadge({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: CircularProgressIndicator(
            // Indeterminate until the server reports a byte total.
            value: progress > 0 ? progress : null,
            strokeWidth: 4,
            color: MtColors.brand,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          progress > 0
              ? '${(progress * 100).round()}%'
              : 'Preparing PDF…',
          style: const TextStyle(
            color: MtColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
