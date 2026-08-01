import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-wide "bubble pop" feedback for real-time events.
///
/// One shared [AudioPlayer] for every trigger site (notification hub,
/// chat, future activity alerts) — a single instance keeps the platform
/// decoder hot so `lowLatency` playback lands in the same frame as the
/// socket push, and means there's exactly one native handle to release
/// on teardown instead of one per notifier.
///
/// Read it through [notificationSoundProvider]; never construct directly.
class NotificationSoundService {
  NotificationSoundService() {
    // `stop` release mode: a new pop interrupts the previous one cleanly
    // instead of queueing — rapid-fire notifications must not stack tails.
    _player.setReleaseMode(ReleaseMode.stop);
  }

  /// Relative to the pubspec `assets/` root (AssetSource convention).
  static const String _asset = 'audio/bubble.mp3';

  /// Hard ceiling on playback. The clip itself is ~1 s, but encoder
  /// padding / a corrupt asset must never leave the platform audio
  /// thread running in the background.
  static const Duration _maxPlayback = Duration(seconds: 1);

  final AudioPlayer _player = AudioPlayer();
  Timer? _stopTimer;

  /// Fire the bubble pop. Safe to call unawaited from socket listeners:
  /// a missing asset on a dev rig or a transient platform-channel error
  /// is swallowed (with a debug log) — sound is feedback, never a
  /// reason to crash the event that triggered it.
  Future<void> playBubble() async {
    try {
      _stopTimer?.cancel();
      await _player.stop();
      await _player.play(AssetSource(_asset), mode: PlayerMode.lowLatency);
      _stopTimer = Timer(_maxPlayback, () {
        unawaited(_player.stop().catchError((_) {}));
      });
    } catch (e) {
      assert(() {
        debugPrint('[sound] bubble pop failed: $e');
        return true;
      }());
    }
  }

  void dispose() {
    _stopTimer?.cancel();
    _stopTimer = null;
    // Fire-and-forget: Riverpod's onDispose is sync.
    unawaited(_player.dispose());
  }
}

/// Root-scoped (non-autoDispose) so the player is created once on first
/// use and lives for the app session — the decoder stays warm across
/// screen changes and sign-in/out cycles.
final notificationSoundProvider = Provider<NotificationSoundService>((ref) {
  final service = NotificationSoundService();
  ref.onDispose(service.dispose);
  return service;
});
