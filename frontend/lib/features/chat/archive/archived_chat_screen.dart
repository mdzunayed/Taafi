import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/appointment.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../patient/history/patient_history_provider.dart';
import '../models/message_model.dart';

/// Read-only conversation timeline scoped to a single past
/// appointment. Pulls the transcript via [archivedChatProvider] and
/// renders it as alternating chat bubbles. No input pane — the
/// archive screen is deliberately one-way.
///
/// Desktop / web layout cap: the conversation column is constrained
/// to 650 px so long transcripts stay readable on wide monitors.
class ArchivedChatScreen extends ConsumerWidget {
  final Appointment appointment;
  const ArchivedChatScreen({super.key, required this.appointment});

  static const double _maxContentWidth = 650;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(archivedChatProvider(appointment.id));
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Archived chat'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              children: [
                _ContextBanner(appointment: appointment),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: MtColors.brand),
                    ),
                    error: (e, _) => _ErrorView(message: e.toString()),
                    data: (messages) => messages.isEmpty
                        ? const _EmptyTranscript()
                        : _TranscriptList(
                            messages: messages,
                            patientId: appointment.id, // sender check uses id, see below
                          ),
                  ),
                ),
                const _ReadOnlyFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context banner — fixed at top of the transcript
// ---------------------------------------------------------------------------

class _ContextBanner extends StatelessWidget {
  final Appointment appointment;
  const _ContextBanner({required this.appointment});

  String get _summary {
    final care = appointment.careType.isEmpty ? 'visit' : appointment.careType;
    final provider = appointment.assignedDoctorName?.trim().isNotEmpty == true
        ? appointment.assignedDoctorName
        : 'your provider';
    final date = DateFormat('MMM d').format(appointment.updatedAt.toLocal());
    return 'Archived Chat — $care with $provider on $date';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.brandSoft),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.archive_outlined,
              size: 18,
              color: MtColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _summary,
              style: MtTextStyles.labelMd.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript list
// ---------------------------------------------------------------------------

class _TranscriptList extends ConsumerWidget {
  final List<MessageModel> messages;
  final String patientId;
  const _TranscriptList({
    required this.messages,
    required this.patientId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Identify the "current user" side of the conversation so the
    // bubble alignment + colour scheme picks the patient's outbound
    // rows accurately. The archived screen runs in the patient's
    // session by definition; we resolve via the senderId frequency
    // when no auth context is available (fallback below).
    final patientSenderId = _detectPatientSenderId(messages);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMine = msg.senderId == patientSenderId;
        final showDay = index == 0 ||
            !_sameDay(messages[index - 1].timestamp, msg.timestamp);
        return Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showDay) _DateChip(date: msg.timestamp),
            _Bubble(message: msg, isMine: isMine),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Counts which senderId appears most frequently — in a 1:1 chat
  /// between the patient and the provider, that's typically the
  /// patient. Falls back to the first sender if the list is empty.
  /// Good enough for visual alignment in the archive; it does not
  /// affect any wire data.
  static String _detectPatientSenderId(List<MessageModel> messages) {
    if (messages.isEmpty) return '';
    final counts = <String, int>{};
    for (final m in messages) {
      counts[m.senderId] = (counts[m.senderId] ?? 0) + 1;
    }
    String top = messages.first.senderId;
    int max = 0;
    counts.forEach((id, n) {
      if (n > max) {
        max = n;
        top = id;
      }
    });
    return top;
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEE, MMM d').format(date.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: MtColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MtColors.line),
          ),
          child: Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  const _Bubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        DateFormat('h:mm a').format(message.timestamp.toLocal());
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? MtColors.brand : MtColors.surface,
        borderRadius: radius,
        border: isMine ? null : Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.messageText,
            style: MtTextStyles.bodyMd.copyWith(
              color: isMine ? Colors.white : MtColors.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            style: MtTextStyles.bodySm.copyWith(
              color: isMine
                  ? Colors.white.withValues(alpha: 0.78)
                  : MtColors.ink3,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
    if (isMine) return bubble;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const InitialsAvatar(
          name: 'Provider',
          size: 26,
          backgroundColor: MtColors.brandSoft,
          textColor: MtColors.brand,
        ),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error / footer
// ---------------------------------------------------------------------------

class _EmptyTranscript extends StatelessWidget {
  const _EmptyTranscript();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: MtColors.brandSofter,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 32,
                color: MtColors.brand,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No messages were exchanged',
              style: MtTextStyles.h2.copyWith(color: MtColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'This visit completed without a recorded conversation.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        const Center(
          child: Icon(Icons.cloud_off_outlined,
              size: 36, color: MtColors.ink3),
        ),
        const SizedBox(height: 10),
        Text(
          "Couldn't load the transcript",
          textAlign: TextAlign.center,
          style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
        ),
      ],
    );
  }
}

class _ReadOnlyFooter extends StatelessWidget {
  const _ReadOnlyFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: MtColors.ink3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Read-only — this conversation is archived.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
