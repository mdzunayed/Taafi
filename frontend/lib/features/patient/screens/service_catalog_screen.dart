import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/service_catalog_providers.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';

final _priceFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_priceFmt.format(n.round())}';

/// Patient-facing medical catalog. Browses the live `activeServicesProvider`
/// stream with a shimmer skeleton that maps 1:1 to the final card layout, so
/// there is zero structural layout shift when the data lands. Tapping a card
/// prefills the New Request flow and deep-links the patient straight into it.
///
/// [initialCategory] pre-filters the list to one `Service.category` value —
/// used by [BannerActionType.category] promo-banner taps and by the category
/// filter chips below, both landing here with the same in-screen filter
/// rather than a separate category screen (services have no category
/// collection of their own; see `_CategoryTargetPicker` in the admin editor).
class ServiceCatalogScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const ServiceCatalogScreen({super.key, this.initialCategory});

  @override
  ConsumerState<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends ConsumerState<ServiceCatalogScreen> {
  String? _category;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory?.trim();
    _category = (initial != null && initial.isNotEmpty) ? initial : null;
  }

  void _openService(BuildContext context, WidgetRef ref, ServiceCatalogItem s) {
    HapticFeedback.lightImpact();
    ref.read(newRequestProvider.notifier).applyServicePrefill(s, fromLink: true);
    ref.goToNewRequest();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeServicesProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Browse Services',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
      ),
      body: async.when(
        loading: () => const _CatalogSkeletonList(),
        error: (e, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MtErrorState(
            title: "Couldn't load services",
            message: e.toString(),
            onRetry: () => ref.read(serviceCatalogRepositoryProvider).refresh(),
          ),
        ),
        data: (services) {
          if (services.isEmpty) {
            return const _CatalogEmpty();
          }

          final categories = <String>{
            for (final s in services)
              if (s.category.trim().isNotEmpty) s.category.trim(),
          }.toList()
            ..sort();

          final filtered = _category == null
              ? services
              : services.where((s) => s.category.trim() == _category).toList();

          return Column(
            children: [
              if (categories.isNotEmpty)
                _CategoryFilterBar(
                  categories: categories,
                  selected: _category,
                  onSelected: (c) => setState(() => _category = c),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? _CatalogEmpty(
                        category: _category,
                        onClearFilter: () => setState(() => _category = null),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _CatalogCard(
                          service: filtered[i],
                          onTap: () => _openService(context, ref, filtered[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Horizontal scrolling row of category chips — "All" plus every distinct
/// `Service.category` currently in the live catalog. Lets a patient who
/// landed here via a [BannerActionType.category] deep link switch to a
/// different category or clear the filter without leaving the screen.
class _CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryFilterBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          _FilterChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final c in categories) ...[
            _FilterChip(
              label: c,
              selected: selected == c,
              onTap: () => onSelected(c),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MtColors.brandSoft,
      labelStyle: MtTextStyles.labelSm.copyWith(
        color: selected ? MtColors.brand700 : MtColors.ink2,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: MtColors.surface2,
      side: BorderSide(color: selected ? MtColors.brand : MtColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

// ─── Live card ───────────────────────────────────────────────────────────────

class _CatalogCard extends StatelessWidget {
  final ServiceCatalogItem service;
  final VoidCallback onTap;
  const _CatalogCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MtColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: MtColors.brandSofter,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.medical_services_outlined,
                        color: MtColors.brand, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (service.category.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: MtColors.brandSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              service.category.toUpperCase(),
                              style: MtTextStyles.labelSm.copyWith(
                                  color: MtColors.brand, fontSize: 10),
                            ),
                          ),
                        if (service.category.isNotEmpty)
                          const SizedBox(height: 6),
                        Text(
                          service.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MtTextStyles.labelLg.copyWith(
                              color: MtColors.ink,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (service.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  service.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.bodySm
                      .copyWith(color: MtColors.ink3, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_money(service.price)} / Visit',
                      style: MtTextStyles.labelMd.copyWith(
                          color: const Color(0xFF059669),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  if (service.duration != null &&
                      service.duration!.trim().isNotEmpty) ...[
                    const Icon(Icons.schedule,
                        size: 15, color: MtColors.ink3),
                    const SizedBox(width: 4),
                    Text(service.duration!,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3)),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right, color: MtColors.ink3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shimmer skeleton (mirrors _CatalogCard geometry exactly) ────────────────

class _CatalogSkeletonList extends StatelessWidget {
  const _CatalogSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ShimmerLoadingPlaceholder(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const _CatalogCardSkeleton(),
      ),
    );
  }
}

class _CatalogCardSkeleton extends StatelessWidget {
  const _CatalogCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(
                  width: 52,
                  height: 52,
                  borderRadius: BorderRadius.all(Radius.circular(14))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox.line(width: 70, height: 14),
                    const SizedBox(height: 8),
                    ShimmerBox.line(width: 160, height: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ShimmerBox.line(width: double.infinity, height: 12),
          const SizedBox(height: 6),
          ShimmerBox.line(width: 220, height: 12),
          const SizedBox(height: 14),
          Row(
            children: [
              const ShimmerBox(
                  width: 110,
                  height: 30,
                  borderRadius: BorderRadius.all(Radius.circular(8))),
              const Spacer(),
              ShimmerBox.line(width: 50, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogEmpty extends StatelessWidget {
  /// Non-null when this is "no services in this category" (filtered empty)
  /// rather than "the whole catalog is empty" — swaps in a clear-filter CTA.
  final String? category;
  final VoidCallback? onClearFilter;

  const _CatalogEmpty({this.category, this.onClearFilter});

  @override
  Widget build(BuildContext context) {
    final isFiltered = category != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 44, color: MtColors.ink3.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              isFiltered ? 'No services in "$category" yet' : 'No services available yet',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              isFiltered
                  ? 'Try another category, or clear the filter to see everything.'
                  : 'Please check back shortly — our catalog is being updated.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
            if (isFiltered && onClearFilter != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onClearFilter,
                child: const Text('Clear filter'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
