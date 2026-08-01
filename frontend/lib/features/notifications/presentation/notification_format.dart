import 'package:intl/intl.dart';

import '../models/notification_item.dart';

/// Pure presentation helpers shared by the full-screen notification hub and the
/// glassmorphic notification panel — timeline bucketing and relative-time
/// labels. Kept free of widgets/theme so both a light and a dark surface can
/// reuse the exact same grouping/label logic.

/// A day-bucket of notifications ("Today" / "Yesterday" / "Earlier").
class NotificationDayGroup {
  final String label;
  final List<NotificationItem> items;
  const NotificationDayGroup({required this.label, required this.items});
}

/// Buckets [items] into Today / Yesterday / Earlier, preserving their order
/// within each bucket. Empty buckets are omitted.
List<NotificationDayGroup> groupNotificationsByDay(
  List<NotificationItem> items,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final todayItems = <NotificationItem>[];
  final yesterdayItems = <NotificationItem>[];
  final earlierItems = <NotificationItem>[];
  for (final n in items) {
    final t = n.timestamp.toLocal();
    final d = DateTime(t.year, t.month, t.day);
    if (d == today) {
      todayItems.add(n);
    } else if (d == yesterday) {
      yesterdayItems.add(n);
    } else {
      earlierItems.add(n);
    }
  }
  return [
    if (todayItems.isNotEmpty)
      NotificationDayGroup(label: 'Today', items: todayItems),
    if (yesterdayItems.isNotEmpty)
      NotificationDayGroup(label: 'Yesterday', items: yesterdayItems),
    if (earlierItems.isNotEmpty)
      NotificationDayGroup(label: 'Earlier', items: earlierItems),
  ];
}

/// Compact relative-time label: "Just now", "5 min ago", "3 hr ago", "2 d ago",
/// then an absolute "Aug 12" once older than a week.
String notificationRelativeTime(DateTime when) {
  final local = when.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return DateFormat('MMM d').format(local);
}
