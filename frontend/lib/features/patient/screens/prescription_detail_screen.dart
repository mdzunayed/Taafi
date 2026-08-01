import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/models/prescription.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../prescriptions/prescription_download_provider.dart';
import '../../prescriptions/prescription_pad_actions.dart';
import '../../prescriptions/prescription_pad_widget.dart' show kTaafiTagline;
import '../../prescriptions/prescription_release_gate.dart';
import '../../prescriptions/prescriptions_provider.dart';
import 'booking_flow_pages.dart' show runBalancePayment;

const List<DoseSlot> _slotOrder = [
  DoseSlot.morning,
  DoseSlot.afternoon,
  DoseSlot.night,
];

String _freqLabel(PrescriptionItem it) {
  final parts = [
    for (final s in _slotOrder)
      if (it.frequency.contains(s)) s.labelEn,
  ];
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// Typeset digital prescription card. Renders the issuing doctor's verified
/// credentials, diagnosis + symptoms, and an itemized Rx table. Offers a PDF
/// export (print/share) and a high-contrast "Pharmacy Scan View".
class PrescriptionDetailScreen extends ConsumerStatefulWidget {
  final String prescriptionId;
  const PrescriptionDetailScreen({super.key, required this.prescriptionId});

  @override
  ConsumerState<PrescriptionDetailScreen> createState() =>
      _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState
    extends ConsumerState<PrescriptionDetailScreen> {
  bool _scanView = false;
  bool _generatingPdf = false;
  bool _payingBalance = false;
  StreamSubscription<Map<String, dynamic>>? _releaseSub;

  @override
  void initState() {
    super.initState();
    // Live unlock: when the admin decides on this script the backend
    // emits `prescription:release_updated` to the patient's user room —
    // re-fetch so the gate card flips (or the full script appears)
    // without a manual refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _releaseSub = ref
          .read(socketManagerProvider)
          ?.onPrescriptionRelease
          .listen((event) {
        if (!mounted) return;
        if ((event['prescriptionId'] ?? '').toString() ==
            widget.prescriptionId) {
          ref.invalidate(prescriptionDetailProvider(widget.prescriptionId));
        }
      });
    });
  }

  @override
  void dispose() {
    _releaseSub?.cancel();
    super.dispose();
  }

  Future<void> _downloadPdf(Prescription p) async {
    if (_generatingPdf) return;
    HapticFeedback.lightImpact();
    setState(() => _generatingPdf = true);
    try {
      await Printing.layoutPdf(
        name: 'prescription_${p.id}.pdf',
        onLayout: (format) => _buildPdf(p, format),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content: Text("Couldn't generate the PDF: $e"),
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the autoDispose socket alive while this screen is mounted so
    // the initState release-update subscription actually receives events.
    ref.watch(socketManagerProvider);
    final async = ref.watch(prescriptionDetailProvider(widget.prescriptionId));

    return Scaffold(
      backgroundColor: _scanView ? Colors.white : MtColors.bg,
      appBar: AppBar(
        backgroundColor: _scanView ? Colors.white : MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(_scanView ? 'Pharmacy Scan View' : 'Prescription',
            style: MtTextStyles.h3.copyWith(
                color: _scanView ? Colors.black : MtColors.ink)),
        actions: [
          async.maybeWhen(
            // The scan view exposes the full Rx table — locked scripts
            // never get the toggle (their items are server-redacted
            // anyway; this is defence in depth).
            data: (p) => p.locked
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: _scanView ? 'Exit scan view' : 'Pharmacy scan view',
                    icon: Icon(
                      _scanView ? Icons.close_fullscreen : Icons.zoom_out_map,
                      color: _scanView ? Colors.black : MtColors.ink2,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _scanView = !_scanView);
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: MtColors.brand)),
        error: (e, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MtErrorState(
            title: "Couldn't load prescription",
            message: e.toString(),
            onRetry: () => ref.invalidate(
                prescriptionDetailProvider(widget.prescriptionId)),
          ),
        ),
        data: (p) => p.locked
            ? _buildLockedGate(p)
            : (_scanView ? _ScanView(script: p) : _buildDetail(p)),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (p) => (_scanView || p.locked)
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: MtButton(
                        label: 'Scan View',
                        isOutlined: true,
                        leadingIcon: Icons.zoom_out_map,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _scanView = true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MtButton(
                        label: 'Download PDF',
                        leadingIcon: Icons.picture_as_pdf_outlined,
                        // Web keeps the client-side Printing export (no
                        // documents dir / native viewer there); native
                        // pulls the server-rendered A4 PDF and hands it
                        // to the OS viewer.
                        isLoading: kIsWeb
                            ? _generatingPdf
                            : ref
                                .watch(prescriptionDownloadProvider(p.id))
                                .isDownloading,
                        onPressed: () => kIsWeb
                            ? _downloadPdf(p)
                            : ref
                                .read(
                                    prescriptionDownloadProvider(p.id).notifier)
                                .downloadAndOpen(),
                      ),
                    ),
                  ],
                ),
              ),
        orElse: () => null,
      ),
    );
  }

  Widget _buildDetail(Prescription p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // The shared paper-document rendering — the same pad the doctor
        // sees in their consultation history — plus the download action
        // layer (server PDF on native, client Printing export on web).
        DownloadablePrescriptionPad(
          prescription: p,
          webFallback: () => _downloadPdf(p),
        ),
        if (p.symptoms.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Reported symptoms',
            icon: Icons.sick_outlined,
            child: Text(
              p.symptoms,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
            ),
          ),
        ],
      ],
    );
  }

  // ── Release gate (locked script) ───────────────────────────────────────────

  /// Rendered instead of the Rx detail while the server keeps the script
  /// redacted. Which card shows is decided purely by `releaseStatus` —
  /// the client never re-derives the gate.
  Widget _buildLockedGate(Prescription p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _CredentialsHeader(script: p),
        const SizedBox(height: 16),
        PrescriptionReleaseGateCard(
          script: p,
          onRefresh: () => ref
              .invalidate(prescriptionDetailProvider(widget.prescriptionId)),
          onPay: () => _startUnlockPayment(p),
        ),
      ],
    );
  }

  /// The prescription is paid for by settling the BOOKING's outstanding
  /// service balance — there is no per-prescription fee. Reuses the same
  /// init → gateway/simulated → confirm runner as the booking surface;
  /// the backend flips the script to PAID as part of the settlement.
  Future<void> _startUnlockPayment(Prescription p) async {
    if (_payingBalance) return;
    HapticFeedback.lightImpact();
    setState(() => _payingBalance = true);
    try {
      await runBalancePayment(ref, p.appointmentId);
      if (!mounted) return;
      ref.invalidate(prescriptionDetailProvider(widget.prescriptionId));
      ref.invalidate(patientPrescriptionsProvider);
      ref.invalidate(medicationsHubProvider);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content:
              Text(raw.length > 160 ? '${raw.substring(0, 160)}…' : raw),
        ),
      );
    } finally {
      if (mounted) setState(() => _payingBalance = false);
    }
  }

  // ── PDF document ───────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf(Prescription p, PdfPageFormat format) async {
    final doc = pw.Document();
    final date = DateFormat('d MMMM y').format(p.issuedAt);
    final teal = PdfColor.fromInt(0xFF0D9488);
    final ink = PdfColor.fromInt(0xFF111827);
    final ink3 = PdfColor.fromInt(0xFF6B7280);
    // Taafi brand wordmark (sunset orange); header rule uses ink.
    final brand = PdfColor.fromInt(0xFFF36512);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text('$k: $v',
              style: pw.TextStyle(fontSize: 10, color: ink3)),
        );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1.5)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        p.padDoctorName.isEmpty
                            ? 'Attending Physician'
                            : p.padDoctorName,
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: ink),
                      ),
                      if (p.padDegrees.isNotEmpty)
                        pw.Text(p.padDegrees,
                            style: pw.TextStyle(fontSize: 10, color: ink3)),
                      if (p.padHospitalOrCollege.isNotEmpty)
                        pw.Text(p.padHospitalOrCollege,
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: ink)),
                      if (p.padRegistrationNumber.isNotEmpty)
                        pw.Text('BMDC Reg: ${p.padRegistrationNumber}',
                            style: pw.TextStyle(fontSize: 10, color: ink3)),
                      if (p.padEmail.isNotEmpty)
                        pw.Text(p.padEmail,
                            style: pw.TextStyle(fontSize: 10, color: ink3)),
                      if (p.doctorVerified)
                        pw.Text('BMDC Verified',
                            style: pw.TextStyle(fontSize: 9, color: teal)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Taafi',
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: brand)),
                      pw.Text(kTaafiTagline,
                          style: pw.TextStyle(fontSize: 8, color: ink3)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            kv('Diagnosis', p.diagnosis.isEmpty ? 'Not recorded' : p.diagnosis),
            if (p.symptoms.trim().isNotEmpty) kv('Symptoms', p.symptoms),
            kv('Issued', date),
            if (p.vitalsSnapshot != null && !p.vitalsSnapshot!.isEmpty)
              kv('Vitals', [
                if (p.vitalsSnapshot!.weightKg != null)
                  'Weight ${p.vitalsSnapshot!.weightKg} kg',
                if (p.vitalsSnapshot!.heightCm != null)
                  'Height ${p.vitalsSnapshot!.heightCm} cm',
                if (p.vitalsSnapshot!.bloodPressure.isNotEmpty)
                  'BP ${p.vitalsSnapshot!.bloodPressure}',
              ].join(' · ')),
            pw.SizedBox(height: 14),
            pw.Text('Rx',
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: teal)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromInt(0xFFD1D5DB), width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(3),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
                  children: [
                    _pdfCell('Drug', bold: true),
                    _pdfCell('Dosage', bold: true),
                    _pdfCell('Frequency', bold: true),
                    _pdfCell('Meal', bold: true),
                    _pdfCell('Duration', bold: true),
                  ],
                ),
                for (final it in p.items)
                  pw.TableRow(children: [
                    _pdfCell(it.displayName),
                    _pdfCell(it.dosage),
                    _pdfCell(_freqLabel(it)),
                    _pdfCell(it.mealContext.labelEn),
                    _pdfCell('${it.durationDays} days'),
                  ]),
              ],
            ),
            if (p.advice.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('ADVICE GIVEN',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: teal)),
              pw.SizedBox(height: 3),
              pw.Text(p.advice,
                  style: pw.TextStyle(fontSize: 10, color: ink)),
            ],
            if (p.followUpDate != null) ...[
              pw.SizedBox(height: 10),
              pw.Text('FOLLOW-UP',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: teal)),
              pw.SizedBox(height: 3),
              pw.Text(DateFormat('EEEE, d MMMM y').format(p.followUpDate!),
                  style: pw.TextStyle(fontSize: 10, color: ink)),
            ],
            pw.Spacer(),
            pw.SizedBox(height: 30),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: ink3)),
              ),
              child: pw.Text(
                p.padDoctorName.isEmpty
                    ? 'Authorised digital signature'
                    : '${p.padDoctorName} · Digital signature',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: ink3,
                    fontStyle: pw.FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          text.isEmpty ? '—' : text,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
}

// ─── Credentials header ──────────────────────────────────────────────────────

class _CredentialsHeader extends StatelessWidget {
  final Prescription script;
  const _CredentialsHeader({required this.script});

  static const _teal = Color(0xFF0D9488);
  static const _tealSoft = Color(0xFFCCFBF1);

  @override
  Widget build(BuildContext context) {
    final verified = script.doctorVerified;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_hospital_outlined,
                    color: _teal, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.doctorName.isEmpty
                          ? 'Attending physician'
                          : script.doctorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                    ),
                    if (script.doctorSpecialization.isNotEmpty)
                      Text(script.doctorSpecialization,
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (script.doctorBmdc.isNotEmpty) ...[
                const Icon(Icons.badge_outlined, size: 15, color: MtColors.ink3),
                const SizedBox(width: 4),
                Text('BMDC: ${script.doctorBmdc}',
                    style:
                        MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
                const SizedBox(width: 12),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: verified ? _tealSoft : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      verified
                          ? Icons.verified_rounded
                          : Icons.pending_outlined,
                      size: 13,
                      color: verified ? _teal : const Color(0xFFB45309),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      verified ? 'BMDC Verified' : 'Verification pending',
                      style: MtTextStyles.labelSm.copyWith(
                        color: verified ? _teal : const Color(0xFFB45309),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: MtColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MtColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  script.doctorName.isEmpty
                      ? 'Authorised physician'
                      : script.doctorName,
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Digital signature',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section + Rx row ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: MtColors.brand),
              const SizedBox(width: 6),
              Text(title.toUpperCase(),
                  style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ─── Pharmacy scan view (high-contrast, large text) ──────────────────────────

class _ScanView extends StatelessWidget {
  final Prescription script;
  const _ScanView({required this.script});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            script.doctorName.isEmpty ? 'Prescription' : script.doctorName,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          if (script.doctorBmdc.isNotEmpty)
            Text('BMDC: ${script.doctorBmdc}',
                style: const TextStyle(fontSize: 18, color: Colors.black87)),
          const Divider(height: 28, thickness: 2, color: Colors.black),
          if (script.diagnosis.isNotEmpty) ...[
            const Text('Diagnosis',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            Text(script.diagnosis,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black)),
            const SizedBox(height: 20),
          ],
          const Text('Medications',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          for (final it in script.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${it.drugName}  —  ${it.dosage}',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                  const SizedBox(height: 2),
                  Text(
                    '${_freqLabel(it)} · ${it.mealContext.labelEn} · ${it.durationDays} days',
                    style: const TextStyle(
                        fontSize: 20, color: Colors.black87),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
