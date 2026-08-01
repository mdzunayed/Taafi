import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../../core/widgets/mt_skeleton.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  late Future<List<_FaqCategory>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFaq();
  }

  Future<List<_FaqCategory>> _loadFaq() async {
    final raw = await rootBundle.loadString(SupportConfig.faqAsset);
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => _FaqCategory.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> _emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: SupportConfig.supportEmail,
      queryParameters: {'subject': 'Taafi support'},
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email us at ${SupportConfig.supportEmail}'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email us at ${SupportConfig.supportEmail}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MtColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Help & FAQ',
          style: MtTextStyles.h3.copyWith(color: MtColors.ink),
        ),
      ),
      body: FutureBuilder<List<_FaqCategory>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (var i = 0; i < 4; i++) ...[
                  MtSkeleton.line(width: 160, height: 16),
                  const SizedBox(height: 10),
                  MtSkeleton.box(height: 54, radius: 12),
                  const SizedBox(height: 8),
                  MtSkeleton.box(height: 54, radius: 12),
                  const SizedBox(height: 20),
                ],
              ],
            );
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: MtErrorState(
                message: snap.error.toString(),
                onRetry: () => setState(() => _future = _loadFaq()),
              ),
            );
          }
          final categories = snap.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final cat in categories) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cat.categoryEn.toUpperCase(),
                        style: MtTextStyles.sectionLabel.copyWith(
                          color: MtColors.ink3,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        cat.categoryBn,
                        style: MtTextStyles.sectionLabel.copyWith(
                          color: MtColors.ink3,
                          fontFamily: 'Kalpurush',
                        ),
                      ),
                    ],
                  ),
                ),
                for (final item in cat.items) _FaqTile(item: item),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MtColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MtColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Didn't find an answer?",
                        style: MtTextStyles.labelLg.copyWith(color: MtColors.ink)),
                    const SizedBox(height: 6),
                    Text(
                      SupportConfig.supportHoursLabel,
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink3),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _emailSupport,
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: Text('Email support',
                          style: MtTextStyles.labelMd),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MtColors.brand,
                        side: const BorderSide(color: MtColors.brand),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: MtColors.brand,
          collapsedIconColor: MtColors.ink3,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.qEn, style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
              if (item.qBn.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.qBn,
                  style: MtTextStyles.bodySm.copyWith(
                    color: MtColors.ink3,
                    fontFamily: 'Kalpurush',
                  ),
                ),
              ],
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.aEn,
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                  ),
                  if (item.aBn.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.aBn,
                      style: MtTextStyles.bodySm.copyWith(
                        color: MtColors.ink3,
                        fontFamily: 'Kalpurush',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqCategory {
  final String categoryEn;
  final String categoryBn;
  final List<_FaqItem> items;

  _FaqCategory({
    required this.categoryEn,
    required this.categoryBn,
    required this.items,
  });

  factory _FaqCategory.fromJson(Map<String, dynamic> json) {
    return _FaqCategory(
      categoryEn: json['categoryEn']?.toString() ?? '',
      categoryBn: json['categoryBn']?.toString() ?? '',
      items: (json['items'] as List? ?? const [])
          .map((e) => _FaqItem.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class _FaqItem {
  final String qEn;
  final String qBn;
  final String aEn;
  final String aBn;

  _FaqItem({
    required this.qEn,
    required this.qBn,
    required this.aEn,
    required this.aBn,
  });

  factory _FaqItem.fromJson(Map<String, dynamic> json) {
    return _FaqItem(
      qEn: json['qEn']?.toString() ?? '',
      qBn: json['qBn']?.toString() ?? '',
      aEn: json['aEn']?.toString() ?? '',
      aBn: json['aBn']?.toString() ?? '',
    );
  }
}
