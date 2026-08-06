import 'package:flutter/material.dart';

import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';

/// One pill in a [HubTabBar].
class HubTab<T> {
  final T value;
  final String label;
  final IconData icon;

  /// Badge number. `null` or `0` renders no badge, so a drained queue stops
  /// nagging instead of showing a zero.
  final int? count;

  const HubTab({
    required this.value,
    required this.label,
    required this.icon,
    this.count,
  });
}

/// Horizontal pill strip used by every consolidated admin hub.
///
/// The hubs replaced a sidebar where each of these pills was its own
/// destination, so the strip has to carry the same at-a-glance queue depth
/// the sidebar badges did — hence [HubTab.count] rather than a bare label.
class HubTabBar<T> extends StatelessWidget {
  final List<HubTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  const HubTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MtColors.line)),
      ),
      // The four-pill strips fit a laptop viewport, but the CMS hub's
      // longer labels do not — scroll sideways rather than overflow.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in tabs) ...[
              _HubPill(
                label: tab.label,
                icon: tab.icon,
                count: tab.count,
                selected: tab.value == selected,
                onTap: () => onSelect(tab.value),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _HubPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _HubPill({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = count != null && count! > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? MtColors.brand : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MtColors.brand : MtColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : MtColors.ink3,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: MtTextStyles.labelMd.copyWith(
                color: selected ? Colors.white : MtColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showBadge) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: MtTextStyles.labelSm.copyWith(
                    color: selected ? Colors.white : MtColors.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A hub: pill strip pinned at the top, the selected tab's body filling the
/// rest. Bodies keep their own scrolling (most are an `AdminListScaffold`),
/// so the strip stays put while the content moves.
class HubScaffold<T> extends StatelessWidget {
  final List<HubTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onSelect;
  final Widget body;

  const HubScaffold({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubTabBar<T>(tabs: tabs, selected: selected, onSelect: onSelect),
        Expanded(child: body),
      ],
    );
  }
}
