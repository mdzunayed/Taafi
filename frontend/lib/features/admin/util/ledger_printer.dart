// Public entry point for printing the billing ledger. Resolves to the
// web implementation (which drives the browser's print dialog) when
// compiled for Flutter web, and to a graceful no-op stub on mobile/desktop
// where there is no browser print pipeline. Callers import only this file.
export 'ledger_printer_stub.dart'
    if (dart.library.html) 'ledger_printer_web.dart';
