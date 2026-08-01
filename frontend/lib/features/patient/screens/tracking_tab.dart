import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/models/assigned_doctor.dart';
import '../../../core/models/assigned_nurse.dart';
import '../../../core/models/patient_active_request.dart';
import '../../../core/models/patient_request_status.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/whatsapp_support.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/whatsapp_support_button.dart';
import '../navigation/patient_nav_provider.dart';
import 'view_assigned_doctor_screen.dart';
import 'widgets/payment_method_choice_card.dart';

/// Patient tracking tab. Driven by [patientActiveRequestProvider] which
/// auto-polls every 10s — once the admin assigns a doctor, the populated
/// `doctor` block arrives on the next tick and the bottom sheet swaps
/// from the "Assigning Doctor" panel to the live "Your Doctor is Assigned"
/// card without any user action.
class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(patientActiveRequestProvider);
    // The bottom sheet grows when the patient expands "Cash on Service"
    // (Total Fee / Deposit Paid / Cash Due at Door + confirm). Inside the
    // fixed-height TabBarView slot that used to overflow the plain Column, so
    // make the tab fill-or-scroll: fill the viewport when content fits (the
    // map keeps filling the space above the pinned sheet, unchanged look) and
    // scroll once the priced cash breakdown pushes past the available height.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      // Keep the map readable in the scroll case, where
                      // IntrinsicHeight would otherwise collapse it to the dots.
                      constraints: BoxConstraints(minHeight: 240),
                      child: _MapArea(),
                    ),
                  ),
                  _BottomSheet(request: request),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- Map --------------------------------------------------------------------

class _MapArea extends ConsumerWidget {
  const _MapArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _MapPainter()),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: _CircularIconButton(
            icon: Icons.arrow_back,
            // Bottom-nav now drives this — back-out of Tracking
            // lands on the Home destination.
            onTap: ref.goToHome,
          ),
        ),
        const Positioned(top: 16, right: 16, child: _EtaPill()),
        const Align(
          alignment: Alignment(-0.74, 0.7),
          child: _OriginDot(),
        ),
        const Align(
          alignment: Alignment(0.0, -0.05),
          child: _DoctorPin(),
        ),
        const Align(
          alignment: Alignment(0.7, -0.68),
          child: _DestinationDot(),
        ),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  static const _bg = Color(0xFFEEF3EE);
  static const _block = Color(0xFFE0E9DF);
  static const _street = Color(0xFFF6F8F5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final blockPaint = Paint()..color = _block;
    final streetPaint = Paint()
      ..color = _street
      ..strokeWidth = 1;

    final vStreets = [0.13, 0.5, 0.85];
    final hStreets = [0.18, 0.45, 0.72];
    const streetW = 14.0;

    double prevY = 0;
    for (final yf in [...hStreets, 1.0]) {
      final y = yf * h;
      double prevX = 0;
      for (final xf in [...vStreets, 1.0]) {
        final x = xf * w;
        final rect = Rect.fromLTRB(
          prevX + (prevX == 0 ? 0 : streetW / 2),
          prevY + (prevY == 0 ? 0 : streetW / 2),
          x - (xf == 1.0 ? 0 : streetW / 2),
          y - (yf == 1.0 ? 0 : streetW / 2),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          blockPaint,
        );
        prevX = x;
      }
      prevY = y;
    }

    for (final xf in vStreets) {
      canvas.drawLine(Offset(xf * w, 0), Offset(xf * w, h), streetPaint);
    }
    for (final yf in hStreets) {
      canvas.drawLine(Offset(0, yf * h), Offset(w, yf * h), streetPaint);
    }

    final routePaint = Paint()
      ..color = MtColors.brand
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double xf, double yf) => Offset(xf * w, yf * h);

    final path = Path()
      ..moveTo(p(0.13, 0.85).dx, p(0.13, 0.85).dy)
      ..lineTo(p(0.13, 0.45).dx, p(0.13, 0.45).dy)
      ..lineTo(p(0.5, 0.45).dx, p(0.5, 0.45).dy)
      ..lineTo(p(0.5, 0.18).dx, p(0.5, 0.18).dy)
      ..lineTo(p(0.85, 0.18).dx, p(0.85, 0.18).dy);
    canvas.drawPath(path, routePaint);

    final trailPaint = Paint()
      ..color = MtColors.brandSoft
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trailPath = Path()
      ..moveTo(p(0.5, 0.45).dx, p(0.5, 0.45).dy)
      ..lineTo(p(0.5, 0.18).dx, p(0.5, 0.18).dy)
      ..lineTo(p(0.85, 0.18).dx, p(0.85, 0.18).dy);
    canvas.drawPath(trailPath, trailPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircularIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: MtColors.ink, size: 20),
        ),
      ),
    );
  }
}

class _EtaPill extends StatelessWidget {
  const _EtaPill();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF3B82F6),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ETA',
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  '12 min',
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OriginDot extends StatelessWidget {
  const _OriginDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: MtColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: MtColors.ink, width: 3),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: MtColors.ink,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _DestinationDot extends StatelessWidget {
  const _DestinationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: MtColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: MtColors.surface, width: 2),
      ),
    );
  }
}

class _DoctorPin extends StatelessWidget {
  const _DoctorPin();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const InitialsAvatar(
              name: 'Doctor',
              size: 28,
              backgroundColor: MtColors.brand,
              textColor: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              'Dr.',
              style: MtTextStyles.labelMd.copyWith(color: MtColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Bottom sheet -----------------------------------------------------------

class _BottomSheet extends StatelessWidget {
  final PatientActiveRequest? request;
  const _BottomSheet({required this.request});

  bool get _hasDoctor {
    final r = request;
    if (r == null) return false;
    if (r.assignedDoctor != null) return true;
    // Defensive fallback: if the legacy `providerName` is filled in but
    // the new populate didn't run, still treat the request as assigned
    // so the UI doesn't get stuck in the pending panel. Skip this when a
    // nurse is on the visit (the provider name may be the nurse's).
    return r.assignedNurse == null &&
        r.status != PatientRequestStatus.pendingReview &&
        (r.providerName?.isNotEmpty ?? false);
  }

  bool get _hasNurse => request?.assignedNurse != null;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SERVICE STATUS',
                    style: MtTextStyles.sectionLabel.copyWith(
                      color: c.brand,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (request != null)
                    Text(
                      '#${request!.id.isNotEmpty ? request!.id.substring(request!.id.length > 6 ? request!.id.length - 6 : 0).toUpperCase() : 'MT-4827'}',
                      style: MtTextStyles.bodySm.copyWith(color: c.muted),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressSegments(
                status: request?.status ?? PatientRequestStatus.pendingReview,
              ),
              const SizedBox(height: 14),
              // Doctor: show the assigned card, or the "assigning" placeholder
              // only when no provider of any kind is on the visit yet.
              if (_hasDoctor)
                _AssignedDoctorPanel(
                  request: request!,
                  doctor: request!.assignedDoctor,
                )
              else if (!_hasNurse)
                const _AssigningDoctorPanel(),
              // Nurse: a home visit can carry a nurse in addition to (or
              // instead of) a doctor. Render the nurse card whenever assigned.
              if (_hasNurse) ...[
                if (_hasDoctor) const SizedBox(height: 16),
                _AssignedNursePanel(nurse: request!.assignedNurse!),
              ],
              // Balance-payment pre-commitment: once the visit is priced and
              // a provider is dispatched, let the patient choose Cash on
              // Service vs Digital before the service wraps up.
              if (request != null &&
                  PaymentMethodChoiceCard.shouldShow(request!))
                PaymentMethodChoiceCard(request: request!),
              // Primary support action for the live visit. Opens WhatsApp with
              // the booking id + service title pre-filled, so support has the
              // context immediately — this replaced the in-app chat thread.
              if (request != null && request!.status.isActive) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: WhatsAppSupportButton(
                    label: 'WhatsApp Support',
                    message: bookingWhatsAppMessage(
                      bookingId: request!.id,
                      serviceTitle: request!.serviceTitleEn,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Top half of the assigned state: the "Your Doctor is Assigned" headline,
/// the thumbnail + name + specialty card, and the View Profile / Call CTA
/// row. Tapping View Profile opens the read-only doctor profile sheet.
class _AssignedDoctorPanel extends StatelessWidget {
  final PatientActiveRequest request;
  final AssignedDoctor? doctor;
  const _AssignedDoctorPanel({required this.request, this.doctor});

  String get _name =>
      doctor?.fullName ?? request.providerName ?? 'Your assigned doctor';
  String get _specialty =>
      doctor?.specialty ?? request.providerSpecialization ?? '';
  String? get _photo => doctor?.profilePicture ?? request.providerAvatarUrl;
  int? get _years =>
      doctor != null && doctor!.yearsExperience > 0 ? doctor!.yearsExperience : null;
  double? get _rating =>
      doctor != null && doctor!.rating > 0 ? doctor!.rating : null;

  void _openProfile(BuildContext context) {
    final d = doctor;
    if (d == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewAssignedDoctorScreen(
          doctor: d,
          appointmentId: request.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Doctor is Assigned',
          style: MtTextStyles.h2.copyWith(color: c.title),
        ),
        const SizedBox(height: 4),
        Text(
          "Tap View Profile to see credentials, or call directly when needed.",
          style: MtTextStyles.bodyMd.copyWith(color: c.body),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.brand.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DoctorThumbnail(
                photoUrl: _photo,
                fallbackName: _name,
                verified: doctor?.isVerifiedDoctor ?? false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _name,
                            style: MtTextStyles.labelLg
                                .copyWith(color: c.title),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (doctor?.isVerifiedDoctor ?? false) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: c.brand,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (_specialty.isNotEmpty)
                      Text(
                        _specialty,
                        style: MtTextStyles.bodySm.copyWith(color: c.body),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (_rating != null) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: c.warning,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _rating!.toStringAsFixed(1),
                            style: MtTextStyles.bodySm
                                .copyWith(color: c.title),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (_years != null)
                          Text(
                            '$_years yr exp',
                            style: MtTextStyles.bodySm
                                .copyWith(color: c.body),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    doctor == null ? null : () => _openProfile(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.brand,
                  side: BorderSide(color: c.brand),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('View Profile'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Assigned-nurse counterpart to [_AssignedDoctorPanel]. Home visits are
/// often nurse-led (lab collection, dressing, IV), so the patient sees who
/// is coming — name, qualifications, BNMC registration, and institute — plus
/// a direct Call CTA.
class _AssignedNursePanel extends StatelessWidget {
  final AssignedNurse nurse;
  const _AssignedNursePanel({required this.nurse});

  Future<void> _call(BuildContext context) async {
    final phone = nurse.phone;
    if (phone == null || phone.trim().isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final quals = nurse.qualifications;
    final institute = nurse.hospitalAffiliation;
    final bnmc = nurse.nursingLicense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Nurse is Assigned',
            style: MtTextStyles.h2.copyWith(color: c.title)),
        const SizedBox(height: 4),
        Text(
          'A qualified home-care nurse will handle your visit.',
          style: MtTextStyles.bodyMd.copyWith(color: c.body),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.info.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(
                name: nurse.fullName,
                size: 52,
                backgroundColor: c.infoBg,
                textColor: c.info,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nurse.fullName,
                            style: MtTextStyles.labelLg
                                .copyWith(color: c.title),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (nurse.isVerifiedNurse) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.verified, size: 16, color: c.info),
                        ],
                      ],
                    ),
                    if (quals != null && quals.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(quals,
                          style: MtTextStyles.bodySm.copyWith(color: c.body)),
                    ],
                    if (institute != null && institute.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NurseMetaRow(
                          icon: Icons.local_hospital_outlined,
                          text: institute,
                          color: c.muted),
                    ],
                    if (bnmc != null && bnmc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _NurseMetaRow(
                          icon: Icons.badge_outlined,
                          text: 'BNMC $bnmc',
                          color: c.muted),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Direct line to the nurse. Anything else (reschedule, complaint,
        // billing) goes through the sheet's WhatsApp Support button below,
        // which replaced the old in-app chat drawer.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                (nurse.phone?.isNotEmpty ?? false) ? () => _call(context) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.info,
              side: BorderSide(color: c.info),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.phone_outlined, size: 18),
            label: const Text('Call Nurse'),
          ),
        ),
      ],
    );
  }
}

class _NurseMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _NurseMetaRow(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text,
              style: MtTextStyles.bodySm.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _DoctorThumbnail extends StatelessWidget {
  final String? photoUrl;
  final String fallbackName;
  final bool verified;
  const _DoctorThumbnail({
    required this.photoUrl,
    required this.fallbackName,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final url = photoUrl;
    Widget avatar;
    if (url != null && url.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          url,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: fallbackName.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), ''),
            size: 56,
            backgroundColor: c.brand,
            textColor: c.onAccent,
          ),
        ),
      );
    } else {
      avatar = InitialsAvatar(
        name: fallbackName.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), ''),
        size: 56,
        backgroundColor: c.brand,
        textColor: c.onAccent,
      );
    }
    if (!verified) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified,
              size: 14,
              color: c.brand,
            ),
          ),
        ),
      ],
    );
  }
}

/// Rendered while the admin is still picking a doctor for the request.
class _AssigningDoctorPanel extends StatelessWidget {
  const _AssigningDoctorPanel();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assigning Doctor',
          style: MtTextStyles.h2.copyWith(color: c.title),
        ),
        const SizedBox(height: 4),
        Text(
          'Our admin team is matching the best available doctor for your request. This usually takes only a few minutes.',
          style: MtTextStyles.bodyMd.copyWith(color: c.body),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.brand.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(c.brand),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Looking for the right specialist…',
                      style: MtTextStyles.labelLg.copyWith(color: c.title),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "We'll notify you as soon as a doctor accepts.",
                      style: MtTextStyles.bodySm.copyWith(color: c.body),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressSegments extends StatelessWidget {
  final PatientRequestStatus status;
  const _ProgressSegments({required this.status});

  static const _labels = ['Pending', 'En route', 'Arrived', 'In service'];

  /// Maps the live CareRequest status onto the four dispatch milestones:
  /// Pending Assignment → Provider En Route → Provider Arrived → In Service.
  /// `accepted` (a doctor is assigned but not yet moving) still reads as
  /// "Pending" here — the assigned-doctor panel below surfaces that detail.
  int get _activeIndex {
    switch (status) {
      case PatientRequestStatus.pendingReview:
      case PatientRequestStatus.accepted:
        return 0;
      case PatientRequestStatus.enRoute:
        return 1;
      case PatientRequestStatus.arrived:
        return 2;
      case PatientRequestStatus.inService:
      case PatientRequestStatus.completed:
        return 3;
      case PatientRequestStatus.rejected:
      case PatientRequestStatus.cancelled:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeIndex;
    final c = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int i = 0; i < _labels.length; i++) ...[
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= activeIndex ? c.brand : c.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i != _labels.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 0; i < _labels.length; i++)
              Expanded(
                child: Text(
                  _labels[i],
                  style: MtTextStyles.bodySm.copyWith(
                    color: i == activeIndex ? c.title : c.muted,
                    fontWeight: i == activeIndex
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
