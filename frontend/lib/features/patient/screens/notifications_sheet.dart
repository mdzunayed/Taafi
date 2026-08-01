import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/patient_notification.dart';
import '../../../core/models/patient_request_status.dart';
import '../../../core/models/recent_provider.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../navigation/patient_nav_provider.dart';
import 'provider_profile_screen.dart';

Future<void> showPatientNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MtColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(patientNotificationsProvider);
    final hasUnread =
        notifications.valueOrNull?.any((n) => !n.read) ?? false;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MtColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notifications',
                            style: MtTextStyles.h3
                                .copyWith(color: MtColors.ink)),
                        const SizedBox(height: 2),
                        Text(
                          'নোটিফিকেশন',
                          style: MtTextStyles.bodySm.copyWith(
                            color: MtColors.ink3,
                            fontFamily: 'Kalpurush',
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: hasUnread
                        ? () async {
                            try {
                              await ref
                                  .read(patientNotificationsProvider.notifier)
                                  .markAllRead();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Could not mark all read: $e')),
                                );
                              }
                            }
                          }
                        : null,
                    style: TextButton.styleFrom(
                      foregroundColor: MtColors.brand,
                      disabledForegroundColor: MtColors.ink3,
                    ),
                    child: Text('Mark all read',
                        style: MtTextStyles.labelMd),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: MtColors.line),
            Expanded(
              child: AsyncValueView<List<PatientNotification>>(
                value: notifications,
                onRetry: () =>
                    ref.read(patientNotificationsProvider.notifier).refresh(),
                loadingBuilder: (_) => ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: 5,
                  itemBuilder: (context, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        MtSkeleton.circle(size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MtSkeleton.line(width: 180),
                              const SizedBox(height: 6),
                              MtSkeleton.line(width: 240, height: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                isEmpty: (list) => list.isEmpty,
                emptyBuilder: (_) => const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: MtEmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications yet',
                    subtitle:
                        'Booking updates and announcements will show up here.',
                    bnSubtitle: 'বুকিং আপডেট ও ঘোষণা এখানে দেখাবে।',
                  ),
                ),
                dataBuilder: (context, list) {
                  final now = DateTime.now();
                  final today = <PatientNotification>[];
                  final earlier = <PatientNotification>[];
                  for (final n in list) {
                    final sameDay = n.createdAt.year == now.year &&
                        n.createdAt.month == now.month &&
                        n.createdAt.day == now.day;
                    (sameDay ? today : earlier).add(n);
                  }
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (today.isNotEmpty) ...[
                        _GroupHeader(label: 'Today'),
                        for (final n in today)
                          _NotificationTile(notification: n),
                      ],
                      if (earlier.isNotEmpty) ...[
                        if (today.isNotEmpty) const SizedBox(height: 12),
                        _GroupHeader(label: 'Earlier'),
                        for (final n in earlier)
                          _NotificationTile(notification: n),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: MtTextStyles.sectionLabel.copyWith(
          color: MtColors.ink3,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final PatientNotification notification;
  const _NotificationTile({required this.notification});

  IconData _iconFor(PatientNotificationKind kind) {
    switch (kind) {
      case PatientNotificationKind.request:
        return Icons.medical_services_outlined;
      case PatientNotificationKind.provider:
        return Icons.person_outline;
      case PatientNotificationKind.system:
        return Icons.info_outline;
    }
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return DateFormat('MMM d').format(when);
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // The outer Scaffold context (under the patient home tab) is what
    // owns the Navigator we want to push the profile screen onto. The
    // sheet itself will be popped first.
    final outerContext = Navigator.of(context).context;
    final activeRequest = ref.read(patientActiveRequestProvider);

    void Function()? destinationJump;
    RecentProvider? providerToOpen;
    bool providerLookupFailed = false;

    switch (notification.kind) {
      case PatientNotificationKind.request:
        final requestId = notification.payload?['requestId']?.toString();
        if (requestId != null &&
            activeRequest != null &&
            activeRequest.id == requestId) {
          switch (activeRequest.status.homeRouteTarget) {
            case HomeRouteTarget.underReview:
              destinationJump = () =>
                  ref.goToActivities(sub: PatientActivitiesTab.underReview);
              break;
            case HomeRouteTarget.tracking:
              destinationJump = () =>
                  ref.goToActivities(sub: PatientActivitiesTab.tracking);
              break;
            case HomeRouteTarget.none:
              destinationJump = () =>
                  ref.goToActivities(sub: PatientActivitiesTab.underReview);
              break;
          }
        } else {
          destinationJump = () =>
              ref.goToActivities(sub: PatientActivitiesTab.underReview);
        }
        break;
      case PatientNotificationKind.provider:
        final providerId = notification.payload?['providerId']?.toString();
        final feed = ref.read(patientHomeFeedProvider).valueOrNull;
        RecentProvider? match;
        if (providerId != null && feed != null) {
          for (final p in feed.recentProviders) {
            if (p.id == providerId) {
              match = p;
              break;
            }
          }
        }
        if (match != null) {
          providerToOpen = match;
        } else if (providerId != null) {
          providerLookupFailed = true;
        }
        break;
      case PatientNotificationKind.system:
        break;
    }

    Navigator.of(context).maybePop();

    try {
      await ref
          .read(patientNotificationsProvider.notifier)
          .markRead(notification.id);
    } catch (_) {
      // controller handles rollback; do not block navigation
    }

    destinationJump?.call();

    if (providerToOpen != null && outerContext.mounted) {
      await Navigator.of(outerContext).push<bool>(
        MaterialPageRoute(
          builder: (_) => ProviderProfileScreen(provider: providerToOpen),
        ),
      );
    } else if (providerLookupFailed && outerContext.mounted) {
      ScaffoldMessenger.of(outerContext).showSnackBar(
        const SnackBar(content: Text('Provider details unavailable')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notification.read;
    final titleStyle = MtTextStyles.labelMd.copyWith(
      color: MtColors.ink,
      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
    );

    return Material(
      color: unread ? MtColors.brandSofter.withValues(alpha: 0.45) : MtColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context, ref),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MtColors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(notification.kind),
                    color: MtColors.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(notification.titleEn, style: titleStyle),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: const BoxDecoration(
                              color: MtColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.bodyEn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(notification.createdAt),
                      style: MtTextStyles.bodySm.copyWith(
                        color: MtColors.ink3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
