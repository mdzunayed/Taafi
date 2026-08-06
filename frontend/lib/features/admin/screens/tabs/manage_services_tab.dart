import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/category_providers.dart';
import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/home_category.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/models/provider_type.dart';
import '../../../../core/models/service_category.dart';
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
                onRetry: () => refreshServiceCatalog(ref),
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
          Expanded(flex: 4, child: Text('HOME TABS', style: _headerStyle)),
          Expanded(flex: 3, child: Text('ATTENDED BY', style: _headerStyle)),
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
          // Which Home tabs this service lands on — the mapping an operator
          // came here to check. Shows the resolved slugs rather than the raw
          // `category` string, because that is what the patient rail matches:
          // a service can be tagged "Recovery" and still appear under Post-op.
          Expanded(
            flex: 4,
            child: _HomeTabsCell(item: item),
          ),
          // Who attends — the field that words the patient's tracker. An
          // inferred value is shown in parentheses so a row nobody has
          // actually tagged is visible at a glance in the list.
          Expanded(
            flex: 3,
            child: Text(
              item.providerType == null
                  ? '—'
                  : item.providerTypeSource == 'assigned'
                      ? item.providerType!.roleLabel
                      : '${item.providerType!.roleLabel} (auto)',
              style: MtTextStyles.bodySm.copyWith(
                color: item.providerTypeSource == 'assigned'
                    ? MtColors.ink
                    : MtColors.ink3,
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

/// The Home tabs a service actually appears under, resolved the same way the
/// patient rail resolves them.
///
/// Reads `categorySlugs` (server-computed) rather than the ids, so a service
/// that reaches a pill through the legacy free-text `category` shows the pill
/// it lands on instead of an empty cell — which is the exact question this
/// column exists to answer. An "urgent" flag rides along, since it is the other
/// thing that decides whether a patient's filter finds this row.
class _HomeTabsCell extends ConsumerWidget {
  final ServiceCatalogItem item;
  const _HomeTabsCell({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(allCategoriesProvider).valueOrNull ?? const <HomeCategory>[];
    // Slug → the admin's own label, so the cell reads "Post-op", not "post-op".
    final labels = [
      for (final slug in item.categorySlugs)
        categories
                .where((c) => c.slug == slug)
                .map((c) => c.nameEn)
                .firstOrNull ??
            slug,
    ];

    if (labels.isEmpty && !item.isUrgentAvailable) {
      return Text(
        'All only',
        style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: MtTextStyles.labelSm.copyWith(color: MtColors.brand700),
            ),
          ),
        if (item.isUrgentAvailable)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: MtColors.surface2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: MtColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 12, color: MtColors.ink2),
                const SizedBox(width: 3),
                Text(
                  'Urgent',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2),
                ),
              ],
            ),
          ),
      ],
    );
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
  late final TextEditingController _duration;
  late ServiceCatalogStatus _status;
  PreparedImage? _pickedImage;
  bool _saving = false;

  /// The value that will be saved — '' (uncategorized), one of
  /// [kServiceCategories], or [_legacyCategory] while the admin leaves it be.
  String _category = '';

  /// The stored value when it maps to neither canonical category. Kept so the
  /// dropdown can offer it rather than silently resetting a service's category
  /// to blank the moment someone opens the form to change its price.
  String _legacyCategory = '';

  /// The Home pills this service is assigned to — the field behind "which
  /// category tab does this show up under". Multi-select: a service can
  /// legitimately be both post-op care and a doctor visit.
  ///
  /// A `Set` so ticking is idempotent and order can't matter; the API treats
  /// the first entry as primary only for the card badge.
  final Set<String> _categoryIds = {};

  /// True once [_categoryIds] was seeded from the legacy free-text category
  /// rather than read off the service. Surfaced in the form so an operator
  /// knows the ticks are a proposal they are about to make permanent, not
  /// something already stored.
  bool _seededFromLegacy = false;

  /// Can this be dispatched as an urgent/same-day visit? Drives the patient
  /// category view's "Urgent available" filter.
  bool _isUrgentAvailable = false;

  /// Who attends this service. Null = untagged, which is a real state: the API
  /// then infers a role from the title/category on every read. The form shows
  /// what that inference currently produces so the admin can confirm it in one
  /// tap instead of guessing what patients are being told.
  ProviderType? _providerType;

  /// The role the API inferred for an untagged service, echoed back on the
  /// payload as `provider_type` + `provider_type_source: 'inferred'`.
  ProviderType? _inferredProviderType;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _price = TextEditingController(text: e == null ? '' : e.price.toStringAsFixed(0));
    _description = TextEditingController(text: e?.description ?? '');
    _duration = TextEditingController(text: e?.duration ?? '');
    _status = e?.status ?? ServiceCatalogStatus.active;

    if (e != null && e.providerTypeSource == 'assigned') {
      _providerType = e.providerType;
    } else {
      _inferredProviderType = e?.providerType;
    }

    final raw = (e?.category ?? '').trim();
    _category = normalizeServiceCategory(raw);
    if (raw.isNotEmpty && _category.isEmpty) {
      _legacyCategory = raw;
      _category = raw; // select it, so nothing is dropped behind the admin's back
    }

    _isUrgentAvailable = e?.isUrgentAvailable ?? false;
    _categoryIds.addAll(e?.categoryIds ?? const []);
    // A service that has never been explicitly assigned currently reaches its
    // pill through the legacy free-text join. Pre-tick whatever it matches
    // today, so an operator who opens this form to change a price and saves
    // doesn't silently move the service somewhere else. `_seededFromLegacy`
    // makes that pre-tick visible rather than a hidden default.
    if (_categoryIds.isEmpty && e != null && e.categorySlugs.isNotEmpty) {
      _seededFromLegacy = true;
    }
  }

  /// Applies the pre-tick described in [initState], once the category list has
  /// actually loaded.
  ///
  /// Deferred to a post-frame callback because it lands during a build: the
  /// categories arrive asynchronously, so the earliest this can run is the
  /// frame that first renders them, and `setState` is illegal there.
  /// [_seededFromLegacy] deliberately stays true — the ticks are a proposal
  /// until the operator saves, and the form says so.
  void _maybeSeedCategories(List<HomeCategory> categories) {
    if (!_seededFromLegacy || _seedApplied) return;
    _seedApplied = true;
    final slugs = widget.existing?.categorySlugs ?? const <String>[];
    final seed = {
      for (final c in categories)
        if (slugs.contains(c.slug)) c.id,
    };
    if (seed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _categoryIds.addAll(seed));
    });
  }

  /// One-shot latch for [_maybeSeedCategories] — without it every rebuild
  /// would re-tick a pill the operator had just cleared.
  bool _seedApplied = false;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
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
    final duration =
        _duration.text.trim().isEmpty ? null : _duration.text.trim();
    try {
      if (_isEdit) {
        final existing = widget.existing!;
        // Built explicitly rather than with copyWith: that helper is
        // `duration ?? this.duration`, so passing null to clear a duration was
        // a no-op and an admin could never remove one. Every editable field
        // comes from the form; only the server-owned ones carry over.
        final updated = ServiceCatalogItem(
          id: existing.id,
          title: _title.text.trim(),
          price: double.parse(_price.text.trim()),
          description: _description.text.trim(),
          category: _category,
          categoryIds: _categoryIds.toList(),
          isUrgentAvailable: _isUrgentAvailable,
          providerType: _providerType,
          providerTypeSource: existing.providerTypeSource,
          duration: duration,
          imageUrl: existing.imageUrl,
          status: _status,
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
        );
        await repo.update(updated, newImage: _pickedImage);
      } else {
        await repo.create(
          title: _title.text.trim(),
          price: double.parse(_price.text.trim()),
          description: _description.text.trim(),
          category: _category,
          categoryIds: _categoryIds.toList(),
          isUrgentAvailable: _isUrgentAvailable,
          providerType: _providerType,
          duration: duration,
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
                // Distinct from 'Home categories' below on purpose: this is the
                // legacy free-text field that only decides placement when no
                // pill is picked, and two controls both labelled "Category" is
                // the confusion the combobox below exists to end.
                _Label('Catalog category (legacy)'),
                _CategoryDropdown(
                  value: _category,
                  legacyValue: _legacyCategory,
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 12),
                _Label('Home categories'),
                _CategoryCombobox(
                  selected: _categoryIds,
                  inherited: _seededFromLegacy,
                  onCategoriesLoaded: _maybeSeedCategories,
                  onChanged: (ids) => setState(() {
                    _categoryIds
                      ..clear()
                      ..addAll(ids);
                    // Once the operator touches the ticks they own them; the
                    // "inherited from the old category field" note goes away.
                    _seededFromLegacy = false;
                  }),
                ),
                const SizedBox(height: 12),
                _Label('Attended by'),
                _ProviderTypeDropdown(
                  value: _providerType,
                  inferred: _inferredProviderType,
                  onChanged: (v) => setState(() => _providerType = v),
                ),
                const SizedBox(height: 12),
                _Label('Duration / estimated time'),
                _Field(
                  controller: _duration,
                  hint: 'Optional, e.g. 30 min',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Urgent available', style: MtTextStyles.labelLg),
                  subtitle: Text(
                    _isUrgentAvailable
                        ? 'Listed under the "Urgent available" filter on the '
                            'patient category view'
                        : 'Only bookable on the normal schedule',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                  ),
                  value: _isUrgentAvailable,
                  activeColor: MtColors.brand,
                  onChanged: (v) => setState(() => _isUrgentAvailable = v),
                ),
                const SizedBox(height: 8),
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
  /// Fires per keystroke — used by the quick-create dialog to notice that the
  /// operator has taken the slug over from its auto-generated value.
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: MtTextStyles.bodyMd,
      decoration: _fieldDecoration(hint: hint),
    );
  }
}

/// Category picker for the service form.
///
/// Category used to be free text, which is how the database ended up with
/// three parallel vocabularies and a patient filter rail that matched almost
/// nothing. It is now a closed list — but deliberately **not required**: `''`
/// is a real, meaningful answer for the services that are neither post-op care
/// nor a doctor visit (lab collection, nurse-on-call), and forcing a pick would
/// just push operators into mis-tagging them.
///
/// [legacyValue] is a stored category that maps to neither canonical label. It
/// gets its own option plus a warning, because the backend normalizes on write:
/// leaving it selected and saving an unrelated price change *will* blank it,
/// and that is better said out loud than discovered later.
class _CategoryDropdown extends StatelessWidget {
  final String value;
  final String legacyValue;
  final ValueChanged<String> onChanged;

  const _CategoryDropdown({
    required this.value,
    required this.legacyValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasLegacy = legacyValue.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: _fieldDecoration(),
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Uncategorized — shows under All only'),
            ),
            for (final c in kServiceCategories)
              DropdownMenuItem(value: c, child: Text(c)),
            if (hasLegacy)
              DropdownMenuItem(
                value: legacyValue,
                child: Text('$legacyValue (legacy)'),
              ),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
        if (hasLegacy && value == legacyValue) ...[
          const SizedBox(height: 6),
          Text(
            "'$legacyValue' is no longer a recognised category. Saving will "
            'clear it. Pick Post-op or Doctor in Home to keep this service '
            'filterable on Home.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
          ),
        ],
      ],
    );
  }
}

/// One row in the combobox dropdown: an existing pill, or the inline
/// "create it now" action that closes the dead end when nothing matches.
sealed class _CategoryOption {
  const _CategoryOption();
}

class _ExistingCategoryOption extends _CategoryOption {
  final HomeCategory category;
  const _ExistingCategoryOption(this.category);
}

class _CreateCategoryOption extends _CategoryOption {
  final String query;
  const _CreateCategoryOption(this.query);
}

/// Searchable multi-select for the Home pills a service appears under — the
/// mapping behind "tap Post-op on Home and see these services".
///
/// Multi-select rather than a single dropdown because the relationship really
/// is many-to-many: post-operative physiotherapy delivered by a visiting doctor
/// belongs on both tabs, and forcing a single choice pushes operators into
/// duplicating the service instead. (The API accepts a singular `category_id`
/// on write for spec compatibility, but folds it into the same array.)
///
/// Replaces the wall of tick-capsules this used to render. Two rails' worth of
/// pills is a lot to scan, and the capsules had no answer at all for the common
/// case of "the category I need doesn't exist yet" — the operator had to
/// abandon a half-filled service form, go to Home → Categories, create it, and
/// start over. Typing a name that matches nothing now offers
/// `+ Create "<name>"` as the last row of the dropdown.
///
/// **Assignment here is authoritative.** Once any pill is picked, the legacy
/// free-text `Catalog category` field above stops deciding where the service
/// shows up (`resolveCategorySlugs` in the API). That is deliberate — otherwise
/// removing a pill would be a no-op — and it is why an unassigned service is
/// pre-filled from its current legacy match rather than opening empty.
class _CategoryCombobox extends ConsumerStatefulWidget {
  final Set<String> selected;

  /// True when the current picks were inherited from the legacy `category`
  /// field rather than read off the service — the form says so out loud.
  final bool inherited;

  /// Fired with the live category list on every build, so the parent (which
  /// owns the selection and the save) can run its one-shot legacy seed.
  final ValueChanged<List<HomeCategory>> onCategoriesLoaded;

  final ValueChanged<Set<String>> onChanged;

  const _CategoryCombobox({
    required this.selected,
    required this.inherited,
    required this.onCategoriesLoaded,
    required this.onChanged,
  });

  @override
  ConsumerState<_CategoryCombobox> createState() => _CategoryComboboxState();
}

class _CategoryComboboxState extends ConsumerState<_CategoryCombobox> {
  void _add(String id) => widget.onChanged({...widget.selected, id});

  void _remove(String id) =>
      widget.onChanged({...widget.selected}..remove(id));

  Future<void> _handle(_CategoryOption option) async {
    switch (option) {
      case _ExistingCategoryOption(:final category):
        _add(category.id);
      case _CreateCategoryOption(:final query):
        final created = await showDialog<HomeCategory>(
          context: context,
          builder: (_) => _QuickCreateCategoryDialog(initialName: query),
        );
        // Guarded: `onChanged` reaches the service form's setState, and the
        // create dialog is an await during which that form could have gone.
        if (created == null || !mounted) return;
        // The repository refetches on create, so the new pill is already in
        // `allCategoriesProvider` by the time this resolves — selecting it by
        // id is enough to make it show as a chip.
        _add(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allCategoriesProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text(
        "Couldn't load categories: $e",
        style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
      ),
      data: (categories) {
        // The parent owns the selection, so it also owns the one-shot legacy
        // seed — it is the only place that knows whether the operator has
        // since touched the picks, and it defers the actual mutation past
        // this build.
        widget.onCategoriesLoaded(categories);

        final byId = {for (final c in categories) c.id: c};
        // Selected ids that resolve to nothing are dropped rather than rendered
        // as a blank chip: the pill was deleted while this form was open, and
        // the API drops it on the next save anyway.
        final chosen = [
          for (final id in widget.selected)
            if (byId[id] != null) byId[id]!,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RawAutocomplete<_CategoryOption>(
              // Always empty: the field is a search box, not a display of the
              // current value (the chips below are). RawAutocomplete writes
              // this back into the field on selection, which is what clears the
              // query for the next pick — this being a multi-select, leaving
              // "Post-op" in the box would filter the next search to nothing.
              displayStringForOption: (_) => '',
              optionsBuilder: (value) => _optionsFor(value.text, categories),
              onSelected: _handle,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: MtTextStyles.bodyMd,
                  decoration: _fieldDecoration(
                    hint: categories.isEmpty
                        ? 'Type a name to create the first category'
                        : 'Search categories, or type a new name',
                  ).copyWith(
                    prefixIcon:
                        const Icon(Icons.search, size: 20, color: MtColors.ink3),
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
                      width: 460,
                      height: options.length > 4 ? 240 : options.length * 60,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (context, i) => _CategoryOptionTile(
                          option: options.elementAt(i),
                          onTap: () => onSelected(options.elementAt(i)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (chosen.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chosen)
                    Chip(
                      label: Text(
                        // A hidden pill stays assignable — the service
                        // reappears the moment it is un-hidden — but an
                        // operator should know patients can't see that tab.
                        c.isActive ? c.nameEn : '${c.nameEn} (hidden)',
                      ),
                      labelStyle: MtTextStyles.labelSm.copyWith(
                        color: c.isActive ? MtColors.brand700 : MtColors.ink2,
                      ),
                      backgroundColor:
                          c.isActive ? MtColors.brandSofter : MtColors.surface2,
                      side: BorderSide(
                        color: c.isActive ? MtColors.brand : MtColors.line,
                      ),
                      onDeleted: () => _remove(c.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              chosen.isEmpty
                  ? 'Not assigned — this service appears under the "All" tab '
                      'only, unless its Catalog category above happens to '
                      'match a pill.'
                  : widget.inherited
                      ? 'Inherited from the Catalog category field above — '
                          'this is where the service shows today. Saving makes '
                          'it explicit, and from then on these picks decide.'
                      : 'Shown under ${chosen.length} '
                          '${chosen.length == 1 ? 'tab' : 'tabs'} on '
                          'the patient Home screen.',
              style: MtTextStyles.bodySm.copyWith(
                color: widget.inherited ? MtColors.brand700 : MtColors.ink3,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Matching pills, then the inline create action.
  ///
  /// The action is withheld when an existing category already carries that
  /// name or would mint the same slug — `POST /api/categories` 409s on a
  /// duplicate slug, and offering a button whose only outcome is an error is
  /// worse than not offering it. Already-picked pills drop out of the list so
  /// the dropdown only ever shows something that changes the selection.
  List<_CategoryOption> _optionsFor(String raw, List<HomeCategory> categories) {
    final query = raw.trim();
    final q = query.toLowerCase();
    final matches = [
      for (final c in categories)
        if (!widget.selected.contains(c.id) &&
            (q.isEmpty ||
                c.nameEn.toLowerCase().contains(q) ||
                (c.nameBn ?? '').toLowerCase().contains(q) ||
                c.slug.contains(q)))
          _ExistingCategoryOption(c),
    ];
    if (query.isEmpty) return matches;

    final slug = categorySlugFor(query);
    final duplicate = categories.any(
      (c) => c.nameEn.toLowerCase() == q || (slug.isNotEmpty && c.slug == slug),
    );
    return [
      ...matches,
      if (!duplicate) _CreateCategoryOption(query),
    ];
  }
}

/// One dropdown row — an existing pill, or the `+ Create "…"` action rendered
/// distinctly so it never reads as just another category.
class _CategoryOptionTile extends StatelessWidget {
  final _CategoryOption option;
  final VoidCallback onTap;

  const _CategoryOptionTile({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    switch (option) {
      case _ExistingCategoryOption(:final category):
        return ListTile(
          dense: true,
          leading: const Icon(Icons.label_outline, size: 20),
          title: Text(category.nameEn),
          subtitle: Text(
            category.nameBn == null
                ? category.slug
                : '${category.nameBn}  ·  ${category.slug}',
          ),
          trailing: category.isActive
              ? null
              : Text(
                  'hidden',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
                ),
          onTap: onTap,
        );
      case _CreateCategoryOption(:final query):
        return ListTile(
          dense: true,
          leading: const Icon(Icons.add_circle_outline,
              size: 20, color: MtColors.brand),
          title: Text(
            'Create "$query"',
            style: MtTextStyles.labelMd.copyWith(color: MtColors.brand700),
          ),
          subtitle: Text(
            'New Home category · /${categorySlugFor(query)}',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          onTap: onTap,
        );
    }
  }
}

/// Inline category creation, without leaving the half-filled service form.
///
/// Deliberately the short form — name, Bengali name, slug. Icon, description,
/// and rail order are the full editor's job (Home → Categories); asking for
/// them here would turn a two-second detour back into the context switch this
/// exists to avoid. Everything omitted takes the API's own defaults, including
/// `displayOrder`, which lands the new pill at the end of the rail.
class _QuickCreateCategoryDialog extends ConsumerStatefulWidget {
  /// What the operator had typed into the combobox — the whole point of the
  /// inline action is that they don't retype it.
  final String initialName;

  const _QuickCreateCategoryDialog({required this.initialName});

  @override
  ConsumerState<_QuickCreateCategoryDialog> createState() =>
      _QuickCreateCategoryDialogState();
}

class _QuickCreateCategoryDialogState
    extends ConsumerState<_QuickCreateCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameEn;
  late final TextEditingController _nameBn;
  late final TextEditingController _slug;

  /// Stops mirroring [_nameEn] into [_slug] once the operator edits the slug
  /// themselves — the auto-generated value is a convenience, not a lock.
  bool _slugEdited = false;
  bool _saving = false;

  /// Server-side rejection (a 409 on a slug that already exists, most often),
  /// shown against the slug field rather than as a toast that disappears while
  /// they are still looking at the form.
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameEn = TextEditingController(text: widget.initialName);
    _nameBn = TextEditingController();
    _slug = TextEditingController(text: categorySlugFor(widget.initialName));
    _nameEn.addListener(_syncSlug);
  }

  void _syncSlug() {
    if (_slugEdited) return;
    final next = categorySlugFor(_nameEn.text);
    if (next == _slug.text) return;
    _slug.text = next;
  }

  @override
  void dispose() {
    _nameEn.removeListener(_syncSlug);
    _nameEn.dispose();
    _nameBn.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final bn = _nameBn.text.trim();
    try {
      final created = await ref.read(categoryRepositoryProvider).create(
            HomeCategory(
              id: '',
              nameEn: _nameEn.text.trim(),
              nameBn: bn.isEmpty ? null : bn,
              slug: _slug.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      // Kept open on failure so a duplicate slug can be corrected in place.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _categoryErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('New Home category', style: MtTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  'Creates the pill and assigns this service to it. You can add '
                  'an icon, description and rail order later under Home → '
                  'Categories.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
                const SizedBox(height: 20),
                _Label('Category name (English)'),
                _Field(
                  controller: _nameEn,
                  hint: 'e.g. Nursing',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _Label('Category name (Bengali)'),
                _Field(controller: _nameBn, hint: 'Optional, e.g. নার্সিং'),
                const SizedBox(height: 12),
                _Label('Slug'),
                _Field(
                  controller: _slug,
                  hint: 'e.g. nursing',
                  onChanged: (_) => _slugEdited = true,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Slug is required';
                    // Mirrors SAFE_SLUG in backend/src/routes/categories.js —
                    // anything else could never match a service and would come
                    // back as a 400 after a round trip.
                    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(s)) {
                      return 'Lowercase letters, digits and single hyphens';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'The join key patients filter by. Generated from the English '
                  'name — edit it only if you know what it has to match.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
                  ),
                ],
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
                        label: 'Create',
                        leadingIcon: Icons.check,
                        isLoading: _saving,
                        // `_saving` guards the double-click that would
                        // otherwise fire two POSTs, the second colliding with
                        // the unique slug index the first just claimed.
                        onPressed: _saving ? () {} : _save,
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

/// Prefers the backend's own message ("A category with slug \"x\" already
/// exists") over Dio's generic transport copy.
String _categoryErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
  }
  return 'Could not create the category: $error';
}

/// Picker for who attends a service — the field that words the patient's
/// booking tracker ("Nurse On the Way" vs "Doctor On the Way"), names the
/// registration number on the provider card, and selects the pre-arrival
/// preparation tip.
///
/// "Not set" is offered deliberately rather than forcing a pick. An untagged
/// service is not broken: the API infers a role from its title and category,
/// and [inferred] shows exactly what that inference produces, so an operator
/// can either confirm it in one tap or correct it — instead of a required
/// field pushing them to pick whatever is at the top of the list.
class _ProviderTypeDropdown extends StatelessWidget {
  final ProviderType? value;
  final ProviderType? inferred;
  final ValueChanged<ProviderType?> onChanged;

  const _ProviderTypeDropdown({
    required this.value,
    required this.inferred,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value?.toWire() ?? '',
          decoration: _fieldDecoration(),
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Not set — decided from the title'),
            ),
            for (final t in ProviderType.values)
              DropdownMenuItem(value: t.toWire(), child: Text(t.roleLabel)),
          ],
          onChanged: (v) => onChanged(ProviderTypeX.tryFromWire(v)),
        ),
        if (value == null) ...[
          const SizedBox(height: 6),
          Text(
            inferred == null
                ? 'Nothing can be read from this title, so bookings will be '
                    'tracked as nursing care. Pick a role to change that.'
                : 'Untagged: bookings are currently tracked as '
                    '${inferred!.roleLabel.toLowerCase()} visits, read from the '
                    'title and category. Pick a role to make it explicit.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ],
    );
  }
}

/// Shared input chrome, so the category dropdown lines up pixel-for-pixel with
/// the text fields above and below it.
InputDecoration _fieldDecoration({String? hint}) {
  OutlineInputBorder border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
    filled: true,
    fillColor: MtColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border(MtColors.line),
    enabledBorder: border(MtColors.line),
    focusedBorder: border(MtColors.brand, width: 1.5),
    errorBorder: border(MtColors.rejected),
  );
}
