import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/admin_chart_data.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../../core/widgets/shimmer_loading_placeholder.dart';
import '../../admin_providers.dart';
import '../../widgets/triage_slide_over.dart';
import 'admin_table_chrome.dart';

class OverviewTab extends ConsumerWidget {
  final ValueChanged<int>? onNavigateTab;

  const OverviewTab({super.key, this.onNavigateTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 1 telemetry endpoint ($facet) drives the four metric cards.
    final kpiAsync = ref.watch(dashboardTelemetryProvider);
    final feedAsync = ref.watch(activityFeedProvider);
    final filter = ref.watch(requestFilterProvider);
    // The Live-activity pulse ring reads its "connected" state off the
    // telemetry feed's health — green + pulsing while data is flowing.
    final telemetryConnected = kpiAsync.hasValue && !kpiAsync.hasError;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI Cards ────────────────────────────────────────────────
          kpiAsync.when(
            loading: () => _buildKpiShimmer(),
            error: (e, _) => MtErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(dashboardTelemetryProvider),
            ),
            data: (kpi) => LayoutBuilder(
              builder: (context, constraints) {
                // Reflow the four telemetry cards instead of forcing them
                // into a rigid Row that clips on narrow viewports. Fit as
                // many ~216px columns as the width allows (capped at 4),
                // then size each card to share the row evenly so they fill
                // the width when there's room and drop to 2-up / 1-up as
                // space tightens — no more right-edge pixel overflow.
                const spacing = 16.0;
                final columns =
                    (constraints.maxWidth / 216).floor().clamp(1, 4);
                final cardWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                final cards = <Widget>[
                  _KpiCard(
                    title: 'ACTIVE SERVICES',
                    value: kpi.activeServices.toString(),
                    badgeLabel: 'live',
                    badgeColor: const Color(0xFFEFF6FF),
                    badgeTextColor: const Color(0xFF2563EB),
                    icon: Icons.medical_services_outlined,
                    iconBg: const Color(0xFFEFF6FF),
                    iconColor: const Color(0xFF2563EB),
                  ),
                  _KpiCard(
                    title: 'PENDING APPROVALS',
                    value: kpi.pendingApprovals.toString(),
                    badgeLabel: '+2',
                    badgeColor: MtColors.brandSoft,
                    badgeTextColor: MtColors.brand,
                    icon: Icons.pending_actions,
                    iconBg: MtColors.brandSofter,
                    iconColor: MtColors.brand,
                  ),
                  _KpiCard(
                    title: 'EMERGENCY ALERTS',
                    value: kpi.emergencyAlerts.toString(),
                    badgeLabel: 'urgent',
                    badgeColor: const Color(0xFFFEE2E2),
                    badgeTextColor: MtColors.rejected,
                    icon: Icons.warning_amber_rounded,
                    iconBg: const Color(0xFFFEE2E2),
                    iconColor: MtColors.rejected,
                    isEmergency: kpi.emergencyAlerts > 0,
                  ),
                  _KpiCard(
                    title: 'DAILY REVENUE',
                    value: '৳${_formatNumber(kpi.dailyRevenue)}',
                    badgeLabel: '+${kpi.revenueDelta.toStringAsFixed(0)}%',
                    badgeColor: const Color(0xFFDCFCE7),
                    badgeTextColor: const Color(0xFF16A34A),
                    icon: Icons.trending_up,
                    iconBg: const Color(0xFFDCFCE7),
                    iconColor: const Color(0xFF16A34A),
                  ),
                ];
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final card in cards)
                      SizedBox(width: cardWidth, child: card),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ── Urgency Toggle ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: filter.urgencyOnly
                  ? const Color(0xFFFEE2E2)
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: filter.urgencyOnly
                    ? MtColors.rejected
                    : MtColors.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 18,
                  color: filter.urgencyOnly
                      ? MtColors.rejected
                      : MtColors.ink3,
                ),
                const SizedBox(width: 8),
                // Flexible so the label shrinks/ellipsizes instead of forcing
                // the min-width Row past a tight parent (the `w<=148` overflow).
                Flexible(
                  child: Text(
                    'High Urgency Only',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: MtTextStyles.labelMd.copyWith(
                      color: filter.urgencyOnly
                          ? MtColors.rejected
                          : MtColors.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: filter.urgencyOnly,
                    activeColor: MtColors.rejected,
                    onChanged: (v) {
                      ref.read(requestFilterProvider.notifier).state =
                          filter.copyWith(urgencyOnly: v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Chart + Activity Feed ────────────────────────────────────
          // Responsive split: side-by-side on desktop, stacked on compact
          // viewports. Each branch hands its children a BOUNDED height so
          // the chart canvas + the feed's scrolling list never collapse or
          // clip — the 192px overflow seen on narrow windows is gone.
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final chartCard = _buildChartCard();
              final activityCard =
                  _buildActivityCard(ref, feedAsync, telemetryConnected);

              if (isWide) {
                return SizedBox(
                  height: 420,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: chartCard),
                      const SizedBox(width: 24),
                      Expanded(flex: 1, child: activityCard),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  SizedBox(height: 350, child: chartCard),
                  const SizedBox(height: 16),
                  SizedBox(height: 350, child: activityCard),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // ── Pending Review Table ─────────────────────────────────────
          _PendingReviewSection(onNavigateTab: onNavigateTab),
        ],
      ),
    );
  }

  // "Requests — past 7 days" card. The chart canvas is an `Expanded` so it
  // grows to fill whatever bounded height the responsive parent hands it
  // (420 on desktop, 350 stacked) instead of a hard-coded 220 that clipped.
  // The header degrades gracefully: the title block flexes + ellipsises and
  // the legend stays `min`-sized so the row can't overflow horizontally.
  Widget _buildChartCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Requests — past 7 days',
                        style: MtTextStyles.labelLg),
                    Text(
                      'Approved vs declined, post-surgery care',
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendItem(color: MtColors.brand, label: 'Approved'),
                  const SizedBox(width: 16),
                  _LegendItem(color: MtColors.line, label: 'Declined'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Expanded(child: _LiveBarChart()),
        ],
      ),
    );
  }

  // "Live activity" card. Always renders the card chrome, with the async
  // feed driving the inner list. The list is an `Expanded` over the bounded
  // card height so it scrolls internally instead of pushing the layout past
  // the viewport.
  Widget _buildActivityCard(
    WidgetRef ref,
    AsyncValue<List<ActivityEvent>> feedAsync,
    bool telemetryConnected,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(activityFeedProvider),
        ),
        data: (events) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _LivePulseRing(connected: telemetryConnected),
                const SizedBox(width: 10),
                Text('Live activity', style: MtTextStyles.labelLg),
                const Spacer(),
                Text('${events.length} events',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: MtColors.line),
                itemBuilder: (_, i) => _ActivityEventTile(event: events[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The four telemetry cards load as moving grey silhouettes (matched height +
  // 12px radius) instead of spinners, so the KPI row never reflows or flickers
  // when the live numbers land.
  Widget _buildKpiShimmer() => const ShimmerKpiRow(count: 4, cardHeight: 100);

  static String _formatNumber(double n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k'.replaceFirst('k', ',${(n % 1000).toInt().toString().padLeft(3, '0')}');
    }
    return n.toStringAsFixed(0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KPI Card
// ═══════════════════════════════════════════════════════════════════════════════

class _KpiCard extends StatefulWidget {
  final String title;
  final String value;
  final String? badgeLabel;
  final Color badgeColor;
  final Color badgeTextColor;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final bool isEmergency;

  const _KpiCard({
    required this.title,
    required this.value,
    this.badgeLabel,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.isEmergency = false,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isEmergency
                ? MtColors.rejected.withValues(alpha: 0.5)
                : MtColors.line,
          ),
          boxShadow: widget.isEmergency
              ? [
                  BoxShadow(
                    color: MtColors.rejected.withValues(alpha: 0.1),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 18),
                ),
                const Spacer(),
                if (widget.badgeLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.badgeLabel!,
                      style: MtTextStyles.labelSm.copyWith(
                        color: widget.badgeTextColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.value,
              style: MtTextStyles.h1.copyWith(
                color: widget.isEmergency ? MtColors.rejected : MtColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.title,
              style: MtTextStyles.labelSm
                  .copyWith(color: MtColors.ink3, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Activity Event Tile
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivityEventTile extends StatelessWidget {
  final ActivityEvent event;

  const _ActivityEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _eventColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(_eventIcon, size: 16, color: _eventColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: MtTextStyles.bodySm.copyWith(
                    color: MtColors.ink,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _timeAgo(event.timestamp),
                  style: MtTextStyles.bodySm
                      .copyWith(color: MtColors.ink3, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _eventColor {
    switch (event.eventType) {
      case ActivityEventType.emergency:
        return MtColors.rejected;
      case ActivityEventType.arrival:
        return const Color(0xFF2563EB);
      case ActivityEventType.assignment:
        return MtColors.brand;
      case ActivityEventType.completion:
        return const Color(0xFF059669);
      case ActivityEventType.system:
        return MtColors.ink3;
    }
  }

  IconData get _eventIcon {
    switch (event.eventType) {
      case ActivityEventType.emergency:
        return Icons.warning_amber_rounded;
      case ActivityEventType.arrival:
        return Icons.location_on;
      case ActivityEventType.assignment:
        return Icons.person_add;
      case ActivityEventType.completion:
        return Icons.check_circle;
      case ActivityEventType.system:
        return Icons.info_outline;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Pending Review Section
// ═══════════════════════════════════════════════════════════════════════════════

class _PendingReviewSection extends ConsumerWidget {
  final ValueChanged<int>? onNavigateTab;

  const _PendingReviewSection({this.onNavigateTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(filteredRequestsProvider);
    final pending = requests.where((r) => r.status == 'pending').take(4).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pending review', style: MtTextStyles.labelLg),
                  Text(
                    '${pending.length} requests · sorted by urgency',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: () => onNavigateTab?.call(1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MtColors.ink,
                  side: const BorderSide(color: MtColors.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  children: [
                    Text('Open queue', style: MtTextStyles.labelMd),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('REQUEST',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
                Expanded(
                    flex: 3,
                    child: Text('PATIENT',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
                Expanded(
                    flex: 3,
                    child: Text('SERVICE',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
                Expanded(
                    flex: 2,
                    child: Text('AREA',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
                Expanded(
                    flex: 2,
                    child: Text('OFFERED',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
                Expanded(
                    flex: 2,
                    child: Text('URGENCY',
                        style: MtTextStyles.labelSm
                            .copyWith(color: MtColors.ink3))),
              ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 40, color: MtColors.ink3.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text('All caught up!',
                        style: MtTextStyles.labelLg
                            .copyWith(color: MtColors.ink3)),
                  ],
                ),
              ),
            )
          else
            ...pending.map((r) => _PendingRow(
                  request: r,
                  onNavigateTab: onNavigateTab,
                )),
        ],
      ),
    );
  }
}

class _PendingRow extends ConsumerWidget {
  final AdminCareRequest request;
  final ValueChanged<int>? onNavigateTab;

  const _PendingRow({required this.request, this.onNavigateTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ageMinutes = DateTime.now().difference(request.createdAt).inMinutes;
    final ageLabel = ageMinutes < 60 ? '${ageMinutes}m' : '${ageMinutes ~/ 60}h';

    return InkWell(
      onTap: () => showTriageSlideOver(
        context,
        request: request,
        onAssignTeam: () {
          Navigator.pop(context); // close slide-over
          ref.read(selectedRequestProvider.notifier).state = request;
          onNavigateTab?.call(2);
        },
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
              Expanded(
                flex: 2,
                child: AdminIdCell(id: request.id, urgent: request.isUrgent),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '${request.patientName}, ${request.patientAge}${request.patientGender ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(request.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2)),
              ),
              Expanded(
                flex: 2,
                child: Text(request.area,
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2)),
              ),
              Expanded(
                flex: 2,
                child: Text('৳${request.patientOffer.toStringAsFixed(0)}',
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3)),
              ),
              Expanded(
                flex: 2,
                child: _UrgencyBadge(level: request.urgencyLevel, age: ageLabel),
              ),
            ],
            ),
          ),
          const Divider(height: 1, color: MtColors.line),
        ],
      ),
    );
  }
}

class _UrgencyBadge extends StatelessWidget {
  final UrgencyLevel level;
  final String age;

  const _UrgencyBadge({required this.level, required this.age});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bg;
    String label;
    switch (level) {
      case UrgencyLevel.critical:
        color = MtColors.rejected;
        bg = const Color(0xFFFEE2E2);
        label = 'CRITICAL';
      case UrgencyLevel.high:
        color = const Color(0xFFD97706);
        bg = const Color(0xFFFEF9C3);
        label = 'HIGH';
      case UrgencyLevel.medium:
        color = MtColors.brand;
        bg = MtColors.brandSoft;
        label = 'MEDIUM';
      case UrgencyLevel.low:
        color = const Color(0xFF059669);
        bg = const Color(0xFFDCFCE7);
        label = 'LOW';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style:
                  MtTextStyles.labelSm.copyWith(color: color, fontSize: 9)),
        ),
        const SizedBox(width: 6),
        Text(age,
            style: MtTextStyles.bodySm
                .copyWith(color: MtColors.ink3, fontSize: 10)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Chart + Legend (kept from original)
// ═══════════════════════════════════════════════════════════════════════════════

/// Status pulse ring for the "Live activity" panel. When [connected] it
/// emits a soft, repeating green halo to signal live admin socket / poll
/// operations; when disconnected it collapses to a static grey dot.
class _LivePulseRing extends StatefulWidget {
  final bool connected;
  const _LivePulseRing({required this.connected});

  @override
  State<_LivePulseRing> createState() => _LivePulseRingState();
}

class _LivePulseRingState extends State<_LivePulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const _green = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    if (widget.connected) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _LivePulseRing old) {
    super.didUpdateWidget(old);
    if (widget.connected && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.connected && _ctrl.isAnimating) {
      _ctrl
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: MtColors.ink3,
          shape: BoxShape.circle,
        ),
      );
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value; // 0 → 1
          return Stack(
            alignment: Alignment.center,
            children: [
              // Expanding, fading halo.
              Container(
                width: 8 + 10 * t,
                height: 8 + 10 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green.withValues(alpha: (1 - t) * 0.35),
                ),
              ),
              // Solid core.
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _green,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
      ],
    );
  }
}

/// Live "Requests — past 7 days" bar chart, backed by
/// [adminChartDataProvider] (which polls `/admin/chart-data` every 15 s).
/// Two side-by-side bars per day:
///   • brand orange = approved + completed
///   • grey         = rejected + cancelled
class _LiveBarChart extends ConsumerWidget {
  const _LiveBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminChartDataProvider);
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => MtErrorState(
        message: e.toString(),
        onRetry: () =>
            ref.read(adminChartDataProvider.notifier).refresh(),
      ),
      data: (data) => data.isEmpty
          ? Center(
              child: Text(
                'No requests in the past 7 days yet.',
                style:
                    MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
            )
          : _BarChartCanvas(data: data),
    );
  }
}

class _BarChartCanvas extends StatelessWidget {
  final AdminChartData data;
  const _BarChartCanvas({required this.data});

  @override
  Widget build(BuildContext context) {
    // Y-axis ceiling — 4 ticks above the max, snapped to a nice integer
    // so the gridlines read clean instead of "12.5 / 25.0 / 37.5".
    final rawMax = data.max;
    final niceMax = _niceCeiling(rawMax == 0 ? 4 : rawMax);
    final interval = (niceMax / 4).clamp(1, double.infinity).toDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: niceMax.toDouble(),
        minY: 0,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => MtColors.ink,
            tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              final point = data.series[group.x];
              final label = rodIdx == 0 ? 'Approved' : 'Declined';
              return BarTooltipItem(
                '${point.label} · $label\n${rod.toY.toInt()}',
                MtTextStyles.labelSm
                    .copyWith(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value > niceMax) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value.toInt().toString(),
                    style: MtTextStyles.labelSm
                        .copyWith(color: MtColors.ink3, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.series.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data.series[idx].label,
                    style: MtTextStyles.labelSm
                        .copyWith(color: MtColors.ink3),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: MtColors.line,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < data.series.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: data.series[i].approved.toDouble(),
                  width: 12,
                  color: MtColors.brand,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: data.series[i].declined.toDouble(),
                  width: 12,
                  color: MtColors.line,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Rounds a raw max up to the nearest "nice" gridline (1/2/5/10
  /// multiplied by a power of 10). Keeps the Y-axis labels readable
  /// instead of showing e.g. "17 / 8.5".
  int _niceCeiling(int v) {
    if (v <= 4) return 4;
    final pow10 = _pow10(v);
    final base = v / pow10;
    final nice = base <= 1
        ? 1
        : base <= 2
            ? 2
            : base <= 5
                ? 5
                : 10;
    return (nice * pow10).toInt();
  }

  int _pow10(int v) {
    var p = 1;
    while (v >= p * 10) {
      p *= 10;
    }
    return p;
  }
}
