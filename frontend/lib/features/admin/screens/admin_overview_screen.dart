import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/mt_search_field.dart';
import '../../auth/auth_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../chat/presentation/conversation_inbox_button.dart';
import '../admin_providers.dart';
import 'tabs/admin_banner_management_page.dart';
import 'tabs/admin_booking_review.dart';
import 'tabs/admin_cash_clearance_page.dart';
import 'tabs/admin_finance_page.dart';
import 'tabs/admin_home_sections_page.dart';
import 'tabs/assign_team_tab.dart';
import 'tabs/billing_tab.dart';
import 'tabs/live_booking_pipeline_page.dart';
import 'tabs/live_monitor_tab.dart';
import 'tabs/manage_services_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/patients_tab.dart';
import 'tabs/prescription_approval_tab.dart';
import 'tabs/provider_verification_tab.dart';
import 'tabs/providers_tab.dart';
import 'tabs/review_queue_tab.dart';
import 'tabs/settings_tab.dart';

class AdminOverviewScreen extends ConsumerStatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  ConsumerState<AdminOverviewScreen> createState() =>
      _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends ConsumerState<AdminOverviewScreen> {
  int _selectedIndex = 0;

  /// Sidebar visibility flag. `false` = full 260px rail; `true` = the
  /// 70px icon-only rail. Toggled from the rail header; the width change
  /// animates via the sidebar's `AnimatedContainer`.
  bool _isSidebarCollapsed = false;

  void _toggleSidebar() =>
      setState(() => _isSidebarCollapsed = !_isSidebarCollapsed);

  // Indices are referenced by the sidebar `_SidebarItem`s below — keep
  // these in lockstep with that list when reordering.
  //   0 Overview          5 Providers        10 Booking review     15 Doctor verification
  //   1 Review queue      6 Patients         11 Home sections      16 Nurse verification
  //   2 Assign team       7 Billing          12 Rx approvals       17 Provider payouts
  //   3 Live monitor      8 Settings         13 Booking pipeline
  //   4 Manage services   9 Banners          14 Cash clearance
  late final _tabs = <Widget>[
    OverviewTab(onNavigateTab: _navigate),
    ReviewQueueTab(onNavigateTab: _navigate),
    AssignTeamTab(onNavigateTab: _navigate),
    const LiveMonitorTab(),
    const ManageServicesTab(),
    const ProvidersTab(),
    const PatientsTab(),
    const BillingTab(),
    const SettingsTab(),
    const AdminBannerManagementPage(),
    const AdminBookingReviewPage(),
    const AdminHomeSectionsPage(),
    const PrescriptionApprovalTab(),
    LiveBookingPipelinePage(onNavigateTab: _navigate),
    const AdminCashClearancePage(),
    const ProviderVerificationTab(role: 'doctor'),
    const ProviderVerificationTab(role: 'nurse'),
    AdminFinancePage(onNavigateTab: _navigate),
  ];

  void _navigate(int idx) => setState(() => _selectedIndex = idx);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      body: Row(
        children: [
          _AdminSidebar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _navigate,
            collapsed: _isSidebarCollapsed,
            onToggleCollapse: _toggleSidebar,
          ),
          Expanded(
            child: Column(
              children: [
                _AdminTopBar(
                  selectedIndex: _selectedIndex,
                  onNavigateTab: _navigate,
                ),
                Expanded(child: _tabs[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Sidebar
// ============================================================================

class _AdminSidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return 'Medical Admin';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.nurse:
        return 'Nurse';
      case UserRole.patient:
        return 'Patient';
      case null:
        return 'Admin';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(requestCountsProvider);
    final bookingReviewCount = ref.watch(bookingReviewCountProvider);
    final rxQueueCount = ref.watch(adminPrescriptionQueueProvider).maybeWhen(
          data: (scripts) => scripts.length,
          orElse: () => 0,
        );
    final kpiAsync = ref.watch(dashboardTelemetryProvider);
    final user = ref.watch(currentUserProvider);
    final activeServicesCount = kpiAsync.maybeWhen(
      data: (kpi) => kpi.activeServices,
      orElse: () => 0,
    );
    final cashOutstandingCount = ref.watch(cashInHandProvider).maybeWhen(
          data: (s) => s.outstandingProvidersCount,
          orElse: () => 0,
        );
    final pendingPayoutCount = ref.watch(payoutRequestsProvider).maybeWhen(
          data: (q) => q.pendingCount,
          orElse: () => 0,
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      width: collapsed ? 70 : 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: MtColors.line)),
      ),
      child: Column(
        children: [
          // ── Logo + collapse toggle ───────────────────────────────────
          Padding(
            padding: collapsed
                ? const EdgeInsets.fromLTRB(0, 24, 0, 20)
                : const EdgeInsets.fromLTRB(20, 28, 10, 24),
            child: collapsed
                ? Column(
                    children: [
                      _LogoMark(),
                      const SizedBox(height: 14),
                      _CollapseButton(
                        collapsed: true,
                        onTap: onToggleCollapse,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _LogoMark(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Taafi', style: MtTextStyles.h3),
                            Text(
                              'OPS CONSOLE',
                              style: MtTextStyles.labelSm.copyWith(
                                color: MtColors.ink3,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _CollapseButton(
                        collapsed: false,
                        onTap: onToggleCollapse,
                      ),
                    ],
                  ),
          ),

          // ── Navigation (grouped into four operational sections) ───────
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 16),
              children: [
                _SidebarSection(
                  title: 'Operations Control',
                  collapsed: collapsed,
                  children: [
                    _SidebarItem(
                      icon: Icons.grid_view,
                      label: 'Overview',
                      selected: selectedIndex == 0,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(0),
                    ),
                    _SidebarItem(
                      icon: Icons.account_tree_outlined,
                      label: 'Booking pipeline',
                      selected: selectedIndex == 13,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(13),
                    ),
                    _SidebarItem(
                      icon: Icons.show_chart,
                      label: 'Live monitor',
                      badgeCount: activeServicesCount == 0
                          ? null
                          : activeServicesCount,
                      selected: selectedIndex == 3,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(3),
                    ),
                    _SidebarItem(
                      icon: Icons.list_alt,
                      label: 'Review queue',
                      badgeCount:
                          counts['pending'] == 0 ? null : counts['pending'],
                      selected: selectedIndex == 1,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(1),
                    ),
                    _SidebarItem(
                      icon: Icons.request_quote_outlined,
                      label: 'Booking review',
                      badgeCount: bookingReviewCount == 0
                          ? null
                          : bookingReviewCount,
                      selected: selectedIndex == 10,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(10),
                    ),
                    _SidebarItem(
                      icon: Icons.people_outline,
                      label: 'Assign team',
                      selected: selectedIndex == 2,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(2),
                    ),
                    _SidebarItem(
                      icon: Icons.medication_outlined,
                      label: 'Rx approvals',
                      badgeCount: rxQueueCount == 0 ? null : rxQueueCount,
                      selected: selectedIndex == 12,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(12),
                    ),
                  ],
                ),
                _SidebarSection(
                  title: 'People & Verification',
                  collapsed: collapsed,
                  children: [
                    _SidebarItem(
                      icon: Icons.medical_information_outlined,
                      label: 'Doctor verification',
                      selected: selectedIndex == 15,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(15),
                    ),
                    _SidebarItem(
                      icon: Icons.vaccines_outlined,
                      label: 'Nurse verification',
                      selected: selectedIndex == 16,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(16),
                    ),
                    _SidebarItem(
                      icon: Icons.local_hospital_outlined,
                      label: 'Providers',
                      selected: selectedIndex == 5,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(5),
                    ),
                    _SidebarItem(
                      icon: Icons.favorite_border,
                      label: 'Patients',
                      selected: selectedIndex == 6,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(6),
                    ),
                  ],
                ),
                _SidebarSection(
                  title: 'Finance & Ledger',
                  collapsed: collapsed,
                  children: [
                    _SidebarItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Billing',
                      selected: selectedIndex == 7,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(7),
                    ),
                    _SidebarItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Cash clearance',
                      badgeCount: cashOutstandingCount == 0
                          ? null
                          : cashOutstandingCount,
                      selected: selectedIndex == 14,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(14),
                    ),
                    _SidebarItem(
                      icon: Icons.payments_outlined,
                      label: 'Provider payouts',
                      badgeCount:
                          pendingPayoutCount == 0 ? null : pendingPayoutCount,
                      selected: selectedIndex == 17,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(17),
                    ),
                  ],
                ),
                _SidebarSection(
                  title: 'CMS & System',
                  collapsed: collapsed,
                  children: [
                    _SidebarItem(
                      icon: Icons.medical_services_outlined,
                      label: 'Manage services',
                      selected: selectedIndex == 4,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(4),
                    ),
                    _SidebarItem(
                      icon: Icons.view_carousel_rounded,
                      label: 'Banners',
                      selected: selectedIndex == 9,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(9),
                    ),
                    _SidebarItem(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Home sections',
                      selected: selectedIndex == 11,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(11),
                    ),
                    _SidebarItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      selected: selectedIndex == 8,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(8),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Bottom user profile + sign out menu ──────────────────────
          _SidebarUserRow(
            user: user,
            roleLabel: _roleLabel(user?.role),
            collapsed: collapsed,
          ),
        ],
      ),
    );
  }
}

/// The orange "+" app mark, shared by both sidebar states.
class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MtColors.brand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
}

/// Collapse / expand control at the top of the rail.
class _CollapseButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onTap;
  const _CollapseButton({required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            collapsed ? Icons.menu : Icons.menu_open,
            size: 20,
            color: MtColors.ink3,
          ),
        ),
      ),
    );
  }
}

/// A collapsible sidebar group. In the full rail it renders a tappable
/// header (with a chevron) above its items and remembers its own expand
/// state; in the icon-only rail the header is hidden and the items render
/// directly with a subtle divider so groups stay visually distinct.
class _SidebarSection extends StatefulWidget {
  final String title;
  final bool collapsed;
  final List<Widget> children;
  const _SidebarSection({
    required this.title,
    required this.collapsed,
    required this.children,
  });

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      // Icon-only rail: no header, items always visible, thin separator.
      return Column(
        children: [
          const SizedBox(height: 6),
          ...widget.children,
          const Divider(height: 14, thickness: 1, color: MtColors.line),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.keyboard_arrow_down,
                      size: 18, color: MtColors.ink3),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Column(children: widget.children),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badgeCount;
  final bool collapsed;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.collapsed,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    // Collapsed: icon-only, centred, with a tooltip carrying the full label
    // (and the badge count when present) so nav stays discoverable.
    if (collapsed) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message:
              badgeCount != null ? '$label · $badgeCount' : label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: selected ? MtColors.brandSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? MtColors.brand : MtColors.ink2,
                  ),
                  if (badgeCount != null)
                    Positioned(
                      top: 6,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: selected ? MtColors.brand : MtColors.ink,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 6,
                          minHeight: 6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? MtColors.brandSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (selected)
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: MtColors.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(width: 11),
              Icon(
                icon,
                size: 20,
                color: selected ? MtColors.brand : MtColors.ink2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd.copyWith(
                    color: selected ? MtColors.brand : MtColors.ink,
                  ),
                ),
              ),
              if (badgeCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? MtColors.brand : MtColors.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: MtTextStyles.labelSm.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarUserRow extends ConsumerWidget {
  final User? user;
  final String roleLabel;
  final bool collapsed;

  const _SidebarUserRow({
    required this.user,
    required this.roleLabel,
    required this.collapsed,
  });

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Sign out of the admin console?',
            style: MtTextStyles.h3),
        content: Text(
          "You'll need to sign in again to access requests and team assignments.",
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: Text('Sign out', style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = user?.name ?? 'Admin';
    final shortName = displayName.length > 22
        ? '${displayName.substring(0, 20)}…'
        : displayName;

    return Padding(
      padding: collapsed
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 16)
          : const EdgeInsets.all(20),
      child: PopupMenuButton<String>(
        tooltip: collapsed ? '$displayName · $roleLabel' : 'Account',
        position: PopupMenuPosition.over,
        offset: const Offset(0, -8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onSelected: (value) {
          if (value == 'signout') _confirmSignOut(context, ref);
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'signout',
            child: Row(
              children: [
                const Icon(Icons.logout,
                    size: 18, color: MtColors.rejected),
                const SizedBox(width: 10),
                Text(
                  'Sign out',
                  style:
                      MtTextStyles.labelMd.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ),
        ],
        child: collapsed
            ? Center(
                child: InitialsAvatar(
                  name: displayName,
                  size: 36,
                  backgroundColor: MtColors.ink,
                  textColor: Colors.white,
                ),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: displayName,
                      size: 36,
                      backgroundColor: MtColors.ink,
                      textColor: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shortName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MtTextStyles.labelMd,
                          ),
                          Text(
                            roleLabel,
                            style: MtTextStyles.bodySm.copyWith(
                              color: MtColors.ink3,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_up,
                        color: MtColors.ink3, size: 20),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================================
// Top bar
// ============================================================================

class _AdminTopBar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onNavigateTab;

  const _AdminTopBar({
    required this.selectedIndex,
    required this.onNavigateTab,
  });

  @override
  ConsumerState<_AdminTopBar> createState() => _AdminTopBarState();
}

class _AdminTopBarState extends ConsumerState<_AdminTopBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getTabTitle() {
    switch (widget.selectedIndex) {
      case 0:
        return 'Overview';
      case 1:
        return 'Review queue';
      case 2:
        return 'Assign team';
      case 3:
        return 'Live monitor';
      case 4:
        return 'Manage services';
      case 5:
        return 'Providers';
      case 6:
        return 'Patients';
      case 7:
        return 'Billing';
      case 8:
        return 'Settings';
      case 9:
        return 'Promo banners';
      case 10:
        return 'Booking review';
      case 11:
        return 'Home sections';
      case 12:
        return 'Rx approvals';
      case 13:
        return 'Live booking pipeline';
      case 14:
        return 'Provider cash clearance';
      case 15:
        return 'Doctor verification';
      case 16:
        return 'Nurse verification';
      case 17:
        return 'Provider payouts';
      default:
        return 'Dashboard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MtColors.line)),
      ),
      child: Row(
        children: [
          Text(_getTabTitle(), style: MtTextStyles.h2),
          const SizedBox(width: 24),
          // Fluid search: fills the gap between the title and the bell but
          // caps at 320px and right-aligns on wide viewports. On compact
          // windows the Expanded → ConstrainedBox simply shrinks the field
          // instead of pushing it past the screen edge (the overflow bug).
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(
                  height: 40,
                  child: MtSearchField(
                    dense: true,
                    controller: _searchController,
                    hintText: 'Search patients, doctors, requests...',
                    onSubmitted: (val) {
                      if (val.isEmpty) return;
                      ref.read(requestFilterProvider.notifier).state = ref
                          .read(requestFilterProvider)
                          .copyWith(searchQuery: val);
                      widget.onNavigateTab(1);
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Unified multi-role notification bell. Same widget the
          // patient + doctor headers use — the badge is pinned at
          // top-right and self-hides when unread == 0.
          const ConversationInboxButton(framed: false),
          const NotificationBell(framed: false),
        ],
      ),
    );
  }
}

