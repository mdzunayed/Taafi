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

  void _view(DispatchAlert alert) {
    HapticFeedback.lightImpact();
    ref.read(dispatchAlertProvider.notifier).dismiss();
    final user = ref.read(currentUserProvider);
    if (user != null) {
      ref.read(appRouterProvider).go(routeForUser(user));
    }
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
    // Side-effects (haptic + auto-dismiss timer) on each new alert.
    ref.listen<DispatchAlert?>(dispatchAlertProvider, _onAlert);
    final alert = ref.watch(dispatchAlertProvider);

    return Stack(
      children: [
        widget.child,
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
                      onView: () => _view(alert),
                      onDismiss: () {
                        HapticFeedback.lightImpact();
                        ref.read(dispatchAlertProvider.notifier).dismiss();
                      },
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('View',
                      style: MtTextStyles.labelMd.copyWith(
                          color: MtColors.brand,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: widget.onDismiss,
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
