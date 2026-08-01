import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/models/assigned_doctor.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/vitals_grid.dart';
import '../providers/active_chat_provider.dart';
import '../providers/chat_provider.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_list.dart';

// Re-export the shared [PatientVitals] + [VitalsGrid] so existing
// call-sites (`ChatScreen(patientVitals: …)`) keep compiling without
// importing `core/widgets/vitals_grid.dart` themselves.
export '../../../core/widgets/vitals_grid.dart' show PatientVitals, VitalsGrid;

/// Which side of the conversation is rendering. Drives the context
/// sidebar (doctor sees patient vitals, patient sees the assigned-doctor
/// credential card) and the role-specific app bar action.
enum ChatRole { patient, doctor }

/// Theme-reactive color resolver for the chat surface. Field names mirror
/// the legacy `MtColors` tokens so the migration was a mechanical swap, but
/// every value now comes from the light/dark [AppColors] extension — this
/// is what makes the whole screen flip to the dark obsidian canvas
/// (`#0D151C`) with the vibrant `#F36512` orange accent. Build one per
/// `build` via `final cc = _ChatColors.of(context);`.
class _ChatColors {
  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color brand;
  final Color brandSoft;
  final Color brandSofter;
  final Color onBrand;

  const _ChatColors({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.brand,
    required this.brandSoft,
    required this.brandSofter,
    required this.onBrand,
  });

  factory _ChatColors.of(BuildContext context) {
    final a = context.appColors;
    return _ChatColors(
      bg: a.canvas,
      surface: a.surface,
      surfaceHi: a.surfaceHi,
      ink: a.title,
      ink2: a.body,
      ink3: a.muted,
      line: a.cardBorder,
      brand: a.accent,
      brandSoft: a.accent.withValues(alpha: 0.28),
      brandSofter: a.accent.withValues(alpha: 0.12),
      onBrand: a.onAccent,
    );
  }
}

/// Premium real-time consultation console. Responsive: a single column
/// on mobile (< 768 px) and a 65/35 split with a fixed context sidebar
/// on desktop / web. Powered by [chatProvider] — same as the original
/// surface, only the visual shell changes.
class ChatScreen extends ConsumerStatefulWidget {
  /// Appointment-chat mode: the CareRequest id. Empty in conversation mode.
  final String appointmentId;

  /// Conversation-engine mode: the thread id. When set, the screen drives a
  /// multi-role / group thread (`conversation:*` events) and hides the
  /// appointment-specific context sidebar.
  final String? conversationId;

  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final String? otherUserSubtitle;

  /// Which dashboard is showing this chat. Defaults to patient.
  final ChatRole role;

  /// Patient view → populated assigned doctor for the sidebar credential
  /// card. Optional; the sidebar gracefully degrades when absent.
  final AssignedDoctor? assignedDoctor;

  // ---- Doctor view sidebar inputs (all optional) -------------------------

  /// Free-text patient address shown on the doctor's sidebar map card.
  final String? patientAddress;

  /// Patient phone for the "Call Patient" quick-action button on the
  /// doctor sidebar.
  final String? patientPhone;

  /// Service title (e.g. "Post-surgery home care") rendered as the
  /// sidebar header subtitle.
  final String? careType;

  /// Latest vitals snapshot — drives the BP / Temp / SpO₂ tile row on
  /// the doctor sidebar. Defaults to `PatientVitals.empty`.
  final PatientVitals patientVitals;

  const ChatScreen({
    super.key,
    this.appointmentId = '',
    this.conversationId,
    required this.currentUserId,
    this.otherUserId = '',
    required this.otherUserName,
    this.otherUserAvatarUrl,
    this.otherUserSubtitle,
    this.role = ChatRole.patient,
    this.assignedDoctor,
    this.patientAddress,
    this.patientPhone,
    this.careType,
    this.patientVitals = PatientVitals.empty,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  int _previousMessageCount = 0;

  /// Anything ≥ this width gets the split-pane layout.
  static const double _desktopBreakpoint = 768;

  /// Center-constrained chat thread cap on wide screens.
  static const double _chatColumnMaxWidth = 800;

  ChatArgs get _args => ChatArgs(
        appointmentId: widget.appointmentId,
        conversationId: widget.conversationId,
        currentUserId: widget.currentUserId,
        otherUserId: widget.otherUserId,
      );

  /// Normalised key for the thread this screen shows. Registered with
  /// [activeChatProvider] so the app-wide chime stays silent while we're
  /// the focused room.
  String? get _threadKey => chatThreadKey(
        conversationId: widget.conversationId,
        appointmentId: widget.appointmentId,
      );

  @override
  void initState() {
    super.initState();
    final key = _threadKey;
    if (key != null) {
      // Defer past the first build — mutating a provider synchronously in
      // initState would fire mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(activeChatProvider.notifier).enter(key);
      });
    }
  }

  @override
  void dispose() {
    final key = _threadKey;
    if (key != null) ref.read(activeChatProvider.notifier).leave(key);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _maybeScrollToBottom(int newCount) {
    if (newCount == _previousMessageCount) return;
    _previousMessageCount = newCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _callHelpline(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialer. Call ${SupportConfig.supportPhoneDisplay} manually.',
          ),
        ),
      );
    }
  }

  void _logVitals(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log vitals — coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    final state = ref.watch(chatProvider(_args));
    _maybeScrollToBottom(state.messages.length);

    return Scaffold(
      backgroundColor: cc.bg,
      appBar: _ChatAppBar(
        name: widget.otherUserName,
        avatarUrl: widget.otherUserAvatarUrl,
        subtitle: widget.otherUserSubtitle ?? 'Active Chat Support',
        isConnected: state.isConnected,
        role: widget.role,
        onLogVitals: () => _logVitals(context),
        onCallHelpline: () => _callHelpline(context),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
            final chatPane = _ChatPane(
              args: _args,
              state: state,
              scrollController: _scrollController,
              currentUserId: widget.currentUserId,
              otherUserName: widget.otherUserName,
              otherUserAvatarUrl: widget.otherUserAvatarUrl,
              inputController: _inputController,
              inputFocus: _inputFocus,
              onRetry: () =>
                  ref.read(chatProvider(_args).notifier).refresh(),
              isDesktop: isDesktop,
              maxThreadWidth: _chatColumnMaxWidth,
              // Attachments (image + location) are appointment-scoped; the
              // multi-role conversation engine stays text-only for now.
              enableAttachments: widget.conversationId == null,
            );

            // Conversation-engine threads are multi-role / group — the
            // appointment-specific context sidebar (patient vitals /
            // assigned-doctor card) doesn't apply, so always render the
            // single-column chat pane regardless of width.
            if (!isDesktop || widget.conversationId != null) {
              return chatPane;
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 65, child: chatPane),
                Container(width: 1, color: cc.line),
                Expanded(
                  flex: 35,
                  child: _ContextSidebar(
                    role: widget.role,
                    assignedDoctor: widget.assignedDoctor,
                    patientName: widget.role == ChatRole.doctor
                        ? widget.otherUserName
                        : null,
                    patientAddress: widget.patientAddress,
                    patientPhone: widget.patientPhone,
                    careType: widget.careType,
                    vitals: widget.patientVitals,
                    onCallHelpline: () => _callHelpline(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String name;
  final String? avatarUrl;
  final String subtitle;
  final bool isConnected;
  final ChatRole role;
  final VoidCallback onLogVitals;
  final VoidCallback onCallHelpline;

  const _ChatAppBar({
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
    required this.isConnected,
    required this.role,
    required this.onLogVitals,
    required this.onCallHelpline,
  });

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    final statusLabel = isConnected
        ? (role == ChatRole.doctor ? 'Active Sync' : 'Online & Connected')
        : 'Reconnecting…';
    final statusColor = isConnected
        ? (role == ChatRole.doctor ? const Color(0xFF3B82F6) : const Color(0xFF10B981))
        : cc.ink3;

    return AppBar(
      backgroundColor: cc.surface,
      foregroundColor: cc.ink,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          _Avatar(name: name, url: avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: MtTextStyles.labelLg.copyWith(color: cc.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _PulseDot(color: statusColor, pulsing: isConnected),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusLabel,
                        style: MtTextStyles.bodySm.copyWith(
                          color: cc.ink2,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (role == ChatRole.doctor)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: _RoleActionButton(
              icon: Icons.monitor_heart_outlined,
              label: 'Log Vitals',
              onPressed: onLogVitals,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: _RoleActionButton(
              icon: Icons.support_agent,
              label: 'Call Helpline',
              onPressed: onCallHelpline,
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: cc.line),
      ),
    );
  }
}

class _RoleActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _RoleActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: MtTextStyles.labelMd),
      style: ElevatedButton.styleFrom(
        backgroundColor: cc.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulseDot({required this.color, required this.pulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 * (0.6 + 0.4 * t),
                height: 14 * (0.6 + 0.4 * t),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.25 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Chat pane (message list + floating input)
// ---------------------------------------------------------------------------

class _ChatPane extends StatelessWidget {
  final ChatArgs args;
  final ChatState state;
  final ScrollController scrollController;
  final String currentUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final TextEditingController inputController;
  final FocusNode inputFocus;
  final Future<void> Function() onRetry;
  final bool isDesktop;
  final double maxThreadWidth;
  final bool enableAttachments;

  const _ChatPane({
    required this.args,
    required this.state,
    required this.scrollController,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserAvatarUrl,
    required this.inputController,
    required this.inputFocus,
    required this.onRetry,
    required this.isDesktop,
    required this.maxThreadWidth,
    required this.enableAttachments,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _CenterConstrained(
            maxWidth: isDesktop ? maxThreadWidth : double.infinity,
            child: ChatMessageList(
              state: state,
              scrollController: scrollController,
              currentUserId: currentUserId,
              otherUserName: otherUserName,
              otherUserAvatarUrl: otherUserAvatarUrl,
              onRetry: onRetry,
            ),
          ),
        ),
        _CenterConstrained(
          maxWidth: isDesktop ? maxThreadWidth : double.infinity,
          child: state.canSendMessages
              ? ChatInputBar(
                  args: args,
                  controller: inputController,
                  focusNode: inputFocus,
                  isSending: state.isSending,
                  enableAttachments: enableAttachments,
                )
              : const ChatLockedFooter(),
        ),
      ],
    );
  }
}

class _CenterConstrained extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const _CenterConstrained({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context sidebar (desktop only)
// ---------------------------------------------------------------------------

class _ContextSidebar extends StatelessWidget {
  final ChatRole role;
  final AssignedDoctor? assignedDoctor;
  final String? patientName;
  final String? patientAddress;
  final String? patientPhone;
  final String? careType;
  final PatientVitals vitals;
  final VoidCallback onCallHelpline;

  const _ContextSidebar({
    required this.role,
    required this.assignedDoctor,
    required this.patientName,
    required this.patientAddress,
    required this.patientPhone,
    required this.careType,
    required this.vitals,
    required this.onCallHelpline,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Container(
      color: cc.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              role == ChatRole.doctor ? 'PATIENT CONTEXT' : 'CONSULTATION',
              style: MtTextStyles.sectionLabel.copyWith(
                color: cc.ink3,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            if (role == ChatRole.doctor)
              _DoctorSidebar(
                patientName: patientName ?? '—',
                careType: careType,
                vitals: vitals,
                patientAddress: patientAddress,
                patientPhone: patientPhone,
              )
            else
              _PatientSidebar(
                doctor: assignedDoctor,
                onCallHelpline: onCallHelpline,
              ),
          ],
        ),
      ),
    );
  }
}

// ----- Doctor side: vitals + address ----------------------------------------

class _DoctorSidebar extends StatelessWidget {
  final String patientName;
  final String? careType;
  final PatientVitals vitals;
  final String? patientAddress;
  final String? patientPhone;

  const _DoctorSidebar({
    required this.patientName,
    required this.careType,
    required this.vitals,
    required this.patientAddress,
    required this.patientPhone,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: patientName, url: null, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: MtTextStyles.labelLg
                              .copyWith(color: cc.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((careType ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            careType!,
                            style: MtTextStyles.bodySm
                                .copyWith(color: cc.ink2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SidebarSectionTitle(label: 'Active vitals'),
        const SizedBox(height: 8),
        VitalsGrid(vitals: vitals),
        const SizedBox(height: 18),
        _SidebarSectionTitle(label: 'Home address'),
        const SizedBox(height: 8),
        _MapPlaceholderCard(address: patientAddress),
        if ((patientPhone ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          _SidebarPrimaryButton(
            icon: Icons.phone,
            label: 'Call patient',
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: patientPhone);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ],
    );
  }
}

class _MapPlaceholderCard extends StatelessWidget {
  final String? address;
  const _MapPlaceholderCard({required this.address});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cc.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _MiniMapPainter()),
                ),
                Center(
                  child: Icon(
                    Icons.location_on,
                    color: cc.brand,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: cc.line),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: cc.ink2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (address ?? '').isEmpty
                        ? 'Address shared at dispatch.'
                        : address!,
                    style: MtTextStyles.bodySm
                        .copyWith(color: cc.ink2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final block = Paint()..color = const Color(0xFFE0E9DF);
    final street = Paint()
      ..color = const Color(0xFFF6F8F5)
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF3EE));
    final cols = [0.18, 0.52, 0.82];
    final rows = [0.25, 0.58, 0.86];
    double prevY = 0;
    for (final ry in [...rows, 1.0]) {
      double prevX = 0;
      for (final rx in [...cols, 1.0]) {
        final rect = Rect.fromLTRB(
          prevX * size.width + 4,
          prevY * size.height + 4,
          rx * size.width - 4,
          ry * size.height - 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          block,
        );
        prevX = rx;
      }
      prevY = ry;
    }
    for (final c in cols) {
      canvas.drawLine(
        Offset(c * size.width, 0),
        Offset(c * size.width, size.height),
        street,
      );
    }
    for (final r in rows) {
      canvas.drawLine(
        Offset(0, r * size.height),
        Offset(size.width, r * size.height),
        street,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ----- Patient side: doctor credentials + emergency call --------------------

class _PatientSidebar extends StatelessWidget {
  final AssignedDoctor? doctor;
  final VoidCallback onCallHelpline;
  const _PatientSidebar({required this.doctor, required this.onCallHelpline});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    final d = doctor;
    if (d == null) {
      return _SidebarCard(
        child: Text(
          'Your assigned doctor will appear here once the admin confirms the visit.',
          style: MtTextStyles.bodyMd.copyWith(color: cc.ink2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarCard(
          child: Column(
            children: [
              _Avatar(name: d.fullName, url: d.profilePicture, size: 64),
              const SizedBox(height: 10),
              Text(
                d.fullName,
                textAlign: TextAlign.center,
                style: MtTextStyles.labelLg.copyWith(color: cc.ink),
              ),
              if (d.specialty.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  d.specialty,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodySm.copyWith(color: cc.ink2),
                ),
              ],
              if (d.isVerifiedDoctor) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cc.brandSofter,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cc.brandSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          size: 14, color: cc.brand),
                      const SizedBox(width: 4),
                      Text(
                        'Verified by Taafi',
                        style: MtTextStyles.bodySm.copyWith(
                          color: cc.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if ((d.bmdcLicense ?? '').isNotEmpty)
          _SidebarKeyValue(
            label: 'BMDC LICENSE',
            value: d.bmdcLicense!,
            icon: Icons.badge_outlined,
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Experience',
                value: d.yearsExperience > 0 ? '${d.yearsExperience} yr' : '—',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'Rating',
                value: d.rating > 0 ? d.rating.toStringAsFixed(1) : '—',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'Reviews',
                value: d.reviewCount > 0 ? '${d.reviewCount}' : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if ((d.phone ?? '').isNotEmpty)
          _SidebarPrimaryButton(
            icon: Icons.phone,
            label: 'Call doctor',
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: d.phone);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        const SizedBox(height: 10),
        _SidebarSecondaryButton(
          icon: Icons.support_agent,
          label: 'Call 24/7 helpline',
          onPressed: onCallHelpline,
        ),
      ],
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final Widget child;
  const _SidebarCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cc.line),
      ),
      child: child,
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  final String label;
  const _SidebarSectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel.copyWith(
        color: cc.ink3,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _SidebarKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SidebarKeyValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cc.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cc.brandSofter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: cc.brand, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: cc.ink3,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MtTextStyles.labelMd.copyWith(color: cc.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: cc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cc.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: MtTextStyles.labelLg.copyWith(color: cc.ink),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: MtTextStyles.bodySm.copyWith(
              color: cc.ink3,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarPrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _SidebarPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: MtTextStyles.labelLg),
        style: ElevatedButton.styleFrom(
          backgroundColor: cc.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SidebarSecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _SidebarSecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: MtTextStyles.labelLg),
        style: OutlinedButton.styleFrom(
          foregroundColor: cc.brand,
          side: BorderSide(color: cc.brand),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const _Avatar({required this.name, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final cc = _ChatColors.of(context);
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

