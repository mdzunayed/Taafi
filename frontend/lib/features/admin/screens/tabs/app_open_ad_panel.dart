import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/app_open_ad_providers.dart';
import '../../../../core/models/app_open_ad.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/image_upload.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_toast.dart';

/// Admin control panel for the full-screen app-open interstitial ad.
///
/// Rendered at the top of [AdminBannerManagementPage]. The campaign is a
/// backend singleton, so this is a single card — image preview, countdown
/// duration, live active toggle, and an edit dialog — rather than a list.
class AppOpenAdPanel extends ConsumerWidget {
  const AppOpenAdPanel({super.key});

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    AppOpenAd ad,
    bool isActive,
  ) async {
    try {
      await ref.read(appOpenAdRepositoryProvider).save(
            durationInSeconds: ad.durationInSeconds,
            isActive: isActive,
          );
      ref.invalidate(appOpenAdProvider);
      if (!context.mounted) return;
      MtToast.success(
        context,
        isActive ? 'App-open ad activated' : 'App-open ad deactivated',
      );
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete app-open ad?', style: MtTextStyles.h3),
        content: Text(
          'Patients will no longer see an interstitial when the app launches.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(appOpenAdRepositoryProvider).delete();
      ref.invalidate(appOpenAdProvider);
      if (!context.mounted) return;
      MtToast.success(context, 'App-open ad deleted');
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appOpenAdProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.ad_units_outlined, color: MtColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('App-open ad', style: MtTextStyles.h3),
                    const SizedBox(height: 2),
                    Text(
                      'Full-screen interstitial patients see when the app '
                      'launches. It auto-dismisses to Home after the countdown.',
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              'Could not load the app-open ad: $e',
              style: MtTextStyles.bodySm.copyWith(color: Colors.red),
            ),
            data: (ad) => ad == null
                ? _EmptyState(
                    onCreate: () => _openForm(context, ref, existing: null))
                : _AdSummary(
                    ad: ad,
                    onEdit: () => _openForm(context, ref, existing: ad),
                    onDelete: () => _delete(context, ref),
                    onToggle: (v) => _toggleActive(context, ref, ad, v),
                  ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref,
      {required AppOpenAd? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _AppOpenAdFormDialog(existing: existing),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'No app-open ad configured yet.',
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
          ),
        ),
        SizedBox(
          width: 200,
          child: MtButton(
            label: 'Set up ad',
            leadingIcon: Icons.add,
            onPressed: onCreate,
          ),
        ),
      ],
    );
  }
}

class _AdSummary extends StatelessWidget {
  final AppOpenAd ad;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _AdSummary({
    required this.ad,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `ad.imageUrl` is non-nullable and defaults to '' — AppNetworkImage
        // resolves that to the placeholder instead of letting
        // CachedNetworkImage assert on an empty URL.
        AppNetworkImage(
          url: ad.imageUrl,
          width: 90,
          height: 160,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 16, color: MtColors.ink3),
                  const SizedBox(width: 6),
                  Text(
                    'Shows for ${ad.durationInSeconds}s, then opens Home',
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active', style: MtTextStyles.labelLg),
                subtitle: Text(
                  ad.isActive
                      ? 'Patients see this ad at every app launch'
                      : 'Campaign is off — patients go straight to Home',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
                value: ad.isActive,
                activeColor: MtColors.brand,
                onChanged: onToggle,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: MtButton(
                      label: 'Edit',
                      leadingIcon: Icons.edit_outlined,
                      isOutlined: true,
                      onPressed: onEdit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Delete ad',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Form dialog ------------------------------------------------------------

class _AppOpenAdFormDialog extends ConsumerStatefulWidget {
  final AppOpenAd? existing;
  const _AppOpenAdFormDialog({required this.existing});

  @override
  ConsumerState<_AppOpenAdFormDialog> createState() =>
      _AppOpenAdFormDialogState();
}

class _AppOpenAdFormDialogState extends ConsumerState<_AppOpenAdFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _duration;
  late bool _isActive;
  PreparedImage? _pickedImage;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _duration = TextEditingController(
        text: (widget.existing?.durationInSeconds ?? 5).toString());
    _isActive = widget.existing?.isActive ?? false;
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      // FileType.custom restricts the dialog itself to the formats the backend
      // accepts — image_picker could only ask for `image/*` on web, which let
      // HEIC/AVIF through to be rejected as a 415 after a full round trip.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAllowedImageExtensions,
        withData: true, // web needs it; keeps mobile on the same bytes path
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      // The dialog filter is a convenience, not a guarantee ("All files" is one
      // click away), and it also handles the downscale image_picker_for_web
      // used to skip, keeping web uploads under multer's 8 MB cap.
      final prepared = await prepareImageBytesForUpload(
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      setState(() => _pickedImage = prepared);
    } on UnsupportedImageException catch (e) {
      if (!mounted) return;
      MtToast.error(context, 'Unsupported image', e.message);
    } catch (e) {
      if (!mounted) return;
      MtToast.error(context, 'Image not selected',
          'Could not read the chosen image. Try another file.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // The backend requires an image on the very first save.
    if (!_isEdit && _pickedImage == null) {
      MtToast.error(context, 'Image required',
          'Pick the full-screen ad graphic before saving.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(appOpenAdRepositoryProvider).save(
            durationInSeconds: int.parse(_duration.text.trim()),
            isActive: _isActive,
            image: _pickedImage,
          );
      ref.invalidate(appOpenAdProvider);
      if (!mounted) return;
      MtToast.success(
          context, _isEdit ? 'App-open ad updated' : 'App-open ad created');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_isEdit ? 'Edit app-open ad' : 'Set up app-open ad',
                    style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update the campaign below. Leave the image empty to keep the current one.'
                      : 'Upload a portrait full-screen graphic (JPEG/PNG/WEBP, max 8 MB).',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _AdImagePickerTile(
                  pickedBytes: _pickedImage?.bytes,
                  existingUrl: widget.existing?.imageUrl,
                  onTap: _pickImage,
                ),
                const SizedBox(height: 16),
                Text('Countdown duration (seconds)',
                    style: MtTextStyles.labelLg.copyWith(color: MtColors.ink2)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: 'e.g. 5',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null) return 'Enter a number of seconds';
                    if (n < 1 || n > 60) return 'Use 1–60 seconds';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _isActive
                        ? 'Patients see this ad at every app launch'
                        : 'Saved but hidden from patients',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                  value: _isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MtButton(
                        label: 'Cancel',
                        isOutlined: true,
                        onPressed:
                            _saving ? () {} : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MtButton(
                        label: _isEdit ? 'Save changes' : 'Create',
                        leadingIcon: Icons.check,
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable image slot: shows the freshly picked bytes, else the currently
/// stored image, else an upload prompt. Portrait-shaped to hint at the
/// full-screen phone canvas the ad will occupy.
class _AdImagePickerTile extends StatelessWidget {
  final Uint8List? pickedBytes;
  final String? existingUrl;
  final VoidCallback onTap;

  const _AdImagePickerTile({
    required this.pickedBytes,
    required this.existingUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (pickedBytes != null) {
      preview = Image.memory(pickedBytes!, fit: BoxFit.cover);
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      preview = AppNetworkImage(
        url: existingUrl,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
      );
    } else {
      preview = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate_outlined,
              size: 32, color: MtColors.ink3),
          const SizedBox(height: 8),
          Text('Tap to choose the ad image',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 220,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MtColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MtColors.line),
        ),
        child: preview,
      ),
    );
  }
}
