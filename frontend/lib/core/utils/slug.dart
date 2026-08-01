/// Turns "Dr. Nafisa Rahman" -> "dr-nafisa-rahman" for use in URLs.
String slugify(String input) {
  final lower = input.toLowerCase().trim();
  final stripped = lower.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
  final dashed = stripped.replaceAll(RegExp(r'[\s-]+'), '-');
  final trimmed = dashed.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'user' : trimmed;
}
