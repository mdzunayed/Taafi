import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/image_upload.dart';
import '../../../auth/auth_provider.dart';
import '../../providers/chat_provider.dart';
import 'chat_palette.dart';

/// Shared composer for every chat surface. Owns the floating pill text field,
/// the attach menu (image via gallery/camera → Cloudinary upload → IMAGE
/// message; live GPS → LOCATION message), the animated send button, and the
/// outbound typing signal. Reads the [chatProvider] notifier for [args] so
/// both the full-screen [ChatScreen] and the slide-in `ActiveChatDrawer`
/// share one send path.
class ChatInputBar extends ConsumerStatefulWidget {
  final ChatArgs args;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;

  /// Attachments (image + location) only apply to the appointment path — the
  /// multi-role conversation engine stays text-only for now.
  final bool enableAttachments;

  const ChatInputBar({
    super.key,
    required this.args,
    required this.controller,
    required this.focusNode,
    required this.isSending,
    this.enableAttachments = true,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _picker = ImagePicker();
  bool _hasText = false;
  bool _busy = false;

  ChatNotifier get _notifier => ref.read(chatProvider(widget.args).notifier);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncHasText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    super.dispose();
  }

  void _syncHasText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
    // Fan out our typing signal (debounced inside the notifier).
    if (next) _notifier.notifyTyping();
  }

  Future<void> _handleSend() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    widget.controller.clear();
    await _notifier.sendMessage(text);
    if (mounted) widget.focusNode.requestFocus();
  }

  // --- Attachments ---------------------------------------------------------

  Future<void> _pickAndSendImage(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (file == null) return;
      setState(() => _busy = true);
      // Derives the filename and MIME from the bytes. Guessing from the
      // extension sent an iOS HEIC as `IMG_1.heic` labelled image/jpeg —
      // which the upload filter rejects on the extension, and which used to
      // be delivered into the thread as an unrenderable attachment.
      final prepared = await prepareImageForUpload(file);
      final client = ref.read(dioClientProvider);
      final mediaUrl = await client.uploadChatAttachment(
        appointmentId: widget.args.appointmentId,
        bytes: prepared.bytes,
        filename: prepared.filename,
        mimeType: prepared.mimeType,
      );
      await _notifier.sendImage(mediaUrl);
    } on UnsupportedImageException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send image: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLiveLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Turn on location services to share.')),
        );
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }
      setState(() => _busy = true);
      final pos = await Geolocator.getCurrentPosition();
      final snippet =
          'Lat ${pos.latitude.toStringAsFixed(5)}, Lng ${pos.longitude.toStringAsFixed(5)}';
      await _notifier.sendLocation(
        pos.latitude,
        pos.longitude,
        addressSnippet: snippet,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share location: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showAttachMenu() {
    final cc = ChatPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cc.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              _AttachAction(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                description: 'Capture and share a photo instantly.',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              _AttachAction(
                icon: Icons.image_outlined,
                label: 'Photo from gallery',
                description: 'Attach a lab report, wound photo or prescription.',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              _AttachAction(
                icon: Icons.location_on_outlined,
                label: 'Share live location',
                description: 'Send your current coordinates on a map.',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _shareLiveLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final sending = widget.isSending || _busy;
    final canSend = _hasText && !sending;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: cc.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cc.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.enableAttachments)
              IconButton(
                onPressed: sending ? null : _showAttachMenu,
                tooltip: 'Attach',
                icon: Icon(Icons.add_circle_outline, color: cc.ink2),
              ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                style: MtTextStyles.bodyMd.copyWith(color: cc.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Type a message…',
                  hintStyle: MtTextStyles.bodyMd.copyWith(color: cc.ink3),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _AnimatedSendButton(
              enabled: canSend,
              isSending: sending,
              onTap: _handleSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  const _AttachAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cc.brandSofter,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cc.brand, size: 20),
      ),
      title: Text(label, style: MtTextStyles.labelLg),
      subtitle: Text(
        description,
        style: MtTextStyles.bodySm.copyWith(color: cc.ink2),
      ),
    );
  }
}

class _AnimatedSendButton extends StatelessWidget {
  final bool enabled;
  final bool isSending;
  final Future<void> Function() onTap;
  const _AnimatedSendButton({
    required this.enabled,
    required this.isSending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final background = enabled ? cc.brand : cc.brandSofter;
    final iconColor = enabled ? Colors.white : cc.brand;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: cc.brand.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onTap() : null,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: isSending
                ? const SizedBox(
                    key: ValueKey('sending'),
                    width: 18,
                    height: 18,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : Icon(
                    Icons.send,
                    key: const ValueKey('send'),
                    size: 20,
                    color: iconColor,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Footer that replaces the composer once the visit's communication channel
/// locks (completed / cancelled). The transcript stays scrollable; it just
/// can't be appended to. Shared by [ChatScreen] and `ActiveChatDrawer`.
class ChatLockedFooter extends StatelessWidget {
  const ChatLockedFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cc.surface,
        border: Border(top: BorderSide(color: cc.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration:
                BoxDecoration(color: cc.brandSofter, shape: BoxShape.circle),
            child: Icon(Icons.lock_outline, size: 16, color: cc.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This service has ended.',
                  style: MtTextStyles.labelMd.copyWith(
                    color: cc.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Communication history is now read-only.',
                  style: MtTextStyles.bodySm.copyWith(color: cc.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
