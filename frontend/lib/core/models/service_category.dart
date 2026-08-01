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
bool serviceMatchesCategoryChip(ServiceCatalogItem item, String chip) {
  if (chip == kServiceCategoryAll) return true;
  return normalizeServiceCategory(item.category) == chip;
}
