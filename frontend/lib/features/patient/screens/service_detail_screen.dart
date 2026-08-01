import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/service_catalog_item.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../new_request/new_request_notifier.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

class ServiceDetailScreen extends ConsumerWidget {
  final ServiceCatalogItem item;

  const ServiceDetailScreen({super.key, required this.item});

  void _book(BuildContext context, WidgetRef ref) {
    ref.read(newRequestProvider.notifier).applyServicePrefill(item, fromLink: true);
    // Return true so the home tab can switch to "New Request" from a context
    // that still has access to the DefaultTabController.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: 'Service details', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _HeroImage(url: item.imageUrl),
                  const SizedBox(height: 16),
                  Text(item.title, style: MtTextStyles.h2),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(
                        label: 'From ${_money(item.price)}',
                        color: MtColors.brand,
                        background: MtColors.brandSoft,
                      ),
                      if (item.category.isNotEmpty)
                        _Chip(
                          label: item.category,
                          color: MtColors.ink2,
                          background: MtColors.surface2,
                        ),
                      if (item.duration != null && item.duration!.isNotEmpty)
                        _Chip(
                          label: item.duration!,
                          icon: Icons.schedule,
                          color: MtColors.ink2,
                          background: MtColors.surface2,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (item.description.isNotEmpty) ...[
                    Text('About this service',
                        style: MtTextStyles.labelLg.copyWith(color: MtColors.ink2)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: MtColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MtColors.line),
                      ),
                      child: Text(item.description, style: MtTextStyles.bodyMd),
                    ),
                  ],
                ],
              ),
            ),
            _ActionBar(
              price: item.price,
              onBook: () => _book(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _Header({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MtColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MtColors.ink),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Text(title, style: MtTextStyles.h3),
        ],
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  final String? url;
  const _HeroImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: (url == null || url!.isEmpty)
            ? Container(
                color: MtColors.brandSofter,
                child: const Icon(Icons.medical_services_outlined,
                    color: MtColors.brand, size: 48),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: MtColors.bg),
                errorWidget: (_, __, ___) => Container(
                  color: MtColors.brandSofter,
                  child: const Icon(Icons.broken_image_outlined, color: MtColors.ink3),
                ),
              ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: MtTextStyles.labelMd.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final double price;
  final VoidCallback onBook;

  const _ActionBar({required this.price, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From', style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              Text(_money(price),
                  style: MtTextStyles.h3.copyWith(color: MtColors.brand)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: MtButton(
              label: 'Book',
              leadingIcon: Icons.event_available,
              onPressed: onBook,
            ),
          ),
        ],
      ),
    );
  }
}
