import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/models/prescription.dart';

// ---------------------------------------------------------------------------
// Taafi prescription pad — the shared paper-document rendering of a
// prescription, used by BOTH the patient detail screen and the doctor's
// consultation-history surfaces. Pure presentational: takes a fully
// resolved (never locked) Prescription; the caller owns the release-gate
// check.
//
// The palette is deliberately a fixed light "paper" look in both light
// and dark app themes — the pad is a document artifact (matching the PDF
// export), so it renders as a white page floating on whatever background
// the host screen has. Do not swap these for MtColors / context.appColors.
// ---------------------------------------------------------------------------

const _padPaper = Colors.white;
const _padInk = Color(0xFF1F2937);
const _padInkSoft = Color(0xFF6B7280);
const _padTeal = Color(0xFF0D9488);
const _padRowAlt = Color(0xFFF1F5F9);
const _padLine = Color(0xFFE2E8F0);
// Brand wordmark colour (Taafi sunset orange). The rest of the pad stays
// teal-accented; only the "Taafi" mark uses this.
const _padBrand = Color(0xFFF36512);

/// Platform tagline printed under the brand name on the pad header.
const kTaafiTagline = 'জ্যাম আর সিরিয়ালকে বিদায়, চিকিৎসা এখন আপনার দরজায়।';

class PrescriptionPadWidget extends StatelessWidget {
  final Prescription prescription;

  /// Tighter paddings for bottom-sheet embeds (doctor history).
  final bool compact;

  const PrescriptionPadWidget({
    super.key,
    required this.prescription,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    if (p.locked) {
      // Defence in depth — callers should gate before embedding the pad.
      return const SizedBox.shrink();
    }
    final pad = compact ? 16.0 : 20.0;
    return Material(
      color: _padPaper,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(prescription: p),
            const SizedBox(height: 10),
            // Sharp divider separating credentials from the clinical body.
            Container(height: 1.5, color: Colors.black87),
            const SizedBox(height: 12),
            if (p.patientSnapshot != null && !p.patientSnapshot!.isEmpty) ...[
              _PatientBlock(snapshot: p.patientSnapshot!),
              const SizedBox(height: 10),
            ],
            _VitalsBar(prescription: p),
            SizedBox(height: compact ? 10 : 16),
            const _RxSymbol(),
            const SizedBox(height: 6),
            _MedicationsTable(items: p.items),
            SizedBox(height: compact ? 12 : 18),
            _Footer(prescription: p),
          ],
        ),
      ),
    );
  }
}

// ── Header: doctor credentials (left) · Taafi brand + tagline (right) ──

class _Header extends StatelessWidget {
  final Prescription prescription;
  const _Header({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final name = p.padDoctorName.isEmpty ? 'Doctor' : p.padDoctorName;
    final credentialLines = <Widget>[
      Text(
        name.startsWith('Dr') ? name : 'Dr. $name',
        style: const TextStyle(
          color: _padInk,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      if (p.padDegrees.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            p.padDegrees,
            style: const TextStyle(
              color: _padInkSoft,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      if (p.padHospitalOrCollege.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            p.padHospitalOrCollege,
            style: const TextStyle(
              color: _padInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      if (p.padRegistrationNumber.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'BMDC Reg. No: ${p.padRegistrationNumber}',
            style: const TextStyle(
              color: _padInkSoft,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
        ),
      if (p.padEmail.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            p.padEmail,
            style: const TextStyle(
              color: _padInkSoft,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: credentialLines,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            Text(
              'Taafi',
              style: TextStyle(
                color: _padBrand,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 2),
            Text(
              kTaafiTagline,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _padInkSoft,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Patient identity block (target patient / family-member bookings) ──

class _PatientBlock extends StatelessWidget {
  final PatientSnapshot snapshot;
  const _PatientBlock({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final meta = [
      if (s.ageSexLine.isNotEmpty) s.ageSexLine,
      if (s.relationship.isNotEmpty)
        s.relationship[0].toUpperCase() + s.relationship.substring(1),
    ].join('   ·   ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text(
          'Patient: ',
          style: TextStyle(
            color: _padInkSoft,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: s.name,
                  style: const TextStyle(
                    color: _padInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (meta.isNotEmpty)
                  TextSpan(
                    text: '   $meta',
                    style: const TextStyle(
                      color: _padInkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Vitals metadata bar: Date · Diagnosis · Weight · Height · BP ──

class _VitalsBar extends StatelessWidget {
  final Prescription prescription;
  const _VitalsBar({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final v = p.vitalsSnapshot;
    final entries = <MapEntry<String, String>>[
      MapEntry('Date', DateFormat('d MMM y').format(p.issuedAt)),
      if (p.diagnosis.isNotEmpty) MapEntry('Diagnosis', p.diagnosis),
      if (v?.weightKg != null)
        MapEntry('Weight', '${_trimNum(v!.weightKg!)} kg'),
      if (v?.heightCm != null)
        MapEntry('Height', '${_trimNum(v!.heightCm!)} cm'),
      if ((v?.bloodPressure ?? '').isNotEmpty) MapEntry('BP', v!.bloodPressure),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _padRowAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final e in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${e.key}: ',
                  style: const TextStyle(
                    color: _padInkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  e.value,
                  style: const TextStyle(
                    color: _padInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _trimNum(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
}

// ── The classic big bold italic Rx symbol opening the table frame ──

class _RxSymbol extends StatelessWidget {
  const _RxSymbol();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Rx',
        style: TextStyle(
          color: _padTeal,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          height: 1.0,
        ),
      ),
    );
  }
}

// ── Structured medications grid ──

class _MedicationsTable extends StatelessWidget {
  final List<PrescriptionItem> items;
  const _MedicationsTable({required this.items});

  static const _headerStyle = TextStyle(
    color: _padInkSoft,
    fontSize: 9.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.0,
  );

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(5),
        1: FlexColumnWidth(3.4),
        2: FlexColumnWidth(2.2),
      },
      border: const TableBorder(
        top: BorderSide(color: _padLine),
        bottom: BorderSide(color: _padLine),
        horizontalInside: BorderSide(color: _padLine, width: 0.6),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            _Cell(child: Text('MEDICINE', style: _headerStyle)),
            _Cell(child: Text('DOSAGE', style: _headerStyle)),
            _Cell(child: Text('DURATION', style: _headerStyle)),
          ],
        ),
        for (var i = 0; i < items.length; i++)
          TableRow(
            decoration: i.isOdd ? const BoxDecoration(color: _padRowAlt) : null,
            children: [
              _Cell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].displayName,
                      style: const TextStyle(
                        color: _padInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (items[i].notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          items[i].notes,
                          style: const TextStyle(
                            color: _padInkSoft,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _Cell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items[i].dosage} — ${items[i].frequencyCode}',
                      style: const TextStyle(
                        color: _padInk,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      _mealLabel(items[i].mealContext),
                      style: const TextStyle(
                        color: _padInkSoft,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              _Cell(
                child: Text(
                  '${items[i].durationDays} days',
                  style: const TextStyle(
                    color: _padInk,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // Pad instruction wording for the 3-state backend meal enum.
  static String _mealLabel(MealContext m) {
    switch (m) {
      case MealContext.before:
        return 'Before Meal';
      case MealContext.after:
        return 'After Meal';
      case MealContext.either:
        return 'With/Without Meal';
    }
  }
}

class _Cell extends StatelessWidget {
  final Widget child;
  const _Cell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: child,
    );
  }
}

// ── Footer: advice · follow-up · digital signature baseline ──

class _Footer extends StatelessWidget {
  final Prescription prescription;
  const _Footer({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final name = p.padDoctorName.isEmpty ? 'Doctor' : p.padDoctorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.advice.isNotEmpty) ...[
          const _FooterLabel('ADVICE GIVEN'),
          const SizedBox(height: 3),
          Text(
            p.advice,
            style: const TextStyle(
              color: _padInk,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (p.followUpDate != null) ...[
          const _FooterLabel('FOLLOW-UP'),
          const SizedBox(height: 3),
          Text(
            DateFormat('EEEE, d MMMM y').format(p.followUpDate!),
            style: const TextStyle(
              color: _padInk,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Script font for the signature execution line. google_fonts
              // resolves at runtime and silently falls back to the system
              // font when offline — no crash path.
              Text(
                name,
                style: GoogleFonts.dancingScript(
                  color: _padInk,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                width: 150,
                height: 1,
                margin: const EdgeInsets.only(top: 2, bottom: 3),
                color: _padInkSoft,
              ),
              const Text(
                'Digital Signature',
                style: TextStyle(
                  color: _padInkSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterLabel extends StatelessWidget {
  final String text;
  const _FooterLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _padTeal,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    );
  }
}

/// Grab-handle tint exposed for the sheet host in
/// prescription_pad_actions.dart (which owns showPrescriptionPadSheet).
const kPadLineColor = _padLine;
