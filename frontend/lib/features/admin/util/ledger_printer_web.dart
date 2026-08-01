// Web implementation of the ledger printer. Materialises the HTML document
// as an in-memory Blob, opens it in a new browser tab, and lets the document
// drive its own `window.print()` on load (the Billing tab embeds that script
// in the HTML it builds). Going through a Blob URL avoids poking at the new
// window's DOM from Dart, which keeps this resilient across browsers.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Browser targets can always drive `window.print()`.
bool get ledgerPrintingSupported => true;

/// Opens [htmlDocument] (a complete, self-printing HTML page) in a new tab.
void printLedgerDocument(String htmlDocument) {
  final blob = html.Blob(<Object>[htmlDocument], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  // Release the object URL once the new tab has had time to load it.
  Future<void>.delayed(const Duration(seconds: 30), () {
    html.Url.revokeObjectUrl(url);
  });
}
