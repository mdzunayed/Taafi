import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_models.dart';
import '../../../core/models/service.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../admin_providers.dart';

/// Right-aligned 420-wide sheet exposing the advanced filters that don't fit
/// on the top filter bar: Service type, Area, and Urgency level.
///
/// Bound directly to [requestFilterProvider] so changes are reflected in the
/// table live — admins don't need to press Apply to see the effect.
class MoreFiltersSheet extends ConsumerWidget {
  const MoreFiltersSheet({super.key});

  static const _serviceTypes = <(ServiceType?, String)>[
    (null, 'Any'),
    (ServiceType.postSurgery, 'Post-surgery'),
    (ServiceType.woundDressing, 'Wound dressing'),
    (ServiceType.vitalsCheck, 'Vitals check'),
    (ServiceType.elderlyCare, 'Elderly care'),
  ];

  static const _urgencyOptions = <(UrgencyLevel, String, Color)>[
    (UrgencyLevel.low, 'Low', Color(0xFF059669)),
    (UrgencyLevel.medium, 'Medium', MtColors.brand),
    (UrgencyLevel.high, 'High', Color(0xFFD97706)),
    (UrgencyLevel.critical, 'Critical', MtColors.rejected),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(requestFilterProvider);
    final areas = ref.watch(distinctAreasProvider);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 420,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: MtColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('More filters', style: MtTextStyles.h2),
                        Text(
                          'Narrow the queue by service, area, or urgency',
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SERVICE TYPE',
                        style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _serviceTypes)
                          _ChipSelector(
                            label: entry.$2,
                            selected: filter.serviceTypeFilter == entry.$1,
                            onSelected: () {
                              ref
                                  .read(requestFilterProvider.notifier)
                                  .state = filter.copyWith(
                                serviceTypeFilter: () => entry.$1,
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    Text('AREA', style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: MtColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: MtColors.line),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: filter.areaFilter,
                          hint: Text(
                            areas.isEmpty
                                ? 'No areas loaded yet'
                                : 'Any area',
                            style: MtTextStyles.bodyMd
                                .copyWith(color: MtColors.ink3),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Any area'),
                            ),
                            for (final area in areas)
                              DropdownMenuItem<String?>(
                                value: area,
                                child: Text(area),
                              ),
                          ],
                          onChanged: areas.isEmpty
                              ? null
                              : (v) {
                                  ref
                                      .read(requestFilterProvider.notifier)
                                      .state = filter.copyWith(
                                    areaFilter: () => v,
                                  );
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    Text('URGENCY LEVEL',
                        style: MtTextStyles.sectionLabel),
                    const SizedBox(height: 4),
                    Text(
                      'Pick one or more — leave empty to include all.',
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink3),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final opt in _urgencyOptions)
                          _UrgencyChip(
                            label: opt.$2,
                            color: opt.$3,
                            selected:
                                filter.urgencyLevels.contains(opt.$1),
                            onTap: () {
                              final next = {...filter.urgencyLevels};
                              if (!next.add(opt.$1)) next.remove(opt.$1);
                              ref
                                  .read(requestFilterProvider.notifier)
                                  .state = filter.copyWith(
                                urgencyLevels: next,
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: MtColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(requestFilterProvider.notifier).state =
                            const RequestFilter();
                      },
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Reset all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MtColors.brand,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMoreFiltersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const MoreFiltersSheet(),
  );
}

class _ChipSelector extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _ChipSelector({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? MtColors.ink : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? MtColors.ink : MtColors.line,
            ),
          ),
          child: Text(
            label,
            style: MtTextStyles.labelMd.copyWith(
              color: selected ? Colors.white : MtColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _UrgencyChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _UrgencyChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : MtColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(
                  color: selected ? color : MtColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
