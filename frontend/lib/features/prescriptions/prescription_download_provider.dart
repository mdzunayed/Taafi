import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/auth_provider.dart';

/// Download lifecycle for one prescription's server-rendered PDF.
///
/// The pad overlay renders off [isDownloading] + [downloadProgress]; the
/// host surfaces listen for [errorMessage] transitions to show a snackbar.
class PrescriptionDownloadState {
  final bool isDownloading;

  /// 0.0–1.0. Stays 0.0 while the byte total is unknown (the overlay
  /// shows an indeterminate spinner in that case).
  final double downloadProgress;
  final String? errorMessage;

  const PrescriptionDownloadState({
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.errorMessage,
  });

  static const idle = PrescriptionDownloadState();

  PrescriptionDownloadState downloading(double progress) =>
      PrescriptionDownloadState(
        isDownloading: true,
        downloadProgress: progress,
      );

  PrescriptionDownloadState failed(String message) =>
      PrescriptionDownloadState(errorMessage: message);
}

/// Native-only (mobile/desktop) downloader: cache-first fetch of
/// `GET /api/prescriptions/:id/download` into the app documents dir,
/// then hand-off to the OS PDF viewer via open_filex. Web never calls
/// this — the detail screen keeps its client-side Printing flow behind
/// a kIsWeb split.
class PrescriptionDownloadController
    extends StateNotifier<PrescriptionDownloadState> {
  final Ref _ref;
  final String _prescriptionId;

  PrescriptionDownloadController(this._ref, this._prescriptionId)
      : super(PrescriptionDownloadState.idle);

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/Taafi_Rx_$_prescriptionId.pdf');
  }

  Future<void> downloadAndOpen() async {
    if (state.isDownloading) return; // double-tap guard

    late final File file;
    try {
      file = await _cacheFile();
      // Cache hit → open instantly, no network. Files only ever land
      // here after a successful 200, so a non-empty file is trustworthy.
      if (await file.exists() && await file.length() > 0) {
        await OpenFilex.open(file.path);
        return;
      }
    } catch (_) {
      state = state.failed('Could not access local storage.');
      return;
    }

    state = state.downloading(0);
    try {
      await _ref.read(dioClientProvider).downloadPrescriptionPdf(
        _prescriptionId,
        file.path,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            state = state.downloading(received / total);
          }
        },
      );
      if (!mounted) return;
      state = PrescriptionDownloadState.idle;
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        state = state.failed(
          'Saved, but no PDF viewer could open it (${result.message}).',
        );
      }
    } catch (e) {
      // Belt-and-braces: dio.download uses temp-file + rename so a failed
      // transfer shouldn't leave anything, but never risk caching a
      // partial script.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {/* cleanup is best-effort */}
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '').trim();
      state = state.failed(
        raw.isEmpty ? 'Download failed. Please try again.' : raw,
      );
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = PrescriptionDownloadState.idle;
    }
  }
}

final prescriptionDownloadProvider = StateNotifierProvider.autoDispose
    .family<PrescriptionDownloadController, PrescriptionDownloadState, String>(
  (ref, prescriptionId) =>
      PrescriptionDownloadController(ref, prescriptionId),
);
