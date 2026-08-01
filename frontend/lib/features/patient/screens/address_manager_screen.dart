import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../new_request/new_request_state.dart';

/// Address & geolocation dispatch editor. Captures structured text fields plus
/// raw GPS coordinates (via geolocator) and returns the completed
/// [RequestAddress] to the caller through `Navigator.pop`, so the New Request
/// flow can serialize the coordinates into the CareRequest payload.
class AddressManagerScreen extends StatefulWidget {
  final RequestAddress initial;
  const AddressManagerScreen({super.key, required this.initial});

  @override
  State<AddressManagerScreen> createState() => _AddressManagerScreenState();
}

class _AddressManagerScreenState extends State<AddressManagerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _houseCtrl =
      TextEditingController(text: widget.initial.line1);
  late final TextEditingController _areaCtrl =
      TextEditingController(text: widget.initial.areaCityZip);
  late final TextEditingController _landmarkCtrl =
      TextEditingController(text: widget.initial.landmark ?? '');
  late final TextEditingController _latCtrl = TextEditingController(
      text: widget.initial.latitude?.toStringAsFixed(6) ?? '');
  late final TextEditingController _lngCtrl = TextEditingController(
      text: widget.initial.longitude?.toStringAsFixed(6) ?? '');

  bool _locating = false;

  @override
  void dispose() {
    _houseCtrl.dispose();
    _areaCtrl.dispose();
    _landmarkCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
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
        _toast('Location services are turned off on this device.',
            error: true);
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
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
      _toast('Pinned your current location.');
    } catch (e) {
      _toast("Couldn't get your location: $e", error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    HapticFeedback.lightImpact();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final result = widget.initial.copyWith(
      line1: _houseCtrl.text.trim(),
      areaCityZip: _areaCtrl.text.trim(),
      landmark: _landmarkCtrl.text.trim().isEmpty
          ? null
          : _landmarkCtrl.text.trim(),
      latitude: lat,
      longitude: lng,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final hasCoords = lat != null && lng != null;

    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Dispatch Address',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _label('Flat / House / Holding No.'),
            TextFormField(
              controller: _houseCtrl,
              textInputAction: TextInputAction.next,
              decoration: _dec('e.g. House 42, Road 11A, Apt 5B'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('Area / Neighborhood'),
            TextFormField(
              controller: _areaCtrl,
              textInputAction: TextInputAction.next,
              decoration: _dec('e.g. Dhanmondi, Dhaka 1209'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('Special landmark instructions for arriving clinician'),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: TextFormField(
                controller: _landmarkCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. Opposite City Bank, blue gate — call on arrival, '
                      'lift to 5th floor.',
                  contentPadding: EdgeInsets.all(14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _label('Precise location'),
            _MapPreview(lat: lat, lng: lng),
            const SizedBox(height: 10),
            MtButton(
              label: hasCoords
                  ? 'Update current location'
                  : 'Use my current location',
              isOutlined: true,
              leadingIcon: Icons.my_location,
              isLoading: _locating,
              onPressed: _useCurrentLocation,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: _dec('Latitude'),
                    validator: _coordValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: _dec('Longitude'),
                    validator: _coordValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: MtButton(
          label: 'Save address',
          leadingIcon: Icons.check_circle_outline,
          onPressed: _save,
        ),
      ),
    );
  }

  // A coordinate field is optional, but if filled it must parse to a number.
  String? _coordValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t) == null ? 'Invalid' : null;
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: MtColors.surface,
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
      );
}

/// Static map-preview placeholder — renders the captured coordinates without a
/// Google Maps API key. Swappable for a real map widget later.
class _MapPreview extends StatelessWidget {
  final double? lat;
  final double? lng;
  const _MapPreview({this.lat, this.lng});

  @override
  Widget build(BuildContext context) {
    final hasCoords = lat != null && lng != null;
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EEF0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasCoords ? Icons.location_on : Icons.map_outlined,
            size: 30,
            color: hasCoords ? MtColors.brand : MtColors.ink3,
          ),
          const SizedBox(height: 6),
          Text(
            hasCoords
                ? '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                : 'No precise location pinned',
            style: MtTextStyles.labelMd.copyWith(
              color: hasCoords ? MtColors.ink : MtColors.ink3,
            ),
          ),
          if (!hasCoords)
            Text('Tap “Use my current location” to pin coordinates',
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}
