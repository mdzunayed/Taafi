import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../router/app_router.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';
import 'socket_manager.dart';

/// Wraps the whole routed app and paints an intrusive "Incoming Dispatch"
/// card the instant a `dispatch:incoming` socket event arrives — with a
/// mechanical haptic buzz — on top of whatever screen the clinician is on,
/// with zero manual refresh. Mounting this also keeps the authenticated
/// [socketManagerProvider] connection alive app-wide while signed in.
class DispatchOverlayHost extends ConsumerStatefulWidget {
  final Widget child;
  const DispatchOverlayHost({super.key, required this.child});

  @override
  ConsumerState<DispatchOverlayHost> createState() =>
      _DispatchOverlayHostState();
}

class _DispatchOverlayHostState extends ConsumerState<DispatchOverlayHost> {
  Timer? _autoDismiss;

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  void _onAlert(DispatchAlert? previous, DispatchAlert? next) {
    if (next == null) {
      _autoDismiss?.cancel();
      return;
    }
    // Mechanical warning buzz for a brand-new incoming dispatch.
    HapticFeedback.vibrate();
    _autoDismiss?.cancel();
    _autoDismiss = Timer(const Duration(seconds: 12), () {
      if (mounted) ref.read(dispatchAlertProvider.notifier).dismiss();
    });
  }

  void _view() {
    HapticFeedback.lightImpact();
    ref.read(dispatchAlertProvider.notifier).dismiss();
    final user = ref.read(currentUserProvider);
    if (user != null) {
      ref.read(appRouterProvider).go(routeForUser(user));
    }
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    ref.read(dispatchAlertProvider.notifier).dismiss();
  }

  @override
  Widget build(BuildContext context) {
    // Pin the app-wide notification hub alive for the whole signed-in
    // session. It owns the chat chime (`notification_provider.dart`), and
    // this host is the one widget mounted above every route — including
    // full-screen chats whose AppBars don't carry the bell that would
    // otherwise keep the (autoDispose) hub in scope. Without this, walking
    // into a chat could tear the chime source down.
    ref.watch(notificationProvider);
    // Side-effects (haptic + auto-dismiss timer) on each new alert. Listening
    // (rather than watching) also keeps the autoDispose alert provider alive
    // without rebuilding the entire routed app under us on every dispatch —
    // the banner layer below watches it and repaints on its own.
    ref.listen<DispatchAlert?>(dispatchAlertProvider, _onAlert);

    return Stack(
      children: [
        widget.child,
        // This host is mounted from `MaterialApp.builder`, i.e. ABOVE the
        // router's Navigator — so nothing here inherits the app's Overlay.
        // Material widgets that float a layer (the dismiss button's Tooltip,
        // ink splashes, any future menu) would throw "No Overlay widget
        // found". Give the banner its own full-screen Overlay + Material so
        // it is self-sufficient. It fills the Stack for layout only; neither
        // the Overlay nor its Stack absorbs hit-tests, so taps outside the
        // banner still reach the app underneath.
        Positioned.fill(
          child: _DispatchBannerLayer(onView: _view, onDismiss: _dismiss),
        ),
      ],
    );
  }
}

/// Owns the Overlay that the incoming-dispatch banner paints inside.
///
/// The single [OverlayEntry] is created once (`initialEntries` is only read on
/// mount), so the entry deliberately does not close over the current alert —
/// [_DispatchBanner] watches the provider itself and rebuilds in place.
class _DispatchBannerLayer extends StatelessWidget {
  final VoidCallback onView;
  final VoidCallback onDismiss;
  const _DispatchBannerLayer({required this.onView, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) =>
                _DispatchBanner(onView: onView, onDismiss: onDismiss),
          ),
        ],
      ),
    );
  }
}

class _DispatchBanner extends ConsumerWidget {
  final VoidCallback onView;
  final VoidCallback onDismiss;
  const _DispatchBanner({required this.onView, required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(dispatchAlertProvider);

    // The overlay entry is laid out tight to the full screen; pin the banner
    // to the top edge instead of letting it stretch/centre.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: alert == null
                  ? const SizedBox.shrink(key: ValueKey('no-dispatch'))
                  : _DispatchCard(
                      key: ValueKey(alert.appointmentId),
                      alert: alert,
                      onView: onView,
                      onDismiss: onDismiss,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DispatchCard extends StatefulWidget {
  final DispatchAlert alert;
  final VoidCallback onView;
  final VoidCallback onDismiss;
  const _DispatchCard({
    super.key,
    required this.alert,
    required this.onView,
    required this.onDismiss,
  });

  @override
  State<_DispatchCard> createState() => _DispatchCardState();
}

class _DispatchCardState extends State<_DispatchCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final glow = 0.25 + 0.30 * _pulse.value;
            return Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MtColors.brand, MtColors.brand700],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: MtColors.brand.withValues(alpha: glow),
                    blurRadius: 16 + 10 * _pulse.value,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              // Every child is either fixed-and-small or flexible, so the
              // banner survives narrow phones and split-screen windows
              // without painting the yellow overflow stripes.
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.crisis_alert_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Incoming dispatch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.labelLg.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.alert.patientName} · ${widget.alert.careType}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.bodySm.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.onView,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: MtColors.brand,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('View',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.labelMd.copyWith(
                          color: MtColors.brand,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                      width: 36, height: 36),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
