import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/promo_banner_providers.dart';
import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/promo_banner.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/image_upload.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_toast.dart';
import 'app_open_ad_panel.dart';

/// Curated two-stop gradient presets for the banner background. Stored on the
/// banner as a `List<String>` of HEX stops. Includes the rich orange-brown and
/// midnight-purple looks the Home slider uses.
class _GradientPreset {
  final String name;
  final List<String> colors;
  const _GradientPreset(this.name, this.colors);
}

const List<_GradientPreset> _kBannerGradientPresets = [
  _GradientPreset('Orange brown', ['#7C2D12', '#EA580C']),
  _GradientPreset('Midnight purple', ['#4C1D95', '#8B5CF6']),
  _GradientPreset('Clinical teal', ['#0F766E', '#2DD4BF']),
  _GradientPreset('Sapphire', ['#1E3A8A', '#3B82F6']),
  _GradientPreset('Emerald', ['#065F46', '#10B981']),
  _GradientPreset('Rose', ['#9F1239', '#FB7185']),
  _GradientPreset('Slate', ['#0F172A', '#475569']),
];

/// Admin CRUD + drag-to-reorder management for the patient Home promo banners.
///
/// Mirrors [ManageServicesTab] (scroll body + white list card + add/edit
/// [Dialog] + inline active toggle + edit/delete menu), and adds a
/// [ReorderableListView] whose drops persist the new `priorityOrder` via
/// `PromoBannerRepository.reorder`.
class AdminBannerManagementPage extends ConsumerWidget {
  const AdminBannerManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allBannersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Singleton app-open interstitial campaign — managed alongside the
          // Home-slider banners since both are patient-facing ad surfaces.
          const AppOpenAdPanel(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      async.maybeWhen(
                        data: (items) =>
                            '${items.length} banner${items.length == 1 ? '' : 's'}',
                        orElse: () => '',
                      ),
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Drag the handle to reorder — lower rows show first on the app home.',
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: MtButton(
                  label: 'Add banner',
                  leadingIcon: Icons.add,
                  onPressed: () => _openForm(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MtColors.line),
            ),
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBlock(
                message: e.toString(),
                onRetry: () => ref.refresh(allBannersProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No banners yet. Click "Add banner" to create the first one.',
                        style: MtTextStyles.bodyMd,
                      ),
                    ),
                  );
                }
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(context, ref, items, oldIndex, newIndex),
                  itemBuilder: (context, i) => _BannerRow(
                    key: ValueKey(items[i].id),
                    banner: items[i],
                    index: i,
                    isLast: i == items.length - 1,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    WidgetRef ref,
    List<PromoBanner> items,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot *before* removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final ids = reordered.map((b) => b.id).toList();
    try {
      await ref.read(promoBannerRepositoryProvider).reorder(ids);
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }

  static void _openForm(BuildContext context, WidgetRef ref,
      {PromoBanner? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _BannerFormDialog(existing: existing),
    );
  }
}

class _BannerRow extends ConsumerWidget {
  final PromoBanner banner;
  final int index;
  final bool isLast;
  const _BannerRow({
    required this.banner,
    required this.index,
    required this.isLast,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(promoBannerRepositoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: MtColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle_rounded, color: MtColors.ink3),
              ),
            ),
            _BannerThumb(banner: banner),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner.tagText,
                    style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    banner.title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelLg,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  banner.buttonText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.brand700),
                ),
              ),
            ),
            Row(
              children: [
                Switch(
                  value: banner.isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) async {
                    try {
                      await repo.setStatus(banner.id, v);
                    } catch (e) {
                      if (!context.mounted) return;
                      final (title, message) = mapBannerError(e);
                      MtToast.error(context, title, message);
                    }
                  },
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 58,
                  child: Text(
                    banner.isActive ? 'Active' : 'Hidden',
                    style: MtTextStyles.labelMd.copyWith(
                      color: banner.isActive ? MtColors.completed : MtColors.ink3,
                    ),
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: MtColors.ink2),
              onSelected: (action) async {
                if (action == 'edit') {
                  AdminBannerManagementPage._openForm(context, ref,
                      existing: banner);
                } else if (action == 'delete') {
                  await _confirmDelete(context, ref, banner);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, PromoBanner banner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete banner?'),
        content: Text(
            '"${banner.title.replaceAll('\n', ' ')}" will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MtColors.rejected),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(promoBannerRepositoryProvider).delete(banner);
      if (!context.mounted) return;
      MtToast.success(context, 'Banner deleted');
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = mapBannerError(e);
      MtToast.error(context, title, message);
    }
  }
}

/// A small rounded preview of the banner — its image if present, else its
/// gradient.
class _BannerThumb extends StatelessWidget {
  final PromoBanner banner;
  const _BannerThumb({required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 44,
        child: hasImage
            ? AppNetworkImage(
                url: banner.imageUrl,
                width: 64,
                height: 44,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => _gradientBox(),
                // Gradient + a broken-image glyph, so a failed load reads as
                // "this banner's image is broken" rather than being
                // indistinguishable from a gradient-only banner.
                errorBuilder: (_) => Stack(
                  fit: StackFit.expand,
                  children: [
                    _gradientBox(),
                    const Icon(Icons.broken_image_outlined,
                        size: 16, color: Colors.white70),
                  ],
                ),
              )
            : _gradientBox(),
      ),
    );
  }

  Widget _gradientBox() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: banner.gradient,
          ),
        ),
      );
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: MtColors.rejected, size: 32),
          const SizedBox(height: 12),
          Text(message, style: MtTextStyles.bodyMd, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(
            width: 140,
            child: MtButton(label: 'Retry', onPressed: onRetry, isOutlined: true),
          ),
        ],
      ),
    );
  }
}

// --- Form dialog ------------------------------------------------------------

class _BannerFormDialog extends ConsumerStatefulWidget {
  final PromoBanner? existing;
  const _BannerFormDialog({this.existing});

  @override
  ConsumerState<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends ConsumerState<_BannerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tagText;
  late final TextEditingController _title;
  late final TextEditingController _buttonText;
  late List<String> _gradient;
  late bool _isActive;
  PreparedImage? _pickedImage;
  bool _saving = false;

  // --- CTA deep-link destination ---------------------------------------
  late BannerActionType _actionType;
  ServiceCatalogItem? _targetService;
  late final TextEditingController _targetCategory;
  late final TextEditingController _targetUrl;
  late final TextEditingController _promoCode;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tagText = TextEditingController(text: e?.tagText ?? '');
    _title = TextEditingController(text: e?.title ?? '');
    _buttonText = TextEditingController(text: e?.buttonText ?? '');
    _gradient = e?.gradientColors ?? _kBannerGradientPresets.first.colors;
    _isActive = e?.isActive ?? true;

    _actionType = e?.actionType ?? BannerActionType.service;
    // The banner form doesn't fetch a single service by id, so it seeds the
    // picker from the populated snapshot the backend already sent
    // (`targetService`) — good enough to show "current: Wound Care Dressing"
    // even before the live catalog stream lands.
    final target = e?.targetService;
    _targetService = target == null
        ? null
        : ServiceCatalogItem(
            id: target.id,
            title: target.title,
            price: target.price,
            category: target.category,
            imageUrl: target.imageUrl,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
    _targetCategory = TextEditingController(text: e?.targetCategoryId ?? '');
    _targetUrl = TextEditingController(text: e?.targetUrl ?? '');
    _promoCode = TextEditingController(text: e?.promoCode ?? '');
  }

  @override
  void dispose() {
    _tagText.dispose();
    _title.dispose();
    _buttonText.dispose();
    _targetCategory.dispose();
    _targetUrl.dispose();
    _promoCode.dispose();
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
      // used to skip — the browser would otherwise send the full original and
      // trip multer's 8 MB cap.
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

  /// The target fields aren't `TextFormField`s wired into [_formKey] (the
  /// service picker isn't a text field at all), so the "target is required
  /// for this action type" rule is enforced here rather than through Form
  /// validation.
  String? _targetValidationError() {
    switch (_actionType) {
      case BannerActionType.service:
        return _targetService == null ? 'Choose a service to link to' : null;
      case BannerActionType.category:
        return _targetCategory.text.trim().isEmpty
            ? 'Choose a category to link to'
            : null;
      case BannerActionType.externalUrl:
        final url = _targetUrl.text.trim();
        if (url.isEmpty) return 'Enter a destination URL';
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          return 'Enter a valid URL, e.g. https://taafihealth.com/offers';
        }
        return null;
      case BannerActionType.promoCode:
        return _promoCode.text.trim().isEmpty ? 'Enter a promo code' : null;
      case BannerActionType.none:
        return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final targetError = _targetValidationError();
    if (targetError != null) {
      MtToast.error(context, 'Missing destination', targetError);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(promoBannerRepositoryProvider);
    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          tagText: _tagText.text.trim(),
          title: _title.text.trim(),
          buttonText: _buttonText.text.trim(),
          gradientColors: _gradient,
          isActive: _isActive,
          actionType: _actionType,
          targetServiceId: _actionType == BannerActionType.service
              ? _targetService?.id
              : null,
          targetCategoryId: _actionType == BannerActionType.category
              ? _targetCategory.text.trim()
              : null,
          targetUrl: _actionType == BannerActionType.externalUrl
              ? _targetUrl.text.trim()
              : '',
          promoCode: _actionType == BannerActionType.promoCode
              ? _promoCode.text.trim()
              : '',
        );
        await repo.update(updated, newImage: _pickedImage);
      } else {
        await repo.create(
          tagText: _tagText.text.trim(),
          title: _title.text.trim(),
          buttonText: _buttonText.text.trim(),
          gradientColors: _gradient,
          isActive: _isActive,
          actionType: _actionType,
          targetServiceId: _actionType == BannerActionType.service
              ? _targetService?.id
              : null,
          targetCategoryId: _actionType == BannerActionType.category
              ? _targetCategory.text.trim()
              : null,
          targetUrl: _actionType == BannerActionType.externalUrl
              ? _targetUrl.text.trim()
              : '',
          promoCode: _actionType == BannerActionType.promoCode
              ? _promoCode.text.trim()
              : '',
          image: _pickedImage,
        );
      }
      if (!mounted) return;
      // Fire the success toast (it lives on the root overlay, so it survives
      // the dialog dismissal) then close the form.
      MtToast.success(context, _isEdit ? 'Banner updated' : 'Banner created');
      Navigator.of(context).pop();
    } catch (e) {
      // A failed save keeps the dialog open so the admin can fix + retry
      // instead of losing their input. Map 404/401/500 to a clean
      // indigo/amber toast rather than surfacing the raw Dio exception.
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
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_isEdit ? 'Edit banner' : 'Add banner',
                    style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update the banner below. Leave the image empty to keep the current one.'
                      : 'Create a promo banner for the patient Home slider.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _GradientPreview(colors: _gradient),
                const SizedBox(height: 16),
                _ImagePickerTile(
                  pickedBytes: _pickedImage?.bytes,
                  existingUrl: widget.existing?.imageUrl,
                  onTap: _pickImage,
                ),
                const SizedBox(height: 16),
                _Label('Tag text'),
                _Field(
                  controller: _tagText,
                  hint: 'e.g. VERIFIED TEAM',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Tag text is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Title'),
                _Field(
                  controller: _title,
                  hint: 'e.g. MBBS doctors + certified aides',
                  maxLines: 2,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Button text'),
                _Field(
                  controller: _buttonText,
                  hint: 'e.g. Meet providers',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Button text is required'
                      : null,
                ),
                const SizedBox(height: 16),
                _Label('Action / Target destination'),
                _BannerActionFields(
                  actionType: _actionType,
                  targetService: _targetService,
                  targetCategoryController: _targetCategory,
                  targetUrlController: _targetUrl,
                  promoCodeController: _promoCode,
                  onActionTypeChanged: (t) => setState(() => _actionType = t),
                  onTargetServiceChanged: (s) =>
                      setState(() => _targetService = s),
                ),
                const SizedBox(height: 16),
                _Label('Background gradient'),
                _GradientPicker(
                  selected: _gradient,
                  onSelected: (colors) => setState(() => _gradient = colors),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _isActive
                        ? 'Visible in the patient Home slider'
                        : 'Hidden from patients',
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

/// Human-readable labels for [BannerActionType], shared by the dropdown and
/// any other admin surface that needs to render one.
const Map<BannerActionType, String> _kActionTypeLabels = {
  BannerActionType.service: 'Specific Service',
  BannerActionType.category: 'Service Category',
  BannerActionType.externalUrl: 'External Web URL',
  BannerActionType.promoCode: 'Apply Promo Code',
  BannerActionType.none: 'None (Display Only)',
};

/// The "Action / Target destination" block of the banner form — an
/// [BannerActionType] dropdown plus whichever single target field applies:
/// a searchable service picker, a category picker, a URL field, or a promo
/// code field. Only one target is ever sent to the backend (see
/// `PromoBannerRepository`), matching the schema's "only actionType's own
/// field is populated" contract.
class _BannerActionFields extends ConsumerWidget {
  final BannerActionType actionType;
  final ServiceCatalogItem? targetService;
  final TextEditingController targetCategoryController;
  final TextEditingController targetUrlController;
  final TextEditingController promoCodeController;
  final ValueChanged<BannerActionType> onActionTypeChanged;
  final ValueChanged<ServiceCatalogItem?> onTargetServiceChanged;

  const _BannerActionFields({
    required this.actionType,
    required this.targetService,
    required this.targetCategoryController,
    required this.targetUrlController,
    required this.promoCodeController,
    required this.onActionTypeChanged,
    required this.onTargetServiceChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<BannerActionType>(
          initialValue: actionType,
          decoration: _fieldDecoration(),
          items: [
            for (final entry in _kActionTypeLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v != null) onActionTypeChanged(v);
          },
        ),
        const SizedBox(height: 10),
        switch (actionType) {
          BannerActionType.service => _ServiceTargetPicker(
              selected: targetService,
              onChanged: onTargetServiceChanged,
            ),
          BannerActionType.category => _CategoryTargetPicker(
              controller: targetCategoryController,
            ),
          BannerActionType.externalUrl => _Field(
              controller: targetUrlController,
              hint: 'https://taafihealth.com/offers/first-visit',
            ),
          BannerActionType.promoCode => _Field(
              controller: promoCodeController,
              hint: 'e.g. TAAFI500',
            ),
          BannerActionType.none => Text(
              'The button renders but does nothing when tapped.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
        },
      ],
    );
  }
}

InputDecoration _fieldDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
    filled: true,
    fillColor: MtColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MtColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MtColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
    ),
  );
}

/// Type-ahead service picker backed by the live `activeServicesProvider`
/// stream (the same one the patient app books from — see `Service.js` +
/// `/api/services`). Shows the current pick as a dismissable chip below the
/// search field once one is made.
class _ServiceTargetPicker extends ConsumerWidget {
  final ServiceCatalogItem? selected;
  final ValueChanged<ServiceCatalogItem?> onChanged;

  const _ServiceTargetPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeServicesProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Text(
        "Couldn't load services: $e",
        style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
      ),
      data: (services) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Autocomplete<ServiceCatalogItem>(
            initialValue: TextEditingValue(text: selected?.title ?? ''),
            displayStringForOption: (s) => '${s.title} (৳${s.price.round()})',
            optionsBuilder: (v) {
              if (v.text.trim().isEmpty) return services;
              final q = v.text.trim().toLowerCase();
              return services.where((s) => s.title.toLowerCase().contains(q));
            },
            onSelected: onChanged,
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: MtTextStyles.bodyMd,
                decoration: _fieldDecoration(
                  hint: 'Search services, e.g. "Wound Care"',
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 512,
                    height: options.length > 4 ? 220 : options.length * 52,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final s = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          title: Text(s.title),
                          subtitle: s.category.isNotEmpty ? Text(s.category) : null,
                          trailing: Text('৳${s.price.round()}'),
                          onTap: () => onSelected(s),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Chip(
              label: Text('${selected!.title} · ৳${selected!.price.round()}'),
              onDeleted: () => onChanged(null),
              backgroundColor: MtColors.brandSoft,
              labelStyle: MtTextStyles.labelSm.copyWith(color: MtColors.brand700),
            ),
          ],
        ],
      ),
    );
  }
}

/// Category picker for [BannerActionType.category]. Services have no fixed
/// category taxonomy of their own (`Service.category` is admin free-text —
/// see `manage_services_tab.dart`), so the dropdown offers whatever distinct
/// values are already in use, and a text field underneath lets the admin
/// target a category that doesn't exist on any service yet.
class _CategoryTargetPicker extends ConsumerWidget {
  final TextEditingController controller;
  const _CategoryTargetPicker({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeServicesProvider);
    final categories = async.maybeWhen(
      data: (services) {
        final set = <String>{
          for (final s in services)
            if (s.category.trim().isNotEmpty) s.category.trim(),
        };
        return set.toList()..sort();
      },
      orElse: () => const <String>[],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categories.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: categories.contains(controller.text.trim())
                ? controller.text.trim()
                : null,
            decoration: _fieldDecoration(hint: 'Choose an existing category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => controller.text = v ?? '',
          ),
        if (categories.isNotEmpty) const SizedBox(height: 8),
        _Field(
          controller: controller,
          hint: categories.isEmpty
              ? 'e.g. Nursing Care'
              : 'Or type a category not listed above',
        ),
      ],
    );
  }
}

/// A live preview strip of the currently selected gradient.
class _GradientPreview extends StatelessWidget {
  final List<String> colors;
  const _GradientPreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    final parsed = PromoBanner(
      id: '',
      tagText: '',
      title: '',
      buttonText: '',
      gradientColors: colors,
    ).gradient;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: parsed,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'Gradient preview',
        style: MtTextStyles.labelMd.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Horizontal row of tappable gradient swatches. The selected preset gets a
/// ring; picking one reports its HEX stops upward.
class _GradientPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onSelected;
  const _GradientPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in _kBannerGradientPresets)
          _Swatch(
            preset: preset,
            isSelected: _listEquals(preset.colors, selected),
            onTap: () => onSelected(preset.colors),
          ),
      ],
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toUpperCase() != b[i].toUpperCase()) return false;
    }
    return true;
  }
}

class _Swatch extends StatelessWidget {
  final _GradientPreset preset;
  final bool isSelected;
  final VoidCallback onTap;
  const _Swatch({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = PromoBanner(
      id: '',
      tagText: '',
      title: '',
      buttonText: '',
      gradientColors: preset.colors,
    ).gradient;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: preset.name,
        child: Container(
          width: 56,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(
              color: isSelected ? MtColors.ink : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  final Uint8List? pickedBytes;
  final String? existingUrl;
  final VoidCallback onTap;

  const _ImagePickerTile({
    required this.pickedBytes,
    required this.existingUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (pickedBytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(pickedBytes!,
            fit: BoxFit.cover, width: double.infinity, height: 140),
      );
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      content = AppNetworkImage(
        url: existingUrl,
        width: double.infinity,
        height: 140,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(10),
        placeholderBuilder: (_) => Container(color: MtColors.bg, height: 140),
      );
    } else {
      content = Container(
        height: 140,
        decoration: BoxDecoration(
          color: MtColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MtColors.line),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, color: MtColors.ink3, size: 32),
              SizedBox(height: 8),
              Text('Tap to upload image (optional)', style: MtTextStyles.bodyMd),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: content,
        ),
        if (pickedBytes != null || (existingUrl != null && existingUrl!.isNotEmpty))
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Replace',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child:
          Text(text, style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: MtTextStyles.bodyMd,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.rejected),
        ),
      ),
    );
  }
}
