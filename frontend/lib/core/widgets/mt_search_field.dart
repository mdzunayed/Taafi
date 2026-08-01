import 'package:flutter/material.dart';

import '../theme/app_colors_ext.dart';
import '../theme/mt_text_styles.dart';

/// The app-wide minimalist search input.
///
/// Visual anatomy:
///   • A true stadium silhouette — `BorderRadius.circular(100)` so the ends
///     stay full semicircles at any height.
///   • A razor-thin uniform outline (1.0px, 1.5px focused) in the adaptive
///     `cardBorder` token. No fill, no drop shadow, no glow.
///   • An `Icons.search` prefix tinted with the softened adaptive accent
///     orange — the only warm note; the outline stays neutral even focused.
///   • Faint left-aligned hint text in the `muted` token.
///
/// All colors come from `context.appColors`, so the field adapts to the
/// light/dark theme with no per-screen palette wiring.
///
/// Set [dense] for the 40px header/toolbar variant (admin console, dashboard
/// headers) — it tightens the vertical padding and shrinks the glyph so the
/// field seats inside a fixed 40px-tall box.
class MtSearchField extends StatefulWidget {
  /// Optional external controller; when omitted the field owns (and
  /// disposes) an internal one.
  final TextEditingController? controller;

  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Compact 40px header/toolbar variant.
  final bool dense;

  const MtSearchField({
    super.key,
    this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.dense = false,
  });

  @override
  State<MtSearchField> createState() => _MtSearchFieldState();
}

class _MtSearchFieldState extends State<MtSearchField> {
  TextEditingController? _internalController;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  OutlineInputBorder _outline(Color color, double width) => OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(100)),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dense = widget.dense;

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      cursorColor: colors.accent,
      style: MtTextStyles.bodyMd.copyWith(color: colors.title, fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: MtTextStyles.bodyMd.copyWith(
          color: colors.muted,
          fontSize: dense ? 13 : 14,
          fontWeight: FontWeight.w300,
        ),
        prefixIcon: Icon(
          Icons.search,
          size: dense ? 18 : 20,
          color: colors.accent.withValues(alpha: 0.8),
        ),
        filled: false,
        isDense: dense,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: dense ? 8 : 12,
        ),
        border: _outline(colors.cardBorder, 1.0),
        enabledBorder: _outline(colors.cardBorder, 1.0),
        focusedBorder: _outline(colors.cardBorder, 1.5),
      ),
    );
  }
}
