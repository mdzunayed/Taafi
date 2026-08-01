import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../../core/widgets/mt_skeleton.dart';
import '../../admin_providers.dart';

/// Real-time monitor showing every visit that's currently dispatched, in
/// transit, or in service. The right sidebar is bound to [liveServicesProvider];
/// a [Timer.periodic] silently re-fetches every 30s and a manual Refresh
/// button lets the admin pull immediately when they need an authoritative
/// snapshot.
class LiveMonitorTab extends ConsumerStatefulWidget {
  const LiveMonitorTab({super.key});

  @override
  ConsumerState<LiveMonitorTab> createState() => _LiveMonitorTabState();
}

class _LiveMonitorTabState extends ConsumerState<LiveMonitorTab> {
  Timer? _refreshTimer;
  DateTime _lastRefreshed = DateTime.now();
  // Ticks every 15s just to update the "refreshed Xs ago" label between real
  // refreshes; keeps the time display honest without re-fetching.
  Timer? _displayTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      ref.invalidate(liveServicesProvider);
      setState(() => _lastRefreshed = DateTime.now());
    });
    _displayTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {}); // re-render the "refreshed ago" label
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _displayTimer?.cancel();
    super.dispose();
  }

  void _manualRefresh() {
    ref.invalidate(liveServicesProvider);
    setState(() => _lastRefreshed = DateTime.now());
  }

  String _refreshedAgoLabel() {
    final secs = DateTime.now().difference(_lastRefreshed).inSeconds;
    if (secs < 5) return 'refreshed just now';
    if (secs < 60) return 'refreshed ${secs}s ago';
    final mins = secs ~/ 60;
    return 'refreshed ${mins}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(liveServicesProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: map ────────────────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: MtColors.rejected,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Live map · Dhaka',
                            style: MtTextStyles.labelLg),
                        const SizedBox(width: 12),
                        Builder(
                          builder: (_) {
                            final count = liveAsync.maybeWhen(
                              data: (v) => v.length,
                              orElse: () => null,
                            );
                            final label = count == null
                                ? _refreshedAgoLabel()
                                : '$count services in progress · ${_refreshedAgoLabel()}';
                            return Text(
                              label,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: MtColors.ink3),
                            );
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _LegendDot(
                            color: const Color(0xFF2563EB),
                            label: 'En route'),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: MtColors.brand, label: 'Arrived'),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: const Color(0xFF8B5CF6),
                            label: 'In service'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MtColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: liveAsync.when(
                      loading: () => Container(
                        color: MtColors.bg,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) => Container(
                        color: MtColors.bg,
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: MtErrorState(
                          message: e.toString(),
                          onRetry: _manualRefresh,
                        ),
                      ),
                      data: (services) => _LiveMap(services: services),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Right: sidebar list ─────────────────────────────────────────
        Container(
          width: 340,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: MtColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active services',
                              style: MtTextStyles.labelLg),
                          Text(
                            'Auto-refreshes every 10s',
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: MtColors.ink2,
                      tooltip: 'Refresh now',
                      onPressed: _manualRefresh,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MtColors.line),
              Expanded(
                child: liveAsync.when(
                  loading: () => ListView.separated(
                    itemCount: 4,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: MtColors.line),
                    itemBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MtSkeleton.line(width: 80, height: 10),
                          const SizedBox(height: 10),
                          MtSkeleton.line(width: 160),
                          const SizedBox(height: 6),
                          MtSkeleton.line(width: 200, height: 10),
                          const SizedBox(height: 14),
                          MtSkeleton.box(height: 4, radius: 2),
                        ],
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: MtErrorState(
                      message: e.toString(),
                      onRetry: _manualRefresh,
                    ),
                  ),
                  data: (services) {
                    if (services.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: MtEmptyState(
                          icon: Icons.medical_services_outlined,
                          title: 'No active services',
                          subtitle:
                              'Once a visit is dispatched, it will appear here in real time.',
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: services.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: MtColors.line),
                      itemBuilder: (_, i) =>
                          _ActiveServiceItem(service: services[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

({Color color, Color bg, String label}) _statusVisuals(LiveServiceStatus s) {
  switch (s) {
    case LiveServiceStatus.onTheWay:
      return (
        color: const Color(0xFF2563EB),
        bg: const Color(0xFFEFF6FF),
        label: 'ON THE WAY',
      );
    case LiveServiceStatus.arrived:
      return (
        color: MtColors.brand,
        bg: MtColors.brandSoft,
        label: 'ARRIVED',
      );
    case LiveServiceStatus.inService:
      return (
        color: const Color(0xFF8B5CF6),
        bg: const Color(0xFFF5F3FF),
        label: 'IN SERVICE',
      );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2)),
      ],
    );
  }
}

class _ActiveServiceItem extends StatelessWidget {
  final LiveServiceUpdate service;

  const _ActiveServiceItem({required this.service});

  @override
  Widget build(BuildContext context) {
    final visuals = _statusVisuals(service.status);
    final progressColor = service.status == LiveServiceStatus.arrived
        ? MtColors.line
        : visuals.color;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(service.id,
                  style: MtTextStyles.labelSm
                      .copyWith(color: MtColors.ink3)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: visuals.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: visuals.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      visuals.label,
                      style: MtTextStyles.labelSm.copyWith(
                        color: visuals.color,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(service.patientName, style: MtTextStyles.labelLg),
          Text(
            service.doctorWithArea,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: service.progressPercent.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                service.timeLabel,
                style: MtTextStyles.labelSm.copyWith(
                  color: MtColors.ink3,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Real OpenStreetMap-backed live map (flutter_map, no API key). Plots one
/// pin per active visit at its assigned provider's live GPS
/// (`current_location`, surfaced by the extended `/admin/live-services`).
/// Providers without a recent heartbeat carry null coords and are counted in
/// an overlay rather than plotted. Centres on Dhaka by default.
class _LiveMap extends StatelessWidget {
  final List<LiveServiceUpdate> services;
  const _LiveMap({required this.services});

  static const _dhaka = LatLng(23.8103, 90.4125);

  @override
  Widget build(BuildContext context) {
    final located = services
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();

    // Centre on the mean of plotted providers, else Dhaka.
    LatLng center = _dhaka;
    if (located.isNotEmpty) {
      final lat = located.map((s) => s.latitude!).reduce((a, b) => a + b) /
          located.length;
      final lng = located.map((s) => s.longitude!).reduce((a, b) => a + b) /
          located.length;
      center = LatLng(lat, lng);
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: located.isEmpty ? 11 : 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.taafi.admin',
            ),
            MarkerLayer(
              markers: [
                for (final s in located)
                  Marker(
                    point: LatLng(s.latitude!, s.longitude!),
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: _MapPin(
                      color: _statusVisuals(s.status).color,
                      label: '${s.doctorName} · ${s.patientName}',
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Live-location coverage overlay.
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MtColors.line),
            ),
            child: Text(
              located.isEmpty
                  ? 'No providers sharing live location'
                  : '${located.length} of ${services.length} sharing live GPS',
              style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2),
            ),
          ),
        ),
        // Attribution (OSM tile usage policy).
        const Positioned(
          right: 6,
          bottom: 4,
          child: Text(
            '© OpenStreetMap',
            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }
}

/// A rounded map marker with a hover tooltip naming the provider + patient.
class _MapPin extends StatelessWidget {
  final Color color;
  final String label;
  const _MapPin({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.person, size: 13, color: Colors.white),
          ),
          // Little downward stem so the pin reads as anchored to the point.
          Container(width: 2, height: 6, color: color),
        ],
      ),
    );
  }
}
