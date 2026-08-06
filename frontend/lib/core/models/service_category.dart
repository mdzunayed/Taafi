/// Canonical vocabulary for a service's `category`, and the chip set the
/// patient Home screen filters with.
///
/// `category` was a free-text field for its whole life, so the database
/// accumulated a vocabulary nobody designed — 'Recovery', 'Consultation',
/// 'Diagnostics'. Home now filters on an *exact* match against two canonical
/// labels, so anything that isn't folded onto them is invisible to the chips.
///
/// MIRROR: `backend/src/utils/serviceCategories.js` holds the authoritative
/// copy of the alias table below and normalizes on write, so stored values are
/// canonical by construction. This file duplicates it anyway, on purpose:
/// mobile builds are not force-updated and may talk to an API whose database
/// hasn't been migrated, and a client that trusted the raw string would
/// silently render two empty chips. ~25 lines of duplication buys a client
/// that degrades gracefully. Keep the two tables in sync when adding an alias.
library;

import 'service_catalog_item.dart';

/// Sentinel chip that disables filtering entirely.
const String kServiceCategoryAll = 'All';

/// Slug form of the sentinel, and the value [selectedCategoryProvider] holds
/// while the Home rail is unfiltered.
///
/// Lives here rather than on [HomeCategory] — which re-exports it as
/// `HomeCategory.allSlug` — so this library stays the bottom of the dependency
/// chain: the category model imports the vocabulary, never the reverse.
const String kCategoryAllSlug = 'all';

const String kServiceCategoryPostOp = 'Post-op';
const String kServiceCategoryDoctorInHome = 'Doctor in Home';

/// The real categories a service can carry, in chip order.
const List<String> kServiceCategories = [
  kServiceCategoryPostOp,
  kServiceCategoryDoctorInHome,
];

/// The complete Home filter rail — exactly three chips.
const List<String> kPatientCategoryChips = [
  kServiceCategoryAll,
  ...kServiceCategories,
];

/// Squashed alias → canonical label. Keys have had every non-alphanumeric
/// character stripped (see [_squash]), so one entry covers 'Post-op',
/// 'post op', 'POST_OP' and 'Post  Op' at once.
const Map<String, String> _aliases = {
  // --- Post-op ---
  'postop': kServiceCategoryPostOp,
  'postoperative': kServiceCategoryPostOp,
  'postopcare': kServiceCategoryPostOp,
  'postsurgery': kServiceCategoryPostOp,
  'postsurgical': kServiceCategoryPostOp,
  'postsurgerycare': kServiceCategoryPostOp,
  'recovery': kServiceCategoryPostOp,
  'rehabilitation': kServiceCategoryPostOp,
  'rehab': kServiceCategoryPostOp,
  'physiotherapy': kServiceCategoryPostOp,
  'physio': kServiceCategoryPostOp,
  'wound': kServiceCategoryPostOp,
  'woundcare': kServiceCategoryPostOp,
  'surgery': kServiceCategoryPostOp,
  'surgicalcare': kServiceCategoryPostOp,

  // --- Doctor in Home ---
  'doctorinhome': kServiceCategoryDoctorInHome,
  'doctorathome': kServiceCategoryDoctorInHome,
  'doctorhome': kServiceCategoryDoctorInHome,
  'homedoctor': kServiceCategoryDoctorInHome,
  'doctorhomevisit': kServiceCategoryDoctorInHome,
  'doctorvisit': kServiceCategoryDoctorInHome,
  'homevisit': kServiceCategoryDoctorInHome,
  'consultation': kServiceCategoryDoctorInHome,
  'doctorconsultation': kServiceCategoryDoctorInHome,
  'physicianathome': kServiceCategoryDoctorInHome,
  'gpvisit': kServiceCategoryDoctorInHome,
};

final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]+');

String _squash(String value) =>
    value.toLowerCase().replaceAll(_nonAlphanumeric, '');

/// Folds any stored / typed category onto the canonical vocabulary.
///
/// Returns one of [kServiceCategories], or `''` when the value maps to
/// neither. `''` is a legitimate answer, not a failure: lab collection and
/// nurse-on-call are genuinely neither post-op care nor a doctor visit, and
/// those services stay visible under the [kServiceCategoryAll] chip.
///
/// Call this at filter / display time, never inside
/// [ServiceCatalogItem.fromJson] — the admin console has to show operators
/// the value the database actually holds so they can see and fix a legacy one.
String normalizeServiceCategory(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';
  return _aliases[_squash(trimmed)] ?? '';
}

/// True when [item] belongs under the [chip] filter.
///
/// [kServiceCategoryAll] matches everything, including uncategorized services.
/// Everything else is an exact match on the *normalized* category — notably
/// **not** a substring search over the title, which is what used to make the
/// 'Post-op' chip catch any service whose name happened to mention surgery.
///
/// Superseded on Home by the slug join in [serviceMatchesCategorySlug], which
/// the admin-managed rail needs; still used by the label-driven filters that
/// have no category document to match against (the standalone service catalog
/// screen, the banner target picker).
bool serviceMatchesCategoryChip(ServiceCatalogItem item, String chip) {
  if (chip == kServiceCategoryAll) return true;
  return normalizeServiceCategory(item.category) == chip;
}

final RegExp _slugSeparators = RegExp(r'[^a-z0-9]+');
final RegExp _edgeHyphens = RegExp(r'^-+|-+$');

/// Any label → lowercase kebab-case. 'Doctor in Home' → `doctor-in-home`.
///
/// MIRROR: `slugify` in backend/src/utils/serviceCategories.js.
String slugifyCategory(String? raw) => (raw ?? '')
    .trim()
    .toLowerCase()
    .replaceAll(_slugSeparators, '-')
    .replaceAll(_edgeHyphens, '');

/// The join key between a service's free-text category and a [HomeCategory].
///
/// Differs from [normalizeServiceCategory] in one way that matters: that
/// function collapses anything outside [kServiceCategories] to `''`, which was
/// correct while the chip rail was a fixed list — an unrecognised value had no
/// pill to belong to. Now that admins mint pills at runtime, 'Nursing' is a
/// perfectly good category the alias table has simply never heard of, so an
/// unrecognised value slugifies as itself instead of vanishing.
///
/// The alias fold still runs first, so a service stored as 'Recovery' resolves
/// to `post-op` and keeps matching the Post-op pill exactly as it does today.
/// Returns `''` for uncategorized services: they match no pill and stay
/// visible under "All".
///
/// MIRROR: `categorySlug` in backend/src/utils/serviceCategories.js. The API
/// resolves this server-side for every card it sends; the client keeps its own
/// copy for the offline / old-backend fallback path, where cards are built
/// straight from `/api/services`.
String categorySlugFor(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';
  final canonical = _aliases[_squash(trimmed)];
  return slugifyCategory(canonical ?? trimmed);
}

/// True when a card tagged [cardSlug] belongs under the [selectedSlug] pill.
///
/// [kCategoryAllSlug] matches everything, including untagged cards. A null or
/// blank [cardSlug] means untagged, which matches nothing else — an
/// uncategorized service must not leak into an unrelated filter.
bool serviceMatchesCategorySlug(String? cardSlug, String selectedSlug) {
  if (selectedSlug == kCategoryAllSlug || selectedSlug.isEmpty) return true;
  return (cardSlug ?? '').isNotEmpty && cardSlug == selectedSlug;
}

/// [serviceMatchesCategorySlug] for a card carrying several pills.
///
/// One service can be assigned to multiple categories in the CMS, so a card's
/// membership is a set rather than a single value: it belongs under
/// [selectedSlug] when *any* of [cardSlugs] matches. An empty set is untagged
/// and matches only [kCategoryAllSlug].
bool serviceMatchesAnyCategorySlug(
  Iterable<String> cardSlugs,
  String selectedSlug,
) {
  if (selectedSlug == kCategoryAllSlug || selectedSlug.isEmpty) return true;
  return cardSlugs.any((s) => s.isNotEmpty && s == selectedSlug);
}
