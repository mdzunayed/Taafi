import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_open_ad_providers.dart';
import '../../../core/models/app_open_ad.dart';
import '../../../core/theme/mt_text_styles.dart';

/// Full-screen app-open ad gate. Mounted above the patient shell (last child
/// of a [Stack]) so it intercepts the very first frame after launch:
///
///   1. While the launch check runs (bounded to 3 s in [launchAdProvider])
///      it holds an opaque canvas-coloured scrim — the user never sees Home
///      flash before the ad.
///   2. With an active campaign, it shows the ad image full-screen and
///      counts down `durationInSeconds`, then fades itself out and latches
///      [appOpenAdShownProvider] so the ad never replays this session.
///   3. With no campaign (or any fetch failure) it latches immediately and
///      renders nothing.
class AppOpenAdInterstitial extends ConsumerStatefulWidget {
  const AppOpenAdInterstitial({super.key});

  @override
  ConsumerState<AppOpenAdInterstitial> createState() =>
      _AppOpenAdInterstitialState();
}

class _AppOpenAdInterstitialState extends ConsumerState<AppOpenAdInterstitial> {
  Timer? _ticker;
  int? _remaining;
  bool _fadingOut = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Idempotent — build() calls this every frame while the ad shows, but the
  /// countdown must only start once.
  void _startCountdown(AppOpenAd ad) {
    if (_remaining != null) return;
    _remaining = ad.durationInSeconds.clamp(1, 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = _remaining! - 1;
        if (_remaining! <= 0) {
          _ticker?.cancel();
          _fadingOut = true;
        }
      });
    });
  }

  /// Latch the session flag outside of build (mutating a provider mid-build
  /// throws) — after this the widget renders [SizedBox.shrink] for the rest
  /// of the app session.
  void _latchDone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appOpenAdShownProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appOpenAdShownProvider)) return const SizedBox.shrink();

    final adAsync = ref.watch(launchAdProvider);
    return adAsync.when(
      loading: () => _HoldingScrim(color: Theme.of(context).scaffoldBackgroundColor),
      error: (_, _) {
        _latchDone();
        return const SizedBox.shrink();
      },
      data: (ad) {
        if (ad == null || ad.imageUrl.isEmpty) {
          _latchDone();
          return const SizedBox.shrink();
        }
        _startCountdown(ad);
        return AnimatedOpacity(
          opacity: _fadingOut ? 0 : 1,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          onEnd: () {
            if (_fadingOut) _latchDone();
          },
          // Once faded we still need to stop swallowing taps while the
          // post-frame latch lands.
          child: IgnorePointer(
            ignoring: _fadingOut,
            child: _AdSurface(ad: ad, remaining: _remaining ?? ad.durationInSeconds),
          ),
        );
      },
    );
  }
}

class _AdSurface extends StatelessWidget {
  final AppOpenAd ad;
  final int remaining;
  const _AdSurface({required this.ad, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: ad.imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
            // A broken asset shouldn't strand the patient on a black
            // screen with nothing to look at; the countdown still runs
            // and releases them to Home.
            errorWidget: (_, _, _) => const SizedBox.expand(),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'Ad · ${remaining}s',
                    style: MtTextStyles.labelMd.copyWith(color: Colors.white),
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

/// Opaque placeholder shown for at most ~3 s while the launch check runs, so
/// the transition is splash → (ad | Home) with no Home flash in between.
class _HoldingScrim extends StatelessWidget {
  final Color color;
  const _HoldingScrim({required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
