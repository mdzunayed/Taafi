import '../api/dio_client.dart';

/// Normalizes a server-supplied image reference into something safe to hand to
/// [Image.network] / `CachedNetworkImage`.
///
/// Returns `null` whenever there is nothing renderable, so callers branch to a
/// placeholder instead of constructing a `CachedNetworkImage` with an empty
/// `imageUrl` (which asserts) — the exact failure at the App-Open Ad summary
/// card, where `AppOpenAd.imageUrl` is non-nullable and defaults to `''`.
///
/// The backend already absolutizes these fields before they reach us (see
/// routes/promoBanners.js and routes/appOpenAd.js), so for well-formed API
/// responses this is a pass-through. It earns its keep on the paths that
/// bypass that: the admin home-sections panel lets an operator paste a raw URL
/// by hand, and older/partial rows can still carry a bare filename.
String? resolveImageUrl(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  // Inline base64 images render as-is.
  if (value.startsWith('data:')) return value;

  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    // Anything already absolute is honoured, but only over http(s) — reject
    // file:, javascript:, blob: and friends rather than handing them to the
    // image pipeline.
    return (uri.scheme == 'http' || uri.scheme == 'https') ? value : null;
  }

  // Relative: either `/uploads/x.jpg` or a bare `x.jpg` filename.
  final base = DioClient.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}
