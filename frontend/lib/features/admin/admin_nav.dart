import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Admin console navigation contract.
///
/// The console renders eight destinations behind four sidebar groups. Each
/// destination owns its own sub-tabs, so cross-screen hand-offs ("send this
/// booking to the dispatch workspace") need to name *two* things: the section
/// and the sub-tab inside it. Sections stay integer-indexed because the shell
/// still drives an `IndexedStack`-style list; the sub-tab lives in a
/// `StateProvider` so a caller anywhere in the tree can set it without the
/// callback having to thread an extra argument through five widget layers.
///
/// Before this file the indices were bare integers duplicated across five
/// files, with a comment warning that reordering them would silently re-point
/// every call site. Naming them removes that hazard.
class AdminSection {
  const AdminSection._();

  static const int overview = 0;
  static const int bookings = 1;
  static const int providers = 2;
  static const int patients = 3;
  static const int services = 4;
  static const int banners = 5;
  static const int finance = 6;
  static const int settings = 7;

  static const int count = 8;
}

// ─── Bookings hub ────────────────────────────────────────────────────────────

/// Tabs of the unified Bookings workspace. These replace what used to be six
/// separate sidebar destinations (pipeline, live monitor, review queue,
/// booking review, assign team, Rx approvals).
enum BookingsTab {
  /// Full care-request table with status chips + bulk triage actions.
  all('All bookings'),

  /// Deposit-paid bookings that still need a service fee quoted.
  pricing('Awaiting pricing'),

  /// Priced + paid bookings waiting on a dispatch team.
  assignment('Needs assignment'),

  /// Prescription / report approval queue.
  rxReview('Rx & report review');

  const BookingsTab(this.label);
  final String label;
}

final bookingsTabProvider =
    StateProvider<BookingsTab>((ref) => BookingsTab.all);

// ─── Providers hub ───────────────────────────────────────────────────────────

/// Status pills on the Providers directory. `pending` doubles as the merged
/// doctor + nurse credential-verification queue that used to be two separate
/// sidebar entries.
enum ProvidersFilter {
  all('All'),
  pending('Pending verification'),
  active('Active'),
  suspended('Suspended');

  const ProvidersFilter(this.label);
  final String label;
}

final providersFilterProvider =
    StateProvider<ProvidersFilter>((ref) => ProvidersFilter.all);

// ─── Content (CMS) hub ───────────────────────────────────────────────────────

enum ServicesTab {
  services('Services'),
  categories('Categories'),
  careLayout('Care services layout'),
  homeSections('Home sections');

  const ServicesTab(this.label);
  final String label;
}

final servicesTabProvider =
    StateProvider<ServicesTab>((ref) => ServicesTab.services);

// ─── Finance hub ─────────────────────────────────────────────────────────────

enum FinanceTab {
  billing('Billing'),
  cashClearance('Cash clearance'),
  payouts('Provider payouts');

  const FinanceTab(this.label);
  final String label;
}

final financeTabProvider =
    StateProvider<FinanceTab>((ref) => FinanceTab.billing);
