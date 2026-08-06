import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/models/service.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_search_field.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_nav.dart';
import '../../admin_providers.dart';
import '../../widgets/more_filters_sheet.dart';
import '../../widgets/triage_slide_over.dart';
import 'admin_table_chrome.dart';

/// The full care-request table — the "All bookings" tab of the Bookings hub.
///
/// Carries the status chips and the bulk approve/reject toolbar that used to
/// be their own sidebar destination. Hand-offs to the dispatch workspace now
/// switch the hub's tab instead of navigating, so the admin keeps their place.
class ReviewQueueTab extends ConsumerStatefulWidget {
  const ReviewQueueTab({super.key});

  @override
  ConsumerState<ReviewQueueTab> createState() => _ReviewQueueTabState();
}

class _ReviewQueueTabState extends ConsumerState<ReviewQueueTab> {
  final _searchController = TextEditingController();

  /// Move to the dispatch workspace within the Bookings hub.
  void _goToAssignment() =>
      ref.read(bookingsTabProvider.notifier).state = BookingsTab.assignment;

  @override
  void initState() {
    super.initState();
    // Pre-fill search if it exists in the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final q = ref.read(requestFilterProvider).searchQuery;
      if (q.isNotEmpty) {
        _searchController.text = q;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    ref.read(requestFilterProvider.notifier).state =
        ref.read(requestFilterProvider).copyWith(searchQuery: val);
  }

  /// Chips are mutually exclusive, so every one of them clears the other two
  /// status dimensions rather than layering on top of whatever was set.
  void _setFilter(
    String? statusFilter, {
    bool urgencyOnly = false,
    Set<String> statusAnyOf = const {},
  }) {
    ref.read(requestFilterProvider.notifier).state =
        ref.read(requestFilterProvider).copyWith(
              statusFilter: () => statusFilter,
              urgencyOnly: urgencyOnly,
              statusAnyOf: statusAnyOf,
            );
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(adminRequestsProvider);
    final counts = ref.watch(requestCountsProvider);
    final filteredRequests = ref.watch(filteredRequestsProvider);
    final filter = ref.watch(requestFilterProvider);
    final selectedIds = ref.watch(selectedRequestIdsProvider);

    final isAllSelected = filteredRequests.isNotEmpty &&
        selectedIds.length == filteredRequests.length;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Filter Bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              color: MtColors.bg,
              child: Row(
                children: [
                  // Search
                  SizedBox(
                    width: 250,
                    height: 40,
                    child: MtSearchField(
                      dense: true,
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      hintText: 'Search ID, patient, area...',
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Chips — the five of them plus the search field and the
                  // "More filters" button are wider than a laptop viewport,
                  // so the chip strip takes the slack and scrolls sideways
                  // instead of overflowing the bar.
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FilterChip(
                            label: 'All',
                            count: counts['all'] ?? 0,
                            selected: filter.statusFilter == null &&
                                !filter.urgencyOnly &&
                                filter.statusAnyOf.isEmpty,
                            onTap: () => _setFilter(null),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Pending',
                            count: counts['pending'] ?? 0,
                            selected: filter.statusFilter == 'pending' &&
                                !filter.urgencyOnly,
                            onTap: () => _setFilter('pending'),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Urgent',
                            count: counts['urgent'] ?? 0,
                            selected: filter.urgencyOnly,
                            onTap: () => _setFilter(null, urgencyOnly: true),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            // 'approved' now means "needs (re-)assignment" — a
                            // doctor declined or a legacy payment landed.
                            label: 'Awaiting assignment',
                            count: counts['approved'] ?? 0,
                            selected: filter.statusFilter == 'approved',
                            onTap: () => _setFilter('approved'),
                          ),
                          const SizedBox(width: 8),
                          // Carried over from the retired Booking-pipeline
                          // board, whose "payment" stage was the only view
                          // of these two states. Spans both because no
                          // single status covers the stage.
                          _FilterChip(
                            label: 'Awaiting payment',
                            count: counts['awaitingPayment'] ?? 0,
                            selected: filter.statusAnyOf.isNotEmpty,
                            onTap: () => _setFilter(
                              null,
                              statusAnyOf: kAwaitingPaymentStatuses,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Rejected',
                            count: counts['rejected'] ?? 0,
                            selected: filter.statusFilter == 'rejected',
                            onTap: () => _setFilter('rejected'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => showMoreFiltersSheet(context),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text('More filters', style: MtTextStyles.labelMd),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MtColors.ink,
                      side: const BorderSide(color: MtColors.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Active-filter chip strip ───────────────────────────────────
            if (filter.hasAdvancedFilters)
              _ActiveFilterChips(filter: filter),

            // ─── Table Area ──────────────────────────────────────────────────
            Expanded(
              child: Container(
                color: Colors.white,
                child: requestsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: MtErrorState(
                        message: e.toString(),
                        onRetry: () => ref
                            .read(adminRequestsProvider.notifier)
                            .fetchRequests(),
                      ),
                    ),
                  ),
                  data: (_) {
                    if (filteredRequests.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: MtEmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'No requests found',
                            subtitle:
                                'Try adjusting your filters or search query.',
                          ),
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // Auto-scrolling fallback: keep a sane minimum table
                        // width so the flex columns never crush into each
                        // other — on a narrower viewport the whole table
                        // scrolls horizontally instead of bleeding rows.
                        final tableWidth = constraints.maxWidth < 1000.0
                            ? 1000.0
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            height: constraints.maxHeight,
                            child: Column(
                      children: [
                        // Table Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isAllSelected,
                                activeColor: MtColors.brand,
                                onChanged: (val) {
                                  if (val == true) {
                                    ref
                                        .read(selectedRequestIdsProvider.notifier)
                                        .state = filteredRequests
                                        .map((e) => e.id)
                                        .toSet();
                                  } else {
                                    ref
                                        .read(selectedRequestIdsProvider.notifier)
                                        .state = {};
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
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
                                  flex: 3,
                                  child: Text('LOCATION',
                                      style: MtTextStyles.labelSm
                                          .copyWith(color: MtColors.ink3))),
                              Expanded(
                                  flex: 2,
                                  child: Text('OFFERED',
                                      style: MtTextStyles.labelSm
                                          .copyWith(color: MtColors.ink3))),
                              Expanded(
                                  flex: 4,
                                  child: Text('STATUS / TEAM',
                                      style: MtTextStyles.labelSm
                                          .copyWith(color: MtColors.ink3))),
                              Expanded(
                                  flex: 1,
                                  child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text('AGE',
                                          style: MtTextStyles.labelSm.copyWith(
                                              color: MtColors.ink3)))),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: MtColors.line),
                        
                        // Table Body
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 100), // space for floating bar
                            itemCount: filteredRequests.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: MtColors.line),
                            itemBuilder: (context, index) {
                              final req = filteredRequests[index];
                              final isSelected = selectedIds.contains(req.id);
                              return InkWell(
                                onTap: () => _showTriageSlideOver(context, req),
                                child: _TableRowWidget(
                                  request: req,
                                  isSelected: isSelected,
                                  onToggleSelect: (val) {
                                    final current = Set<String>.from(
                                        ref.read(selectedRequestIdsProvider));
                                    if (val == true) {
                                      current.add(req.id);
                                    } else {
                                      current.remove(req.id);
                                    }
                                    ref
                                        .read(selectedRequestIdsProvider.notifier)
                                        .state = current;
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        // ─── Floating Bulk Action Bar ────────────────────────────────────
        if (selectedIds.isNotEmpty)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: MtColors.ink,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${selectedIds.length}',
                        style: MtTextStyles.labelMd
                            .copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Requests selected',
                        style: MtTextStyles.bodyMd
                            .copyWith(color: Colors.white)),
                    const SizedBox(width: 32),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await _confirmBulk(
                          context: context,
                          title: 'Reject ${selectedIds.length} requests?',
                          message:
                              'Patients will be notified. Any escrowed payment will be refunded within 24 hours.',
                          confirmLabel: 'Reject all',
                          confirmColor: MtColors.rejected,
                        );
                        if (!ok || !context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(adminRequestsProvider.notifier)
                              .bulkUpdateStatus(selectedIds, 'rejected');
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Could not reject: $e'),
                              backgroundColor: MtColors.rejected,
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        ref.read(selectedRequestIdsProvider.notifier).state =
                            {};
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Reject all'),
                    ),
                    const SizedBox(width: 12),
                    // Approval IS team assignment now — there is no
                    // standalone "approve" status flip (the backend
                    // rejects it). Route the admin to Assign Team.
                    ElevatedButton(
                      onPressed: _goToAssignment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MtColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Assign team to approve'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showTriageSlideOver(BuildContext context, AdminCareRequest request) {
    showTriageSlideOver(
      context,
      request: request,
      onAssignTeam: () {
        Navigator.pop(context); // close slide-over
        ref.read(selectedRequestProvider.notifier).state = request;
        _goToAssignment();
      },
    );
  }

  /// Confirmation dialog for destructive/bulk operations. Returns `true` only
  /// when the admin presses the destructive primary action.
  Future<bool> _confirmBulk({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(title, style: MtTextStyles.h3),
        content: Text(
          message,
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: MtTextStyles.labelMd),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmLabel, style: MtTextStyles.labelMd),
          ),
        ],
      ),
    );
    return result == true;
  }
}

// ============================================================================
// Active-filter chip strip
// ============================================================================

class _ActiveFilterChips extends ConsumerWidget {
  final RequestFilter filter;
  const _ActiveFilterChips({required this.filter});

  String _serviceLabel(ServiceType type) {
    switch (type) {
      case ServiceType.postSurgery:
        return 'Post-surgery';
      case ServiceType.woundDressing:
        return 'Wound dressing';
      case ServiceType.vitalsCheck:
        return 'Vitals check';
      case ServiceType.elderlyCare:
        return 'Elderly care';
    }
  }

  String _urgencyLabel(UrgencyLevel u) {
    switch (u) {
      case UrgencyLevel.low:
        return 'Low';
      case UrgencyLevel.medium:
        return 'Medium';
      case UrgencyLevel.high:
        return 'High';
      case UrgencyLevel.critical:
        return 'Critical';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      color: MtColors.bg,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (filter.serviceTypeFilter != null)
            _DismissibleChip(
              label:
                  'Service: ${_serviceLabel(filter.serviceTypeFilter as ServiceType)}',
              onClear: () {
                ref.read(requestFilterProvider.notifier).state =
                    filter.copyWith(serviceTypeFilter: () => null);
              },
            ),
          if (filter.areaFilter != null)
            _DismissibleChip(
              label: 'Area: ${filter.areaFilter}',
              onClear: () {
                ref.read(requestFilterProvider.notifier).state =
                    filter.copyWith(areaFilter: () => null);
              },
            ),
          for (final u in filter.urgencyLevels)
            _DismissibleChip(
              label: 'Urgency: ${_urgencyLabel(u)}',
              onClear: () {
                final next = {...filter.urgencyLevels}..remove(u);
                ref.read(requestFilterProvider.notifier).state =
                    filter.copyWith(urgencyLevels: next);
              },
            ),
          TextButton.icon(
            onPressed: () {
              ref.read(requestFilterProvider.notifier).state = filter.copyWith(
                serviceTypeFilter: () => null,
                areaFilter: () => null,
                urgencyLevels: const {},
              );
            },
            icon: const Icon(Icons.refresh, size: 14),
            label: Text('Clear all', style: MtTextStyles.labelSm),
            style: TextButton.styleFrom(
              foregroundColor: MtColors.ink2,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissibleChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _DismissibleChip({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: MtTextStyles.labelSm.copyWith(color: MtColors.ink)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: MtColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MtColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? MtColors.ink : MtColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: MtTextStyles.labelMd
                  .copyWith(color: selected ? Colors.white : MtColors.ink),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? MtColors.ink2 : MtColors.bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                count.toString(),
                style: MtTextStyles.labelSm.copyWith(
                    color: selected ? Colors.white : MtColors.ink3,
                    fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableRowWidget extends StatelessWidget {
  final AdminCareRequest request;
  final bool isSelected;
  final ValueChanged<bool?> onToggleSelect;

  const _TableRowWidget({
    required this.request,
    required this.isSelected,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final ageMinutes = DateTime.now().difference(request.createdAt).inMinutes;
    final ageLabel =
        ageMinutes < 60 ? '${ageMinutes}m' : '${ageMinutes ~/ 60}h';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            activeColor: MtColors.brand,
            onChanged: onToggleSelect,
          ),
          const SizedBox(width: 8),
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
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2))),
          Expanded(
              flex: 3,
              child: Text(request.serviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2))),
          Expanded(
              flex: 3,
              child: Text(request.location,
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 2,
              child: Text('৳${request.patientOffer.toStringAsFixed(0)}',
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3))),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _StatusBadge(status: request.status),
                if (request.assignedDoctorName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      request.assignedDoctorName!,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
              flex: 1,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(ageLabel,
                      style:
                          MtTextStyles.bodyMd.copyWith(color: MtColors.ink3)))),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color sColor;
    Color sBgColor;
    String label = status.toUpperCase();

    switch (status) {
      case 'pending':
        sColor = MtColors.brand;
        sBgColor = MtColors.brandSoft;
        break;
      case 'approved':
        sColor = const Color(0xFF059669);
        sBgColor = const Color(0xFFDCF3E7);
        break;
      case 'rejected':
        sColor = MtColors.rejected;
        sBgColor = const Color(0xFFFEE2E2);
        break;
      default:
        sColor = MtColors.ink3;
        sBgColor = MtColors.line;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: sBgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: sColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: MtTextStyles.labelSm
                  .copyWith(color: sColor, fontSize: 9, height: 1.1)),
        ],
      ),
    );
  }
}
