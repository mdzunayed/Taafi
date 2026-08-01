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

class _AddressEditorSheetState extends ConsumerState<_AddressEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?.label ?? 'Home');
  late final TextEditingController _area =
      TextEditingController(text: widget.existing?.fullAddressText ?? '');
  late final TextEditingController _house =
      TextEditingController(text: widget.existing?.flatFloorHolding ?? '');
  late final TextEditingController _landmark =
      TextEditingController(text: widget.existing?.landmarkInstructions ?? '');
  late double? _lat = widget.existing?.latitude;
  late double? _lng = widget.existing?.longitude;
  late bool _isDefault = widget.existing?.isDefault ?? false;
  bool _locating = false;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _area.dispose();
    _house.dispose();
    _landmark.dispose();
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
            label: _label.text.trim(),
            fullAddressText: _area.text.trim(),
            flatFloorHolding: _house.text.trim(),
            landmarkInstructions: _landmark.text.trim(),
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
              _field(_label, 'Label (Home, Office, Parents House…)',
                  validator: true),
              const SizedBox(height: 12),
              _field(_house, 'Flat / House / Holding No.'),
              const SizedBox(height: 12),
              _field(_area, 'Area / Neighborhood, City', validator: true),
              const SizedBox(height: 12),
              _field(_landmark, 'Landmark instructions for the clinician',
                  maxLines: 2),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: MtButton(
                      label: (_lat != null && _lng != null)
                          ? 'Location pinned ✓'
                          : 'Use my current location',
                      isOutlined: true,
                      leadingIcon: Icons.my_location,
                      isLoading: _locating,
                      onPressed: _useCurrentLocation,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: MtColors.brand,
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                title: Text('Set as default address',
                    style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
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
      {bool validator = false, int maxLines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
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
