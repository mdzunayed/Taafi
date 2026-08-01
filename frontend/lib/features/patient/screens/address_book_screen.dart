import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/saved_address.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../auth/auth_provider.dart';
import '../profile/patient_lifecycle_providers.dart';

IconData _iconForLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('office') || l.contains('work')) return Icons.work_outline;
  if (l.contains('parent') || l.contains('family') || l.contains('home2')) {
    return Icons.family_restroom;
  }
  if (l.contains('hospital') || l.contains('clinic')) {
    return Icons.local_hospital_outlined;
  }
  return Icons.home_outlined;
}

/// The patient's reusable saved-address ledger. Premium card list with
/// per-label icons and a default-location switch.
class AddressBookScreen extends ConsumerWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedAddressesProvider);
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Address Book',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MtColors.brand,
        foregroundColor: Colors.white,
        onPressed: () {
          HapticFeedback.lightImpact();
          _openEditor(context, ref, null);
        },
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add address'),
      ),
      body: RefreshIndicator(
        color: MtColors.brand,
        onRefresh: () async => ref.invalidate(savedAddressesProvider),
        child: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: MtColors.brand)),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MtErrorState(
                title: "Couldn't load addresses",
                message: e.toString(),
                onRetry: () => ref.invalidate(savedAddressesProvider),
              ),
            ],
          ),
          data: (addresses) {
            if (addresses.isEmpty) return const _EmptyAddresses();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: addresses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AddressCard(address: addresses[i]),
            );
          },
        ),
      ),
    );
  }

  static void _openEditor(
    BuildContext context,
    WidgetRef ref,
    SavedAddress? existing,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddressEditorSheet(existing: existing),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  final SavedAddress address;
  const _AddressCard({required this.address});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('Remove "${address.label}" from your address book?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dioClientProvider).deleteAddress(address.id);
      ref.invalidate(savedAddressesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: MtColors.rejected,
        content: Text("Couldn't delete: $e"),
      ));
    }
  }

  Future<void> _makeDefault(BuildContext context, WidgetRef ref) async {
    if (address.isDefault) return;
    HapticFeedback.lightImpact();
    try {
      await ref.read(dioClientProvider).setDefaultAddress(address.id);
      ref.invalidate(savedAddressesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: MtColors.rejected,
        content: Text("Couldn't set default: $e"),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: address.isDefault ? MtColors.brand : MtColors.line,
          width: address.isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconForLabel(address.label),
                    color: MtColors.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(address.label,
                            style: MtTextStyles.labelLg.copyWith(
                                color: MtColors.ink,
                                fontWeight: FontWeight.w800)),
                        if (address.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: MtColors.brandSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('DEFAULT',
                                style: MtTextStyles.labelSm.copyWith(
                                    color: MtColors.brand, fontSize: 9)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(address.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: MtColors.ink3),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  AddressBookScreen._openEditor(context, ref, address);
                },
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MtColors.rejected),
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
          const Divider(height: 18, color: MtColors.line),
          Row(
            children: [
              Icon(
                address.hasCoordinates
                    ? Icons.location_on
                    : Icons.location_off_outlined,
                size: 15,
                color: address.hasCoordinates ? MtColors.brand : MtColors.ink3,
              ),
              const SizedBox(width: 4),
              Text(
                address.hasCoordinates ? 'Pinned location' : 'No GPS pin',
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
              const Spacer(),
              Text('Set as default',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2)),
              Switch.adaptive(
                value: address.isDefault,
                activeThumbColor: MtColors.brand,
                onChanged: (_) => _makeDefault(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Editor sheet (create / edit) ────────────────────────────────────────────

class _AddressEditorSheet extends ConsumerStatefulWidget {
  final SavedAddress? existing;
  const _AddressEditorSheet({this.existing});

  @override
  ConsumerState<_AddressEditorSheet> createState() =>
      _AddressEditorSheetState();
}

/// The residential tags offered as one-tap chips, replacing the free-text
/// label field. `null` is the "Other" escape hatch, which reveals a small
/// custom-name input for anything outside these four.
const _kResidentialTags = <String>['Home', 'Office', 'Parents', 'Hospital'];

class _AddressEditorSheetState extends ConsumerState<_AddressEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  /// The chosen residential tag, or `null` while "Other" is selected (the
  /// name then comes from [_customLabel]).
  late String? _tag = _initialTag();

  /// Only used under the "Other" chip.
  late final TextEditingController _customLabel =
      TextEditingController(text: _initialTag() == null ? _existingLabel : '');

  /// The single consolidated address line. Seeded from the two legacy
  /// columns joined together so editing an address saved under the old
  /// split-field form shows everything the patient originally typed.
  late final TextEditingController _address =
      TextEditingController(text: _initialAddressText());

  late double? _lat = widget.existing?.latitude;
  late double? _lng = widget.existing?.longitude;
  late bool _isDefault = widget.existing?.isDefault ?? false;
  bool _locating = false;
  bool _saving = false;

  String get _existingLabel => widget.existing?.label.trim() ?? 'Home';

  /// Match the saved label onto a chip, case-insensitively. An unrecognised
  /// label (e.g. "Nani's flat") falls through to "Other" with the original
  /// text preserved in the custom field.
  String? _initialTag() {
    if (widget.existing == null) return _kResidentialTags.first;
    final saved = _existingLabel.toLowerCase();
    for (final tag in _kResidentialTags) {
      if (tag.toLowerCase() == saved) return tag;
    }
    return null;
  }

  String _initialAddressText() {
    final e = widget.existing;
    if (e == null) return '';
    return [e.flatFloorHolding.trim(), e.fullAddressText.trim()]
        .where((p) => p.isNotEmpty)
        .join(', ');
  }

  /// The label actually persisted: the chip, or the custom text under
  /// "Other" (falling back to "Home" if that was left blank).
  String get _effectiveLabel {
    if (_tag != null) return _tag!;
    final custom = _customLabel.text.trim();
    return custom.isEmpty ? 'Home' : custom;
  }

  @override
  void dispose() {
    _customLabel.dispose();
    _address.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.completed,
    ));
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    HapticFeedback.lightImpact();
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Location services are off.', error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission denied.', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      _toast('Pinned your current location.');
    } catch (e) {
      _toast("Couldn't get location: $e", error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.vibrate();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      await ref.read(dioClientProvider).saveAddress(
            id: widget.existing?.id,
            label: _effectiveLabel,
            // The consolidated line lands wholesale in `full_address_text` —
            // the column every consumer already reads (list summaries, the
            // booking form's `areaCityZip`). `flat_floor_holding` is left
            // blank rather than guessed at by parsing free text; it stays in
            // the schema for rows written by the old split-field editor.
            fullAddressText: _address.text.trim(),
            flatFloorHolding: '',
            // No longer collected here — the booking form has its own
            // per-visit landmark field. Existing text is passed through
            // untouched so editing an address doesn't silently erase it.
            landmarkInstructions:
                widget.existing?.landmarkInstructions.trim() ?? '',
            latitude: _lat,
            longitude: _lng,
            isDefault: _isDefault,
          );
      ref.invalidate(savedAddressesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Address saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast("Couldn't save: $e", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.existing == null ? 'Add address' : 'Edit address',
                  style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
              const SizedBox(height: 16),

              // 1 — Auto-fill first. Pinning GPS is the lowest-effort way to
              // start, so it sits above the field it fills rather than
              // below the form where it used to be missed.
              _LocationChip(
                pinned: _lat != null && _lng != null,
                loading: _locating,
                onTap: _useCurrentLocation,
              ),
              const SizedBox(height: 18),

              // 2 — Residential tag. Four one-tap chips instead of a text
              // field; "Other" reveals a name box for the long tail.
              Text('Save as',
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _kResidentialTags)
                    _TagChip(
                      label: tag,
                      icon: _iconForLabel(tag),
                      selected: _tag == tag,
                      onTap: () => setState(() => _tag = tag),
                    ),
                  _TagChip(
                    label: 'Other',
                    icon: Icons.bookmark_border,
                    selected: _tag == null,
                    onTap: () => setState(() => _tag = null),
                  ),
                ],
              ),
              if (_tag == null) ...[
                const SizedBox(height: 10),
                _field(_customLabel, 'Name this address'),
              ],
              const SizedBox(height: 18),

              // 3 — One field for the whole address. Everything the rider
              // needs on a single line; no flat/road/area/city hopping.
              Text('Flat / House / Road / Block, area',
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
              const SizedBox(height: 8),
              _field(
                _address,
                'e.g. Flat A-3, House 12, Road 4, Block C, '
                'banasree, rampura, dhaka',
                validator: true,
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 18),

              // 4 — Footer: default toggle inline on the right, then the
              // full-width primary action.
              Row(
                children: [
                  Expanded(
                    child: Text('Set as default address',
                        style: MtTextStyles.labelMd
                            .copyWith(color: MtColors.ink)),
                  ),
                  Switch.adaptive(
                    value: _isDefault,
                    activeThumbColor: MtColors.brand,
                    onChanged: (v) => setState(() => _isDefault = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MtButton(
                label: 'Save address',
                leadingIcon: Icons.check_circle_outline,
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool validator = false, int maxLines = 1, int? minLines}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      minLines: minLines,
      // Multi-line address entry: newline should break the line, not submit.
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
      keyboardType:
          maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: MtColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.line),
        ),
      ),
      validator: validator
          ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
          : null,
    );
  }
}

/// Elevated auto-fill action at the top of the editor. Flips to a settled
/// "pinned" state once coordinates are captured, so the patient can see the
/// GPS fix took without hunting for a separate confirmation.
class _LocationChip extends StatelessWidget {
  final bool pinned;
  final bool loading;
  final VoidCallback onTap;

  const _LocationChip({
    required this.pinned,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = pinned ? MtColors.completed : MtColors.brand;
    return Material(
      color: pinned ? MtColors.surface : MtColors.brandSofter,
      borderRadius: BorderRadius.circular(14),
      elevation: pinned ? 0 : 2,
      shadowColor: MtColors.brand.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: fg.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                )
              else
                Icon(pinned ? Icons.check_circle : Icons.my_location,
                    size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loading
                      ? 'Finding you…'
                      : pinned
                          ? 'Current location pinned — tap to update'
                          : '📍 Use my current location',
                  style: MtTextStyles.labelMd.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One residential tag. Selection is the only state that matters, so it's a
/// plain filled/outlined pill rather than a Material `ChoiceChip` (which
/// carries theming this sheet doesn't otherwise use).
class _TagChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : MtColors.ink2;
    return Material(
      color: selected ? MtColors.brand : MtColors.bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? MtColors.brand : MtColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label, style: MtTextStyles.labelMd.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAddresses extends StatelessWidget {
  const _EmptyAddresses();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.location_off_outlined,
            size: 46, color: MtColors.ink3.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('No saved addresses',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 4),
        Text('Add an address to reuse it at checkout.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
      ],
    );
  }
}
