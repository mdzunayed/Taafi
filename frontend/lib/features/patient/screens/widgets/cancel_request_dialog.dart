import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/patient_home_repository.dart';
import '../../../../core/theme/mt_text_styles.dart';
import 'patient_home_palette.dart';

/// Patient self-cancel. Offered only in the states the backend's
/// `PATIENT_CANCELLABLE` guard accepts — before a coordinator claims the
/// dispatch, when nothing has been paid and cancelling costs nothing.
///
/// A patient who decides not to pay the deposit needs this way out: the
/// booking still counts as "active", so until it is cancelled the
/// one-active-booking rule blocks every new request.
Future<void> confirmCancelRequest(
  BuildContext context,
  WidgetRef ref,
  String requestId,
) async {
  final hd = HomeDark.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<_CancelDialogResult>(
    context: context,
    builder: (_) => const _CancelConfirmDialog(),
  );
  if (result == null || !result.confirmed) return;

  try {
    await ref
        .read(patientHomeFeedProvider.notifier)
        .cancelActiveRequest(reason: result.reason);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Request $requestId cancelled'),
        backgroundColor: hd.positive,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not cancel request: $e'),
        backgroundColor: hd.danger,
      ),
    );
  }
}

class _CancelDialogResult {
  final bool confirmed;
  final String? reason;
  const _CancelDialogResult({required this.confirmed, this.reason});
}

/// Confirmation dialog with an optional cancellation reason. Pre-fills a few
/// common reasons as quick-select chips while still allowing free-text.
class _CancelConfirmDialog extends StatefulWidget {
  const _CancelConfirmDialog();

  @override
  State<_CancelConfirmDialog> createState() => _CancelConfirmDialogState();
}

class _CancelConfirmDialogState extends State<_CancelConfirmDialog> {
  static const _quickReasons = [
    'Booked by mistake',
    'Patient feels better',
    'Found care elsewhere',
    'Schedule conflict',
  ];

  String? _selected;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  String? _finalReason() {
    if (_otherCtrl.text.trim().isNotEmpty) return _otherCtrl.text.trim();
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Cancel request?', style: MtTextStyles.h3),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You'll lose your place in the queue. Any escrowed payment is "
              'refunded within 24 hrs.',
              style: MtTextStyles.bodyMd.copyWith(color: hd.body),
            ),
            const SizedBox(height: 14),
            Text(
              'WHY ARE YOU CANCELLING?',
              style: MtTextStyles.sectionLabel.copyWith(
                color: hd.muted,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in _quickReasons)
                  ChoiceChip(
                    label: Text(reason, style: MtTextStyles.labelSm),
                    selected: _selected == reason,
                    onSelected: (_) {
                      setState(() {
                        _selected = _selected == reason ? null : reason;
                      });
                    },
                    selectedColor: hd.violet.withValues(alpha: 0.14),
                    labelStyle: MtTextStyles.labelSm.copyWith(
                      color: _selected == reason ? hd.violetDeep : hd.body,
                    ),
                    side: BorderSide(
                      color: _selected == reason ? hd.violet : hd.border,
                    ),
                    backgroundColor: hd.surface,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otherCtrl,
              maxLines: 2,
              style: MtTextStyles.bodyMd,
              decoration: InputDecoration(
                hintText: 'Other (optional)',
                hintStyle: MtTextStyles.bodySm.copyWith(color: hd.muted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: hd.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: hd.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: hd.violet, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const _CancelDialogResult(confirmed: false),
          ),
          style: TextButton.styleFrom(foregroundColor: hd.body),
          child: Text('Keep request', style: MtTextStyles.labelMd),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _CancelDialogResult(confirmed: true, reason: _finalReason()),
          ),
          style: TextButton.styleFrom(foregroundColor: hd.danger),
          child: Text('Cancel request', style: MtTextStyles.labelMd),
        ),
      ],
    );
  }
}
