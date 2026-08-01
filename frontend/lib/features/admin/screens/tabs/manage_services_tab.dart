import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/image_upload.dart';
import '../../../../core/widgets/mt_button.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

class ManageServicesTab extends ConsumerWidget {
  const ManageServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allServicesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  async.maybeWhen(
                    data: (items) => '${items.length} service${items.length == 1 ? '' : 's'}',
                    orElse: () => '',
                  ),
                  style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                ),
              ),
              SizedBox(
                width: 200,
                child: MtButton(
                  label: 'Create service',
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
                onRetry: () => ref.refresh(allServicesProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No services yet. Click "Create service" to add the first one.',
                        style: MtTextStyles.bodyMd,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    const _Header(),
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: MtColors.line),
                      _ServiceRow(item: items[i]),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _openForm(BuildContext context, WidgetRef ref, {ServiceCatalogItem? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _ServiceFormDialog(existing: existing),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 56),
          Expanded(flex: 4, child: Text('TITLE', style: _headerStyle)),
          Expanded(flex: 3, child: Text('CATEGORY', style: _headerStyle)),
          Expanded(flex: 2, child: Text('PRICE', style: _headerStyle)),
          Expanded(flex: 2, child: Text('STATUS', style: _headerStyle)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  static final _headerStyle = MtTextStyles.labelSm.copyWith(color: MtColors.ink3);
}

class _ServiceRow extends ConsumerWidget {
  final ServiceCatalogItem item;
  const _ServiceRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(serviceCatalogRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _Thumb(url: item.imageUrl),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: MtTextStyles.labelLg),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: item.category.isEmpty
                ? Text('—', style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: MtColors.brandSofter,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category,
                      style: MtTextStyles.labelSm.copyWith(color: MtColors.brand700),
                    ),
                  ),
          ),
          Expanded(
            flex: 2,
            child: Text(_money(item.price), style: MtTextStyles.labelLg),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Switch(
                  value: item.isActive,
                  activeColor: MtColors.brand,
                  onChanged: (v) async {
                    try {
                      await repo.setStatus(
                        item.id,
                        v ? ServiceCatalogStatus.active : ServiceCatalogStatus.inactive,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      _snack(context, 'Failed to update status: $e', error: true);
                    }
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  item.isActive ? 'Active' : 'Inactive',
                  style: MtTextStyles.labelMd.copyWith(
                    color: item.isActive ? MtColors.completed : MtColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: MtColors.ink2),
            onSelected: (action) async {
              if (action == 'edit') {
                ManageServicesTab._openForm(context, ref, existing: item);
              } else if (action == 'delete') {
                await _confirmDelete(context, ref, item);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ServiceCatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('"${item.title}" will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
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
      await ref.read(serviceCatalogRepositoryProvider).delete(item);
      if (!context.mounted) return;
      _snack(context, 'Service deleted');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Failed to delete: $e', error: true);
    }
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: (url == null || url!.isEmpty)
            ? Container(
                color: MtColors.bg,
                child: const Icon(Icons.image_outlined, color: MtColors.ink3),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: MtColors.bg),
                errorWidget: (_, __, ___) => Container(
                  color: MtColors.bg,
                  child: const Icon(Icons.broken_image_outlined, color: MtColors.ink3),
                ),
              ),
      ),
    );
  }
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

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ),
  );
}

// --- Form dialog ------------------------------------------------------------

class _ServiceFormDialog extends ConsumerStatefulWidget {
  final ServiceCatalogItem? existing;
  const _ServiceFormDialog({this.existing});

  @override
  ConsumerState<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends ConsumerState<_ServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _duration;
  late ServiceCatalogStatus _status;
  PreparedImage? _pickedImage;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _price = TextEditingController(text: e == null ? '' : e.price.toStringAsFixed(0));
    _description = TextEditingController(text: e?.description ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _duration = TextEditingController(text: e?.duration ?? '');
    _status = e?.status ?? ServiceCatalogStatus.active;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    _category.dispose();
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
      // used to skip.
      final prepared = await prepareImageBytesForUpload(
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      setState(() => _pickedImage = prepared);
    } on UnsupportedImageException catch (e) {
      if (!mounted) return;
      _snack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Could not pick image: $e', error: true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _pickedImage == null) {
      _snack(context, 'Please pick a service photo', error: true);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(serviceCatalogRepositoryProvider);
    try {
      if (_isEdit) {
        final existing = widget.existing!;
        final updated = existing.copyWith(
          title: _title.text.trim(),
          price: double.parse(_price.text.trim()),
          description: _description.text.trim(),
          category: _category.text.trim(),
          duration: _duration.text.trim().isEmpty ? null : _duration.text.trim(),
          status: _status,
        );
        await repo.update(updated, newImage: _pickedImage);
      } else {
        await repo.create(
          title: _title.text.trim(),
          price: double.parse(_price.text.trim()),
          description: _description.text.trim(),
          category: _category.text.trim(),
          duration: _duration.text.trim().isEmpty ? null : _duration.text.trim(),
          status: _status,
          image: _pickedImage!,
        );
      }
      if (!mounted) return;
      // Message BEFORE popping. `_snack` resolves ScaffoldMessenger from this
      // dialog's context, so calling it after the pop targeted a deactivated
      // element and the confirmation never appeared — a successful save
      // looked like nothing had happened. The banner/ad dialogs already
      // order it this way.
      _snack(context, _isEdit ? 'Service updated' : 'Service created');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, 'Failed to save: $e', error: true);
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
                Text(_isEdit ? 'Edit service' : 'Create service', style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  _isEdit
                      ? 'Update fields below. Leave the photo empty to keep the existing one.'
                      : 'Add a new service to the patient catalog.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _ImagePickerTile(
                  pickedBytes: _pickedImage?.bytes,
                  existingUrl: widget.existing?.imageUrl,
                  onTap: _pickImage,
                ),
                const SizedBox(height: 16),
                _Label('Title'),
                _Field(
                  controller: _title,
                  hint: 'e.g. Wound dressing',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                _Label('Price (৳)'),
                _Field(
                  controller: _price,
                  hint: 'e.g. 800',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim());
                    if (parsed == null) return 'Enter a valid number';
                    if (parsed <= 0) return 'Price must be greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _Label('Short description'),
                _Field(
                  controller: _description,
                  hint: 'Optional',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _Label('Category'),
                _Field(
                  controller: _category,
                  hint: 'e.g. Consultation / Lab Test / Home Visit',
                ),
                const SizedBox(height: 12),
                _Label('Duration / estimated time'),
                _Field(
                  controller: _duration,
                  hint: 'Optional, e.g. 30 min',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _status == ServiceCatalogStatus.active
                        ? 'Visible to patients'
                        : 'Hidden from patients',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                  value: _status == ServiceCatalogStatus.active,
                  activeColor: MtColors.brand,
                  onChanged: (v) => setState(() => _status =
                      v ? ServiceCatalogStatus.active : ServiceCatalogStatus.inactive),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MtButton(
                        label: 'Cancel',
                        isOutlined: true,
                        onPressed: _saving ? () {} : () => Navigator.of(context).pop(),
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
        child: Image.memory(pickedBytes!, fit: BoxFit.cover, width: double.infinity, height: 160),
      );
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: existingUrl!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 160,
          placeholder: (_, __) => Container(color: MtColors.bg, height: 160),
          errorWidget: (_, __, ___) => Container(
            color: MtColors.bg,
            height: 160,
            child: const Icon(Icons.broken_image_outlined, color: MtColors.ink3),
          ),
        ),
      );
    } else {
      content = Container(
        height: 160,
        decoration: BoxDecoration(
          color: MtColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MtColors.line, style: BorderStyle.solid),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, color: MtColors.ink3, size: 32),
              SizedBox(height: 8),
              Text('Tap to upload photo', style: MtTextStyles.bodyMd),
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
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
      child: Text(text, style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
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
