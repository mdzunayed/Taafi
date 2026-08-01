// Non-web fallback. There is no browser print pipeline on mobile/desktop,
// so printing is reported as unsupported and the call is a safe no-op. The
// Billing tab checks [ledgerPrintingSupported] and only surfaces the Print
// button when it's true.

/// Whether the running platform can drive a browser print dialog.
bool get ledgerPrintingSupported => false;

/// No-op on non-web targets.
void printLedgerDocument(String html) {
  // Intentionally empty — guarded by [ledgerPrintingSupported] at the call
  // site so this is never reached in practice.
}
