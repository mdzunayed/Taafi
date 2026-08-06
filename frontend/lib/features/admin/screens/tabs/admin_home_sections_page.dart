import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/home_section_providers.dart';
import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/models/home_service_card.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_toast.dart';
// The live preview renders the patient app's real layout engine, so the CMS
// can never drift from what ships.
import '../../../patient/screens/widgets/care_services_section.dart';
import '../../widgets/home_pill_preview.dart';

/// Prefers the backend's own message (e.g. "sectionKey already exists" on a
/// 409) before falling back to the shared status-code copy.
(String, String) _mapSectionError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return ('Could not save section', data['message'] as String);
    }
  }
  return mapBannerError(error);
}

/// The Care Services layout picker, and nothing else.
///
/// This page has exactly one job: choose how the Care Services block arranges
/// its cards on the patient Home. The dynamic-section CRUD that used to sit
/// underneath it moved to [AdminDynamicSectionsPage] — it manages a different
/// feature (the server-driven rows *below* Care Services), and pairing the two
/// meant every operator who came here to flip a layout had to scroll past a
/// reorderable table they hadn't asked for.
class AdminHomeSectionsPage extends StatelessWidget {
  const AdminHomeSectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [CareServicesLayoutCard()],
      ),
    );
  }
}

// --- Care Services layout switcher ------------------------------------------

/// Picks how the Care Services block arranges its cards on the patient Home,
/// with an interactive preview that repaints the instant a layout is selected.
///
/// The preview is the patient app's real [LayoutEngine] — the same widget that
/// ships — fed real catalog services and rendered at phone width inside a dark
/// frame. That last part matters: the engine reflows a carousel into a grid
/// above 700px, so previewing it at the admin console's own window width would
/// show a layout the phone never renders. The [MediaQuery] override below pins
/// it to 360px so the preview answers the question actually being asked.
///
/// Care Services predates the CMS, so most deployments have no `CARE_SERVICES`
/// document. Selecting a layout upserts one — see
/// [HomeSectionRepository.setCareServicesLayout] — rather than requiring the
/// operator to hand-create a section with a magic key first.
class CareServicesLayoutCard extends ConsumerStatefulWidget {
  const CareServicesLayoutCard({super.key});

  @override
  ConsumerState<CareServicesLayoutCard> createState() =>
      _CareServicesLayoutCardState();
}

class _CareServicesLayoutCardState
    extends ConsumerState<CareServicesLayoutCard> {
  /// The layout the preview is showing. Set optimistically on tap so the
  /// preview is instant, and rolled back if the save fails.
  HomeLayoutType? _pending;
  bool _saving = false;

  /// Phone width the preview is pinned to. Below the engine's 700px
  /// carousel→grid breakpoint, and close to the devices this actually ships to.
  static const double _previewWidth = 360;

  HomeSection? _careSection(List<HomeSection> sections) {
    for (final s in sections) {
      if (s.isCareServices) return s;
    }
    return null;
  }

  Future<void> _select(HomeLayoutType layout) async {
    if (_saving) return;
    final previous = _pending;
    setState(() {
      _pending = layout;
      _saving = true;
    });
    try {
      await ref
          .read(homeSectionRepositoryProvider)
          .setCareServicesLayout(layout);
      if (!mounted) return;
      setState(() => _saving = false);
      MtToast.success(context, 'Care Services layout updated');
    } catch (e) {
      if (!mounted) return;
      // Roll back to what the server still holds, so the preview never claims
      // a layout the app isn't rendering.
      setState(() {
        _pending = previous;
        _saving = false;
      });
      final (title, message) = _mapSectionError(e);
      MtToast.error(context, title, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(allHomeSectionsProvider);
    final section = sectionsAsync.maybeWhen(
      data: _careSection,
      orElse: () => null,
    );
    final selected = _pending ?? section?.layoutType ?? HomeLayoutType.carousel;

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
            children: [
              const Icon(Icons.dashboard_outlined,
                  size: 20, color: MtColors.brand),
              const SizedBox(width: 10),
              Text('Care Services layout', style: MtTextStyles.h3),
              const SizedBox(width: 10),
              if (_saving)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'How the Care Services block arranges its cards on the app home. '
            'Applies immediately — patients see it on their next refresh.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              // Side by side on a roomy console; the options stack above the
              // preview once the two columns would squeeze the phone frame.
              final stacked = constraints.maxWidth < 900;
              final options = _LayoutOptions(
                selected: selected,
                onSelect: _select,
              );
              final preview = _LayoutPreview(
                layoutType: selected,
                width: _previewWidth,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    options,
                    const SizedBox(height: 20),
                    Center(child: preview),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: options),
                  const SizedBox(width: 28),
                  preview,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The three selectable layout formats.
class _LayoutOptions extends StatelessWidget {
  final HomeLayoutType selected;
  final ValueChanged<HomeLayoutType> onSelect;

  const _LayoutOptions({required this.selected, required this.onSelect});

  static const Map<HomeLayoutType, IconData> _icons = {
    HomeLayoutType.grid2Col: Icons.grid_view_rounded,
    HomeLayoutType.carousel: Icons.view_carousel_rounded,
    HomeLayoutType.list: Icons.view_list_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final layout in HomeLayoutType.values) ...[
          if (layout != HomeLayoutType.values.first) const SizedBox(height: 10),
          _LayoutOptionTile(
            icon: _icons[layout]!,
            label: layout.label,
            description: layout.description,
            // The stored value, shown so an operator debugging the API sees
            // the same token the payload carries.
            wire: layout.wire,
            selected: layout == selected,
            onTap: () => onSelect(layout),
          ),
        ],
      ],
    );
  }
}

class _LayoutOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final String wire;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutOptionTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.wire,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $description',
      child: Material(
        color: selected ? MtColors.brandSofter : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? MtColors.brand : MtColors.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? MtColors.brand : MtColors.bg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Colors.white : MtColors.ink2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MtTextStyles.labelLg.copyWith(
                                color: selected ? MtColors.brand700 : MtColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            wire,
                            style: MtTextStyles.labelSm.copyWith(
                              color: MtColors.ink3,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style:
                            MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? MtColors.brand : MtColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone-framed live preview.
class _LayoutPreview extends ConsumerWidget {
  final HomeLayoutType layoutType;
  final double width;

  const _LayoutPreview({required this.layoutType, required this.width});

  /// Stand-ins for an empty catalog, so the preview still shows the geometry
  /// of each layout on a fresh install. Clearly labelled as samples by the
  /// caption below the frame.
  static const List<HomeServiceCard> _samples = [
    HomeServiceCard(
      itemId: 'sample-1',
      titleEn: 'Doctor home visit',
      subtitleEn: 'General consultation by a licensed doctor at your home.',
      price: 1500,
      badgeText: 'Doctor in Home',
    ),
    HomeServiceCard(
      itemId: 'sample-2',
      titleEn: 'Post-op wound care',
      subtitleEn: 'Dressing changes and recovery checks by a nurse.',
      price: 900,
      badgeText: 'Post-op',
    ),
    HomeServiceCard(
      itemId: 'sample-3',
      titleEn: 'Nursing attendant',
      subtitleEn: 'Day or night bedside care at home.',
      price: 2400,
      badgeText: 'Nursing',
    ),
    HomeServiceCard(
      itemId: 'sample-4',
      titleEn: 'Lab sample collection',
      subtitleEn: 'A technician collects samples at your door.',
      price: 400,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real catalog services when there are any, so the preview shows the
    // operator's own titles, prices, and photos rather than invented ones.
    final catalog = ref.watch(activeServicesProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <ServiceCatalogItem>[],
        );
    final usingSamples = catalog.isEmpty;
    final cards = usingSamples
        ? _samples
        : [
            for (final item in catalog.take(4)) HomeServiceCard.fromCatalog(item),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.smartphone, size: 14, color: MtColors.ink3),
            const SizedBox(width: 6),
            Text('Preview on patient Home',
                style: MtTextStyles.labelMd.copyWith(color: MtColors.ink3)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            // Approximates the Home canvas, so the cards are judged against
            // the background they will actually sit on.
            color: HomePillPreview.canvas,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MtColors.line),
          ),
          child: Theme(
            data: ThemeData(brightness: Brightness.dark),
            // Pins the engine to a phone viewport — without this it reads the
            // admin console's width and reflows the carousel into a grid,
            // previewing a layout the phone never shows.
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(width, 720),
                textScaler: TextScaler.noScaling,
              ),
              child: LayoutEngine(
                layoutType: layoutType,
                cards: cards,
                // Preview only: taps are swallowed rather than dispatched.
                onTap: (_) {},
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: width,
          child: Text(
            usingSamples
                ? 'Sample cards — add services to preview your own.'
                : 'Showing your ${cards.length} most recent service'
                    '${cards.length == 1 ? '' : 's'}.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ),
      ],
    );
  }
}