import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api/dio_client.dart';
import '../../auth/auth_provider.dart';

/// Production-grade location reporter for the doctor app.
///
/// When the doctor toggles ONLINE we [start] this service; it requests the
/// runtime location permission, subscribes to the platform location stream,
/// and posts each fix to `POST /doctor/location` via [DioClient] — throttled
/// so the network isn't hammered.
///
/// Toggling OFFLINE calls [stop] which cancels the subscription and the
/// throttle timer. The service is idempotent: repeated `start`/`stop` calls
/// don't leak streams.
///
/// State exposure: callers can listen to [statusStream] to surface "Live
/// tracking active" or "Location permission denied" UI without coupling
/// to geolocator directly.
class LocationTrackingService {
  final DioClient _dio;

  /// Resolves the logged-in doctor's id at POST time so a sign-out
  /// followed by a different sign-in doesn't keep flushing under the
  /// previous identity. The provider wires this to
  /// `currentUserProvider.id` (see [locationTrackingServiceProvider]).
  final String? Function() _resolveDoctorId;

  StreamSubscription<Position>? _positionSub;
  Position? _lastReported;
  Timer? _flushTimer;
  bool _running = false;

  final _statusController =
      StreamController<LocationTrackingStatus>.broadcast();

  LocationTrackingService(this._dio, this._resolveDoctorId);

  /// Distance (meters) the doctor must move before we POST again, on top
  /// of the periodic flush. Saves data and battery.
  static const double _minDistanceMeters = 25;

  /// Periodic flush interval. The last known position is re-posted on this
  /// schedule even if the doctor hasn't moved, so the backend sees a
  /// regular heartbeat.
  static const Duration _flushInterval = Duration(seconds: 15);

  Stream<LocationTrackingStatus> get statusStream => _statusController.stream;
  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;

    final ok = await _ensurePermission();
    if (!ok) {
      _statusController.add(LocationTrackingStatus.permissionDenied);
      return;
    }

    _running = true;
    _statusController.add(LocationTrackingStatus.starting);

    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _minDistanceMeters.toInt(),
    );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e, StackTrace _) {
        _statusController.add(LocationTrackingStatus.error);
      },
    );

    _flushTimer = Timer.periodic(_flushInterval, (_) {
      final last = _lastReported;
      if (last != null) _post(last);
    });

    _statusController.add(LocationTrackingStatus.active);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _positionSub?.cancel();
    _positionSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _lastReported = null;
    _statusController.add(LocationTrackingStatus.stopped);
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  void _onPosition(Position pos) {
    _lastReported = pos;
    _post(pos);
  }

  Future<void> _post(Position pos) async {
    final doctorId = _resolveDoctorId();
    if (doctorId == null || doctorId.isEmpty) {
      // Tracker can fire briefly after sign-out before the provider
      // tears down; skip rather than POST a heartbeat with no owner.
      return;
    }
    try {
      await _dio.postDoctorLocation(
        doctorId: doctorId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
        speedMps: pos.speed,
      );
    } catch (_) {
      // Swallow individual failures — the next flush retries. The status
      // stream is reserved for hard errors (permission / disabled service).
    }
  }

  void dispose() {
    _positionSub?.cancel();
    _flushTimer?.cancel();
    _statusController.close();
  }
}

enum LocationTrackingStatus {
  idle,
  starting,
  active,
  permissionDenied,
  error,
  stopped,
}

/// Riverpod handle for the tracking service. Lifetime is tied to the auth
/// session via the parent provider so signing out tears down the stream.
/// The doctor id is resolved lazily (`ref.read`) on each POST so a
/// sign-out followed by a different sign-in immediately swaps owners
/// without re-creating the service.
final locationTrackingServiceProvider =
    Provider<LocationTrackingService>((ref) {
  final dio = ref.watch(dioClientProvider);
  final service = LocationTrackingService(
    dio,
    () => ref.read(currentUserProvider)?.id,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of the service's current operational state. The dashboard listens
/// to this to surface "ONLINE — tracking active" vs a permission-denied
/// warning chip without reading the service directly.
final locationTrackingStatusProvider =
    StreamProvider<LocationTrackingStatus>((ref) {
  final service = ref.watch(locationTrackingServiceProvider);
  return service.statusStream;
});
