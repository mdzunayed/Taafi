import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../theme/mt_text_styles.dart';

/// Deep-indigo / amber overlay toast used across the Ops Console for
/// non-blocking success / error feedback.
///
/// Built on [OverlayEntry] (rooted at the top-most overlay) so it floats above
/// the current screen — including any open modal dialog — **without displacing
/// layout**. The tab grid underneath stays exactly where it is; there is no
/// more raw red [SnackBar] band eating into the footer.
///
/// Pair [error] with [mapBannerError] to turn a [DioException] into a
/// human-readable `(title, message)` instead of leaking the raw Dio exception
/// string to the admin.
class MtToast {
  MtToast._();

  // Palette kept local — a one-off surface that doesn't warrant widening
  // MtColors. Deep indigo card, amber accent rail/icon for errors, emerald
  // for the happy path.
  static const Color _indigo = Color(0xFF312E81); // deep indigo surface
  static const Color _indigoBorder = Color(0xFF4338CA);
  static const Color _amber = Color(0xFFF59E0B); // error accent
  static const Color _emerald = Color(0xFF34D399); // success accent

  /// Indigo/amber error toast. [title] is the short headline, [message] the
  /// one-line explanation.
  static void error(BuildContext context, String title, String message) =>
      _show(
        context,
        title: title,
        message: message,
        icon: Icons.error_outline_rounded,
        accent: _amber,
      );

  /// Indigo/emerald success toast — reused for the "Banner created / updated"
  /// happy path.
  static void success(BuildContext context, String message) => _show(
        context,
        title: 'Success',
        message: message,
        icon: Icons.check_circle_outline_rounded,
        accent: _emerald,
      );

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color accent,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    var removed = false;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _MtToastCard(
        title: title,
        message: message,
        icon: icon,
        accent: accent,
        indigo: _indigo,
        border: _indigoBorder,
        duration: duration,
        onDismiss: () {
          if (removed) return;
          removed = true;
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

/// Maps a caught mutation error into a user-facing `(title, message)`.
///
/// Pure — no [BuildContext] — so it stays unit-testable and reusable at any
/// callsite. Falls back to a friendly generic message for non-Dio errors and
/// unmapped status codes.
(String, String) mapBannerError(Object error) {
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 413:
        // The backend's uploadErrors middleware sends a specific, readable
        // message here ("Image is larger than the 8 MB limit."), so prefer
        // it over anything hardcoded on this side.
        return (
          'Image too large',
          _serverMessage(error) ??
              'Pick a smaller image, or crop it before uploading.',
        );
      case 415:
        return (
          'Unsupported image',
          _serverMessage(error) ?? 'Use a JPEG, PNG or WebP image.',
        );
      case 400:
        return ('Invalid request', _serverMessage(error) ?? 'Check the form and try again.');
      case 404:
        return (
          'Endpoint not found',
          "The banner service (/api/promo-banners) isn't reachable. "
              'Make sure the backend is running or deployed.',
        );
      case 401:
        return (
          'Not authorized',
          'Your admin session has expired. Sign in again and retry.',
        );
      case 403:
        return (
          'Not permitted',
          "This account doesn't have admin rights to manage banners.",
        );
      case 500:
        return (
          'Server error',
          'The server ran into a problem. Please try again in a moment.',
        );
    }
  }
  // A request that reached the server and came back with an undecodable body
  // (a proxy's HTML error page, say) throws a TypeError from the repository's
  // `res.data!` rather than a DioException. Telling the admin to "check your
  // connection" for a save that may well have landed is actively misleading,
  // so name it as a server-response problem instead.
  if (error is TypeError) {
    return (
      'Unexpected server response',
      'The save may have gone through. Refresh before retrying.',
    );
  }
  return (
    'Something went wrong',
    'Check your connection and try again.',
  );
}

/// The backend's `{ "message": "..." }` body, when there is one worth showing.
String? _serverMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['message'] is String) {
    final message = (data['message'] as String).trim();
    if (message.isNotEmpty) return message;
  }
  return null;
}

class _MtToastCard extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final Color indigo;
  final Color border;
  final Duration duration;
  final VoidCallback onDismiss;

  const _MtToastCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    required this.indigo,
    required this.border,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_MtToastCard> createState() => _MtToastCardState();
}

class _MtToastCardState extends State<_MtToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    _autoDismiss = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    _autoDismiss?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24 + media.padding.bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: GestureDetector(
                    onTap: _dismiss,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.indigo,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: widget.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Amber (or emerald) accent rail.
                            Container(
                              width: 5,
                              decoration: BoxDecoration(
                                color: widget.accent,
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(14),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 14, 8, 14),
                              child: Icon(widget.icon,
                                  color: widget.accent, size: 22),
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 12, 12, 12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: MtTextStyles.labelLg
                                          .copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.message,
                                      style: MtTextStyles.bodySm.copyWith(
                                        color: const Color(0xFFC7D2FE),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Explicit close affordance.
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Color(0xFFA5B4FC), size: 18),
                                splashRadius: 18,
                                onPressed: _dismiss,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
