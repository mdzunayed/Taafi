// The assigned clinician's view of the patient's attached medical records.
//
// Three things have to hold for a doctor or nurse to safely read a discharge
// summary from the console, and each has bitten a surface before:
//
//   1. The panel must distinguish "the patient attached nothing" from "we
//      could not find out". A clinician who sees an empty card believes there
//      was nothing to read; if that card is actually a swallowed 403, they
//      walk into the visit missing the case history.
//   2. A malformed descriptor must degrade to a renderable tile, not throw.
//      This panel sits above the vitals form and the completion footer — an
//      exception here blanks the whole console mid-visit.
//   3. The parsed URLs must be the presigned grants, never a raw storage
//      location. A Cloudinary asset is readable forever by anyone holding its
//      URL, so leaking one through the provider payload would outlive every
//      expiry the grant system exists to enforce.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/models/booking_attachment.dart';
import 'package:taafi/features/provider/presentation/widgets/patient_documents_panel.dart';
import 'package:taafi/features/provider/providers/booking_attachments_provider.dart';

const _bookingId = '507f1f77bcf86cd799439011';

/// One `attachments[]` entry exactly as `describeAttachment` emits it.
Map<String, dynamic> _descriptor({
  String id = '$_bookingId-0',
  String name = 'discharge_summary.pdf',
  String type = 'application/pdf',
  String? url,
}) {
  return {
    'id': id,
    'file_name': name,
    'file_type': type,
    'file_url': url ?? 'https://api.taafi.test/api/documents/grant-token',
    'download_url':
        '${url ?? 'https://api.taafi.test/api/documents/grant-token'}?download=1',
    'size_bytes': 148223,
    'uploaded_at': '2026-08-07T01:30:00.000Z',
  };
}

/// Pumps the panel with [bookingAttachmentsProvider] overridden, so the tests
/// exercise the real widget against a controlled fetch outcome.
Future<void> _pump(
  WidgetTester tester,
  Future<List<BookingAttachment>> Function() fetch,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingAttachmentsProvider.overrideWith((ref, id) => fetch()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PatientDocumentsPanel(bookingId: _bookingId),
        ),
      ),
    ),
  );
}

void main() {
  group('descriptor parsing', () {
    test('reads the backend shape and exposes the presigned grant', () {
      final list = BookingAttachment.listFrom([_descriptor()]);
      expect(list, hasLength(1));
      final doc = list.single;
      expect(doc.fileName, 'discharge_summary.pdf');
      expect(doc.isPdf, isTrue);
      expect(doc.isImage, isFalse);
      expect(doc.sizeBytes, 148223);
      expect(doc.uploadedAt, DateTime.utc(2026, 8, 7, 1, 30));
      expect(doc.fileUrl, contains('/api/documents/'));
      // The provider payload must never carry the raw storage location.
      expect(doc.fileUrl, isNot(contains('res.cloudinary.com')));
    });

    test('classifies images so the viewer picks the lightbox', () {
      for (final mime in ['image/jpeg', 'image/png', 'image/webp']) {
        final doc =
            BookingAttachment.listFrom([_descriptor(type: mime)]).single;
        expect(doc.isImage, isTrue, reason: '$mime should open in the lightbox');
        expect(doc.isPdf, isFalse);
      }
    });

    test('an unknown mime is neither image nor pdf', () {
      // `safeMime` collapses anything unrecognised to octet-stream server-side.
      // It must not be fed to the image decoder or the PDF view on a guess.
      final doc = BookingAttachment.listFrom(
        [_descriptor(type: 'application/octet-stream')],
      ).single;
      expect(doc.isImage, isFalse);
      expect(doc.isPdf, isFalse);
    });

    test('a descriptor with no usable URL is dropped, not rendered', () {
      // A tile whose only button can never work is worse than no tile.
      final list = BookingAttachment.listFrom([
        _descriptor(url: ''),
        _descriptor(id: '$_bookingId-1', name: 'labs.pdf'),
      ]);
      expect(list, hasLength(1));
      expect(list.single.fileName, 'labs.pdf');
    });

    test('a malformed entry degrades instead of throwing', () {
      // The console must survive a payload it did not expect.
      final list = BookingAttachment.listFrom([
        {'file_url': 'https://api.taafi.test/api/documents/t'},
        'not-a-map',
        null,
      ]);
      expect(list, hasLength(1));
      expect(list.single.fileName, 'Document');
      expect(list.single.sizeBytes, 0);
      expect(list.single.uploadedAt, isNull);
      // Older backends ship only `file_url`; Download still has to resolve.
      expect(list.single.downloadUrl, endsWith('?download=1'));
    });

    test('a non-list payload yields nothing rather than throwing', () {
      expect(BookingAttachment.listFrom(null), isEmpty);
      expect(BookingAttachment.listFrom('attachments'), isEmpty);
    });
  });

  group('panel states', () {
    testWidgets('lists each document with a View action', (tester) async {
      await _pump(
        tester,
        () async => BookingAttachment.listFrom([
          _descriptor(),
          _descriptor(id: '$_bookingId-1', name: 'blood_panel.png',
              type: 'image/png'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('PATIENT ATTACHED DOCUMENTS (2)'), findsOneWidget);
      expect(find.text('discharge_summary.pdf'), findsOneWidget);
      expect(find.text('blood_panel.png'), findsOneWidget);
      expect(find.text('View'), findsNWidgets(2));
      // PDFs are badged; images render a thumbnail instead.
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('says so explicitly when nothing was attached',
        (tester) async {
      await _pump(tester, () async => const <BookingAttachment>[]);
      await tester.pumpAndSettle();

      expect(find.text('PATIENT ATTACHED DOCUMENTS (0)'), findsOneWidget);
      expect(
        find.text('No medical documents attached by patient.'),
        findsOneWidget,
      );
      expect(find.text('View'), findsNothing);
    });

    testWidgets('a failed read is NOT reported as an empty folder',
        (tester) async {
      // The regression that matters: a 403 (someone else was reassigned to
      // this visit) rendering as "no documents attached" would tell a
      // clinician a falsehood about their patient's history.
      await _pump(tester, () async => throw Exception('403'));
      await tester.pumpAndSettle();

      expect(
        find.text('No medical documents attached by patient.'),
        findsNothing,
      );
      expect(
        find.text("Could not load the patient's documents."),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows a loading state before the fetch settles',
        (tester) async {
      final completer = Completer<List<BookingAttachment>>();
      await _pump(tester, () => completer.future);
      await tester.pump();

      expect(find.text('Loading patient documents…'), findsOneWidget);
      // The header keeps its footprint so the console below does not jump
      // when the count arrives.
      expect(find.text('PATIENT ATTACHED DOCUMENTS'), findsOneWidget);

      completer.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('PATIENT ATTACHED DOCUMENTS (0)'), findsOneWidget);
    });
  });
}
