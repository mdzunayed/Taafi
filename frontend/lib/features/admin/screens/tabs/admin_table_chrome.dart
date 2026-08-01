import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';

import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';

/// Shared visual chrome for the four new admin list screens (Patients,
/// Providers, Billing, Settings). Keeping it in one place means a future
/// refresh of the heading row / refresh button propagates everywhere
/// at once.
class AdminListScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Future<void> Function()? onRefresh;

  const AdminListScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: MtTextStyles.h2.copyWith(
                          color: MtColors.ink,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink3)),
                  ],
                ),
              ),
              if (onRefresh != null)
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Refresh', style: MtTextStyles.labelMd),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MtColors.ink,
                    side: const BorderSide(color: MtColors.line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class AdminCard extends StatelessWidget {
  final Widget child;
  const AdminCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: child,
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: MtColors.ink3.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(title,
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}

final adminTableDate = DateFormat('MMM d, y');

/// Single-line identifier cell for the admin data tables. Fixes the
/// column-crush bug where long MongoDB ObjectIDs wrapped vertically and
/// overlapped: the hash is middle-truncated (`a1b2c3...e4f5`), wrapped in a
/// [Tooltip] showing the full value on hover, and paired with a
/// click-to-clipboard icon. Short human ids (e.g. "MT-4827") pass through
/// untouched. Use everywhere an `id` renders inside a flex table column.
class AdminIdCell extends StatelessWidget {
  final String id;

  /// Optional leading urgency flame (matches the prior inline markup).
  final bool urgent;
  const AdminIdCell({super.key, required this.id, this.urgent = false});

  String get _display {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (urgent) ...[
          const Icon(Icons.local_fire_department,
              size: 14, color: MtColors.rejected),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Tooltip(
            message: id,
            waitDuration: const Duration(milliseconds: 300),
            child: Text(
              _display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: MtTextStyles.labelMd.copyWith(
                color: MtColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied $id'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.copy_outlined, size: 13, color: MtColors.ink3),
          ),
        ),
      ],
    );
  }
}
