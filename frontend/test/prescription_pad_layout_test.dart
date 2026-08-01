import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/models/prescription.dart';
import 'package:taafi/features/prescriptions/prescription_pad_widget.dart';

// Layout regression guard for the prescription pad. The pad is a fixed
// "paper" document rendered inside whatever width the host screen has,
// and its header + medication table were previously sized so that on a
// phone the credentials column collapsed ("Rahman" broke one letter per
// line) and the table's third heading rendered as "DURATIO" / "N".
//
// The test font in flutter_test lays out every glyph at the full font
// size, so these widths are a harsher case than a real device — a pass
// here means the real rendering has headroom.

Prescription _script({
  String diagnosis = 'Post-surgical recovery',
  PatientSnapshot? patient = const PatientSnapshot(
    name: 'Zunayed',
    age: 24,
    gender: 'male',
    bloodGroup: 'O+',
    relationship: 'other',
  ),
  String patientName = '',
}) =>
    Prescription(
      id: 'p1',
      appointmentId: 'a1',
      patientAccountId: 'acc1',
      doctorName: 'Nafisa Rahman',
      diagnosis: diagnosis,
      issuedAt: DateTime(2026, 7, 31),
      doctorSnapshot: const DoctorSnapshot(
        name: 'Nafisa Rahman',
        degrees: 'MBBS, FCPS',
        hospitalOrCollege: 'BSMMU',
        email: 'drnafisa@taafi.app',
        registrationNumber: '54123',
      ),
      patientSnapshot: patient,
      patientName: patientName,
      vitalsSnapshot: const VitalsSnapshot(weightKg: 55, heightCm: 170),
      items: const [
        PrescriptionItem(
          form: MedicationForm.cap,
          drugName: 'sergel',
          dosage: '20 mg',
          frequency: {DoseSlot.morning, DoseSlot.night},
          mealContext: MealContext.before,
          durationDays: 30,
        ),
      ],
    );

Future<void> _pumpPad(
  WidgetTester tester,
  Prescription script,
  double width,
) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [PrescriptionPadWidget(prescription: script)],
      ),
    ),
  ));
}

/// No paragraph anywhere in the pad is cut off by its maxLines.
void _expectNothingClipped(WidgetTester tester) {
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final para =
        tester.element(find.byWidget(rt)).renderObject! as RenderParagraph;
    expect(para.didExceedMaxLines, isFalse,
        reason: 'clipped: ${rt.text.toPlainText()}');
  }
}

void main() {
  for (final width in <double>[320, 360, 400, 480]) {
    testWidgets('pad lays out cleanly at ${width}dp', (tester) async {
      await _pumpPad(tester, _script(), width);

      expect(tester.takeException(), isNull); // no RenderFlex overflow
      _expectNothingClipped(tester);

      // Each column heading fits on a single line.
      for (final label in ['MEDICINE', 'DOSAGE', 'DURATION']) {
        final para = tester.renderObject<RenderParagraph>(find.text(label));
        expect(para.size.height, lessThan(20),
            reason: '$label wrapped to a second line at ${width}dp');
      }

      // The credentials column keeps most of the pad width instead of
      // being squeezed to a couple of characters by the brand tagline.
      final name = tester
          .renderObjectList<RenderParagraph>(find.text('Dr. Nafisa Rahman'))
          .first;
      expect(name.size.width, greaterThan(width * 0.4));
    });
  }

  testWidgets('a long diagnosis wraps inside the vitals bar', (tester) async {
    await _pumpPad(
      tester,
      _script(
        diagnosis: 'Acute upper respiratory tract infection with '
            'persistent fever and dehydration',
      ),
      360,
    );
    expect(tester.takeException(), isNull);
    _expectNothingClipped(tester);
  });

  testWidgets('patient line prints for a self-booking with no snapshot',
      (tester) async {
    await _pumpPad(
      tester,
      _script(patient: null, patientName: 'Zunayed Ahmed'),
      360,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Zunayed Ahmed', findRichText: true),
        findsWidgets);
  });
}
