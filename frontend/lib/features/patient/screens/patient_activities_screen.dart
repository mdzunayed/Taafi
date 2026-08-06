import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../navigation/patient_nav_provider.dart';
import '../history/patient_history_tab.dart';
import '../../prescriptions/medications_tab_view.dart';
import 'active_care_tab.dart';

/// Unified activity hub for the patient: **Active Care**, **History**,
/// **Medications**.
///
/// Was four tabs. "Under Review" and "Service Status" were the same booking
/// rendered twice — two timelines derived from two different sources that
/// disagreed on which step the patient was on, with the deposit CTA on one and
/// the assigned provider's phone number on the other. They are now a single
/// [ActiveCareTab].
///
/// State is driven by [patientActivitiesTabProvider] so deep-link helpers in
/// `patient_nav_provider.dart` can address any sub-tab atomically.
class PatientActivitiesScreen extends ConsumerStatefulWidget {
  const PatientActivitiesScreen({super.key});

  @override
  ConsumerState<PatientActivitiesScreen> createState() =>
      _PatientActivitiesScreenState();
}

class _PatientActivitiesScreenState
    extends ConsumerState<PatientActivitiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(patientActivitiesTabProvider);
    _tabController = TabController(
      length: PatientActivitiesTab.values.length,
      initialIndex: initial.index,
      vsync: this,
    );
    _tabController.addListener(_onLocalSwipe);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onLocalSwipe);
    _tabController.dispose();
    super.dispose();
  }

  /// When the user swipes the TabBarView, push the new index back
  /// into the Riverpod notifier so the source of truth stays single.
  void _onLocalSwipe() {
    if (_tabController.indexIsChanging) return;
    final wire = PatientActivitiesTab.values[_tabController.index];
    if (wire != ref.read(patientActivitiesTabProvider)) {
      ref
          .read(patientActivitiesTabProvider.notifier)
          .setTab(wire);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactive sync from the provider into the local controller so
    // external `ref.goToActivities(sub: …)` calls move the TabBar
    // even though the local state object is the controller.
    ref.listen<PatientActivitiesTab>(patientActivitiesTabProvider,
        (prev, next) {
      if (_tabController.index != next.index) {
        _tabController.animateTo(next.index);
      }
    });

    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const _ActivitiesHeader(),
                _ActivitiesTabBar(controller: _tabController),
                const SizedBox(height: 4),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const ClampingScrollPhysics(),
                    children: const [
                      ActiveCareTab(),
                      PatientHistoryTab(),
                      MedicationsTabView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header + tab bar
// ---------------------------------------------------------------------------

class _ActivitiesHeader extends ConsumerWidget {
  const _ActivitiesHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => ref.goToHome(),
            icon: Icon(Icons.arrow_back, color: c.accent),
            tooltip: 'Back to home',
          ),
          Expanded(
            child: Text(
              'Your activities',
              style: MtTextStyles.h1.copyWith(color: c.title),
            ),
          ),
          const NotificationBell(),
        ],
      ),
    );
  }
}

class _ActivitiesTabBar extends StatelessWidget {
  final TabController controller;
  const _ActivitiesTabBar({required this.controller});

  // Below this container width the bar switches to horizontal scroll so text
  // is never clipped or compressed. Dropped from 520 when the four tabs became
  // three: "Active Care" is the longest label and three even divisions on a
  // ~390 pt handset give each ~127 pt, which it fits comfortably.
  static const double _scrollThreshold = 340.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isScrollable = constraints.maxWidth < _scrollThreshold;
          final c = context.appColors;
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              // Soft tonal tray — sits just above the canvas
              color: c.surfaceHi,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.cardBorder),
            ),
            child: TabBar(
              controller: controller,
              // Pill-shaped sliding indicator with a brand glow
              indicator: BoxDecoration(
                color: c.brand,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: c.glow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: c.onAccent,
              unselectedLabelColor: c.body,
              // 14pt now that each pill is a single English line — the 12pt
              // base was sized for the two-line bilingual label.
              labelStyle: MtTextStyles.labelMd
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: MtTextStyles.labelMd
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w500),
              // Scrollable: give each tab comfortable side padding so
              // labels breathe. Fill: zero padding lets Flutter distribute
              // the full container width evenly across all three tabs.
              labelPadding: isScrollable
                  ? const EdgeInsets.symmetric(horizontal: 16)
                  : EdgeInsets.zero,
              splashBorderRadius: BorderRadius.circular(20),
              isScrollable: isScrollable,
              tabAlignment:
                  isScrollable ? TabAlignment.start : TabAlignment.fill,
              // Plain [Tab]s: a single-line label needs no custom child, and
              // `text:` inherits the resolved label/unselected colour and
              // weight that TabBar pushes down.
              tabs: const [
                Tab(text: 'Active Care'),
                Tab(text: 'History'),
                Tab(text: 'Medications'),
              ],
            ),
          );
        },
      ),
    );
  }
}
