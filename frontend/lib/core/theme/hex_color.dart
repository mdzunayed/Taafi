import 'package:flutter/material.dart';

/// Parses a hex color string into a [Color].
///
/// Accepts `#RGB`, `#RRGGBB`, or `#AARRGGBB` (case- and hash-insensitive; the
/// leading `#` is optional). Shorthand `#RGB` expands each nibble and a
/// 6-digit value is treated as fully opaque — matching the backend's
/// `sanitizeHex`, so the admin's live swatch and the rendered card agree.
/// Returns `null` for a null/blank/malformed value so callers can skip it and
/// fall back to a theme token.
///
/// Shared by [PromoBanner] and the home-section style tokens.
Color? hexToColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceFirst('#', '');
  if (value.isEmpty) return null;
  if (value.length == 3) {
    // RGB -> RRGGBB
    value = value.split('').map((c) => '$c$c').join();
  }
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
