import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../models/message_model.dart';
import '../../providers/chat_provider.dart';
import 'chat_palette.dart';

/// Shared scrollable message thread — the single source of truth for how a
/// chat renders across the full-screen [ChatScreen] and the slide-in
/// `ActiveChatDrawer`. Handles the loading / error / empty states plus the
/// grouped-bubble ListView (avatar + timestamp collapse within a 2-minute
/// block) and renders TEXT, IMAGE and LOCATION message kinds.
class ChatMessageList extends StatelessWidget {
  final ChatState state;
  final ScrollController scrollController;
  final String currentUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final Future<void> Function() onRetry;
  final EdgeInsets padding;

  const ChatMessageList({
    super.key,
    required this.state,
    required this.scrollController,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserAvatarUrl,
    required this.onRetry,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    if (state.status == ChatStatus.loading && state.messages.isEmpty) {
      return Center(child: CircularProgressIndicator(color: cc.brand));
    }
    if (state.status == ChatStatus.error && state.messages.isEmpty) {
      return _ChatError(
        message: state.errorMessage ?? 'Could not load messages.',
        onRetry: onRetry,
      );
    }
    if (state.messages.isEmpty) {
      return const _EmptyConversation();
    }

    final messages = state.messages;
    return ListView.builder(
      controller: scrollController,
      padding: padding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMine = msg.isMine(currentUserId);

        final prev = index > 0 ? messages[index - 1] : null;
        final next = index + 1 < messages.length ? messages[index + 1] : null;

        final sameSenderAsPrev = prev != null && prev.senderId == msg.senderId;
        final closeToPrev = prev != null &&
            msg.timestamp.difference(prev.timestamp).inMinutes.abs() <= 2;
        final isGroupContinuation = sameSenderAsPrev && closeToPrev;

        final sameSenderAsNext = next != null && next.senderId == msg.senderId;
        final closeToNext = next != null &&
            next.timestamp.difference(msg.timestamp).inMinutes.abs() <= 2;
        final isGroupLast = !(sameSenderAsNext && closeToNext);

        final showDateChip = index == 0 ||
            !_isSameDay(messages[index - 1].timestamp, msg.timestamp);

        return Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showDateChip) _DateChip(date: msg.timestamp),
            ChatMessageBubble(
              message: msg,
              isMine: isMine,
              otherName: otherUserName,
              otherAvatarUrl: otherUserAvatarUrl,
              isGroupContinuation: isGroupContinuation,
              isGroupLast: isGroupLast,
            ),
            SizedBox(height: isGroupLast ? 12 : 3),
          ],
        );
      },
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------------------------------------------------------------------------
// Bubble
// ---------------------------------------------------------------------------

/// One message bubble. Renders TEXT inline, IMAGE as a rounded thumbnail
/// (tap to expand full-screen), and LOCATION as a mini-map card with an
/// "Open Directions" action. Outgoing bubbles use the brand fill; incoming
/// use the theme surface tint.
class ChatMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final String otherName;
  final String? otherAvatarUrl;
  final bool isGroupContinuation;
  final bool isGroupLast;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.otherName,
    required this.otherAvatarUrl,
    required this.isGroupContinuation,
    required this.isGroupLast,
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final timeLabel = DateFormat('h:mm a').format(message.timestamp.toLocal());

    final topRadius = isGroupContinuation
        ? const Radius.circular(8)
        : const Radius.circular(18);
    final bubbleShape = BorderRadius.only(
      topLeft: isMine ? const Radius.circular(18) : topRadius,
      topRight: isMine ? topRadius : const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    final hasCaption = message.messageText.trim().isNotEmpty;
    final isMedia = message.messageType == MessageType.image ||
        message.messageType == MessageType.location;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth(context)),
      // Media messages get tighter padding so the thumbnail can bleed
      // closer to the bubble edge.
      padding: isMedia
          ? const EdgeInsets.all(6)
          : const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isMine ? cc.brand : cc.surfaceHi,
        borderRadius: bubbleShape,
        boxShadow: [
          BoxShadow(
            color: (isMine ? cc.brand : cc.ink).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.messageType == MessageType.image)
            _ImageContent(message: message, cc: cc),
          if (message.messageType == MessageType.location)
            _LocationContent(message: message, isMine: isMine, cc: cc),
          if (message.messageType == MessageType.text || (isMedia && hasCaption))
            Padding(
              padding: isMedia
                  ? const EdgeInsets.fromLTRB(8, 6, 8, 0)
                  : EdgeInsets.zero,
              child: Text(
                message.messageText,
                style: MtTextStyles.bodyMd.copyWith(
                  color: isMine ? Colors.white : cc.ink,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (isGroupLast) ...[
            const SizedBox(height: 6),
            Padding(
              padding:
                  isMedia ? const EdgeInsets.symmetric(horizontal: 8) : EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: MtTextStyles.bodySm.copyWith(
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.78)
                          : cc.ink3,
                      fontSize: 10.5,
                      height: 1.0,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    _DeliveryTicks(isRead: message.isRead),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (isMine) return bubble;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isGroupLast)
          ChatAvatar(name: otherName, url: otherAvatarUrl, size: 28)
        else
          const SizedBox(width: 28),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }

  double _bubbleMaxWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 768) return 560;
    return w * 0.74;
  }
}

// ---------------------------------------------------------------------------
// Media renderers
// ---------------------------------------------------------------------------

class _ImageContent extends StatelessWidget {
  final MessageModel message;
  final ChatPalette cc;
  const _ImageContent({required this.message, required this.cc});

  @override
  Widget build(BuildContext context) {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => _openViewer(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: 220,
            height: 220,
            color: cc.surface,
            child: Center(
              child: CircularProgressIndicator(color: cc.brand, strokeWidth: 2),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            width: 220,
            height: 160,
            color: cc.surface,
            child: Icon(Icons.broken_image_outlined, color: cc.ink3),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogCtx) => Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                // Overrides both fallbacks for the dark barrier — the default
                // grey surface box would read as a broken dialog here.
                child: AppNetworkImage(
                  url: url,
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) => const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                  errorBuilder: (_) => const Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(dialogCtx).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationContent extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final ChatPalette cc;
  const _LocationContent({
    required this.message,
    required this.isMine,
    required this.cc,
  });

  @override
  Widget build(BuildContext context) {
    final loc = message.locationCoordinates;
    if (loc == null || !loc.isValid) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          '📍 Location unavailable',
          style: MtTextStyles.bodyMd.copyWith(
            color: isMine ? Colors.white : cc.ink,
          ),
        ),
      );
    }
    final point = LatLng(loc.latitude, loc.longitude);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 220,
            height: 140,
            child: IgnorePointer(
              // A static thumbnail — dragging the thread shouldn't fight the
              // map. The "Open Directions" button below handles interaction.
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.taafi.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.location_on,
                          color: cc.brand,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (loc.addressSnippet.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(
              loc.addressSnippet,
              style: MtTextStyles.bodySm.copyWith(
                color: isMine ? Colors.white.withValues(alpha: 0.9) : cc.ink2,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: TextButton.icon(
            onPressed: () => _openDirections(context, loc),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              foregroundColor: isMine ? Colors.white : cc.brand,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Open Directions'),
          ),
        ),
      ],
    );
  }

  Future<void> _openDirections(
    BuildContext context,
    LocationCoordinates loc,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Universal Google Maps URL — resolves to the native app when present,
    // the browser otherwise. Works cross-platform without a maps SDK.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open a maps app.')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _DateChip extends StatelessWidget {
  final DateTime date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final now = DateTime.now();
    final isToday =
        now.year == date.year && now.month == date.month && now.day == date.day;
    final label =
        isToday ? 'Today' : DateFormat('EEE, MMM d').format(date.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: cc.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cc.line),
          ),
          child: Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: cc.ink3),
          ),
        ),
      ),
    );
  }
}

/// Single-tick (sent) / double-tick (read) delivery indicator. Read state
/// turns the ticks brand-blue against the white timestamp of an outgoing
/// bubble.
class _DeliveryTicks extends StatelessWidget {
  final bool isRead;
  const _DeliveryTicks({required this.isRead});

  @override
  Widget build(BuildContext context) {
    final color =
        isRead ? const Color(0xFF60A5FA) : Colors.white.withValues(alpha: 0.78);
    return Icon(isRead ? Icons.done_all : Icons.done, size: 14, color: color);
  }
}

/// Circular avatar with a network image + initials fallback. Public so both
/// the message list and the drawer header reuse it.
class ChatAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const ChatAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    final cleaned = name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '');
    final src = url;
    if (src != null && src.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: cleaned,
            size: size,
            backgroundColor: cc.brand,
            textColor: Colors.white,
          ),
        ),
      );
    }
    return InitialsAvatar(
      name: cleaned,
      size: size,
      backgroundColor: cc.brand,
      textColor: Colors.white,
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration:
                  BoxDecoration(color: cc.brandSofter, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_outline, size: 32, color: cc.brand),
            ),
            const SizedBox(height: 14),
            Text('Start the conversation',
                style: MtTextStyles.h2.copyWith(color: cc.ink)),
            const SizedBox(height: 6),
            Text(
              'Messages you send here are delivered instantly and stay '
              'attached to this visit.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodyMd.copyWith(color: cc.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ChatError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cc = ChatPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 36, color: cc.ink3),
            const SizedBox(height: 12),
            Text("Couldn't load conversation",
                style: MtTextStyles.labelLg.copyWith(color: cc.ink)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: cc.ink2),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => onRetry(),
              style: ElevatedButton.styleFrom(
                backgroundColor: cc.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
