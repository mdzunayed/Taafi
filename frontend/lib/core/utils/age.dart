// Age helpers for dependent / care-recipient profiles. Date of birth is a
// free-form String (a partial "1990" is acceptable), so parsing is defensive:
// a bad or partial DOB yields null rather than a misleading number. Mirrors
// the backend `utils/age.js` logic.

/// Whole years from a DOB string, or null when empty / unparseable / future.
/// Accepts full ISO ("1958-04-12") and year-only ("1958").
int? ageFromDob(String? dob) {
  final raw = (dob ?? '').trim();
  if (raw.isEmpty) return null;

  DateTime? birth;
  if (RegExp(r'^\d{4}$').hasMatch(raw)) {
    // Year only — anchor to mid-year so the age is off by at most ~6 months.
    birth = DateTime(int.parse(raw), 7, 1);
  } else {
    birth = DateTime.tryParse(raw);
  }
  if (birth == null) return null;

  final now = DateTime.now();
  if (birth.isAfter(now)) return null;

  var age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    age -= 1;
  }
  return age >= 0 ? age : null;
}

/// "62 / F" style compact label. Falls back to whichever half is known;
/// returns '' when neither age nor gender is present.
String ageSexLabel(String? dob, String? gender) {
  final age = ageFromDob(dob);
  final g = (gender ?? '').trim();
  final sex = g.isEmpty ? '' : g[0].toUpperCase();
  if (age != null && sex.isNotEmpty) return '$age / $sex';
  if (age != null) return '$age';
  return sex;
}
