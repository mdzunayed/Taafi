import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/category_providers.dart';
import '../../../../core/models/home_category.dart';
import '../../../../core/models/service_category.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_button.dart';
import '../../../../core/widgets/mt_toast.dart';
import '../../widgets/home_pill_preview.dart';

/// Prefers the backend's own message (e.g. "A category with slug ... already
/// exists" on a 409) before falling back to the shared status-code copy.
(String, String) _mapCategoryError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return ('Could not save category', data['message'] as String);
    }
  }
  return mapBannerError(error);
}

/// Admin CRUD + drag-to-reorder for the patient Home filter pills.
///
/// Mirrors [AdminHomeSectionsPage] (scroll body + white list card + add/edit
/// [Dialog] + inline active toggle + edit/delete menu + [ReorderableListView]
/// persisting `displayOrder` via `CategoryRepository.reorder`).
///
/// The rail preview at the top is the patient app's real pill widget
/// ([HomePillPreview] wraps it with the patient theme), so what an operator
/// approves here is what ships — a CMS that draws its own approximation of a
/// chip drifts from the app the moment either side moves.
class AdminHomeCategoriesPage extends ConsumerWidget {
  const AdminHomeCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allCategoriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      async.maybeWhen(
                        data: (items) =>
                            '${items.length} categor${items.length == 1 ? 'y' : 'ies'}',
                        orElse: () => '',
                      ),
                      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Filter pills on the app home, above the promo banners. '
                      'Drag the handle to reorder — lower rows show first. '
                      'An "All" pill is always shown first and cannot be removed.',
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: MtButton(
                  label: 'Add category',
                  leadingIcon: Icons.add,
                  onPressed: () => _openForm(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          async.maybeWhen(
            data: (items) => _RailPreview(categories: items),
            orElse: () => const SizedBox.shrink(),
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
                onRetry: () => ref.invalidate(categoryRepositoryProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No categories yet. The app falls back to its built-in '
                        'Post-op / Doctor in Home chips until you add one.',
                        textAlign: TextAlign.center,
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
                  itemBuilder: (context, i) => _CategoryRow(
                    key: ValueKey(items[i].id),
                    category: items[i],
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
    List<HomeCategory> items,
    int oldIndex,
    int newIndex,
  ) async {
    // ReorderableListView reports newIndex as the slot *before* removal.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    try {
      await ref
          .read(categoryRepositoryProvider)
          .reorder(reordered.map((c) => c.id).toList());
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = _mapCategoryError(e);
      MtToast.error(context, title, message);
    }
  }

  static void _openForm(BuildContext context, WidgetRef ref,
      {HomeCategory? existing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _CategoryFormDialog(existing: existing),
    );
  }
}

/// The rail exactly as the patient sees it, hidden pills excluded and the
/// implicit "All" pill leading — the thing an operator is really editing.
class _RailPreview extends StatelessWidget {
  final List<HomeCategory> categories;
  const _RailPreview({required this.categories});

  @override
  Widget build(BuildContext context) {
    final visible = categories.where((c) => c.isActive).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview on patient Home',
              style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
          const SizedBox(height: 4),
          Text(
            visible.isEmpty
                ? 'No visible categories — the app shows its built-in chips.'
                : '${visible.length} visible pill${visible.length == 1 ? '' : 's'}, '
                    'plus the implicit "All".',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          const SizedBox(height: 14),
          HomePillPreview(
            categories: [HomeCategory.all, ...visible],
            selectedIndex: 0,
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  final HomeCategory category;
  final int index;
  final bool isLast;

  const _CategoryRow({
    required this.category,
    required this.index,
    required this.isLast,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(categoryRepositoryProvider);

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
            _CategoryIconThumb(url: category.iconUrl),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.nameEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelLg,
                  ),
                  if (category.nameBn != null && category.nameBn!.isNotEmpty)
                    Text(
                      category.nameBn!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  category.slug,
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
                  value: category.isActive,
                  activeThumbColor: MtColors.brand,
                  onChanged: (v) async {
                    try {
                      await repo.setStatus(category.id, v);
                    } catch (e) {
                      if (!context.mounted) return;
                      final (title, message) = _mapCategoryError(e);
                      MtToast.error(context, title, message);
                    }
                  },
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 58,
                  child: Text(
                    category.isActive ? 'Active' : 'Hidden',
                    style: MtTextStyles.labelMd.copyWith(
                      color: category.isActive
                          ? MtColors.completed
                          : MtColors.ink3,
                    ),
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: MtColors.ink2),
              onSelected: (action) async {
                if (action == 'edit') {
                  AdminHomeCategoriesPage._openForm(context, ref,
                      existing: category);
                } else if (action == 'delete') {
                  await _confirmDelete(context, ref, category);
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
      BuildContext context, WidgetRef ref, HomeCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'The "${category.nameEn}" pill will be removed from the app home. '
          'Services tagged "${category.slug}" are NOT deleted — they stay '
          'visible under the "All" pill.\n\n'
          'To hide the pill temporarily, switch it off instead.',
        ),
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
      await ref.read(categoryRepositoryProvider).delete(category);
      if (!context.mounted) return;
      MtToast.success(context, 'Category deleted');
    } catch (e) {
      if (!context.mounted) return;
      final (title, message) = _mapCategoryError(e);
      MtToast.error(context, title, message);
    }
  }
}

/// The pill's icon, or a neutral placeholder. Uses [Image.network] rather than
/// the cached variant so a just-changed URL repaints immediately.
class _CategoryIconThumb extends StatelessWidget {
  final String? url;
  const _CategoryIconThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: u.isEmpty
          ? const Icon(Icons.label_outline, color: MtColors.ink3, size: 20)
          : Image.network(
              u,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined,
                  color: MtColors.ink3, size: 20),
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

// --- Form dialog ------------------------------------------------------------

/// Add / edit one pill, with a live preview of the chip that repaints per
/// keystroke.
class _CategoryFormDialog extends ConsumerStatefulWidget {
  final HomeCategory? existing;
  const _CategoryFormDialog({this.existing});

  @override
  ConsumerState<_CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameEn;
  late final TextEditingController _nameBn;
  late final TextEditingController _descriptionEn;
  late final TextEditingController _descriptionBn;
  late final TextEditingController _slug;
  late final TextEditingController _iconUrl;
  late bool _isActive;
  bool _saving = false;

  /// True until the admin edits the slug by hand. While set, the slug tracks
  /// the English name — which is what makes the field a detail most operators
  /// never have to think about — and once they take control, typing a name no
  /// longer silently re-points the pill at a different set of services.
  late bool _slugFollowsName;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameEn = TextEditingController(text: e?.nameEn ?? '');
    _nameBn = TextEditingController(text: e?.nameBn ?? '');
    _descriptionEn = TextEditingController(text: e?.descriptionEn ?? '');
    _descriptionBn = TextEditingController(text: e?.descriptionBn ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _iconUrl = TextEditingController(text: e?.iconUrl ?? '');
    _isActive = e?.isActive ?? true;
    // An existing pill's slug is already load-bearing, so never auto-rewrite
    // it; a new one has nothing to break.
    _slugFollowsName = e == null;
  }

  @override
  void dispose() {
    _nameEn.dispose();
    _nameBn.dispose();
    _descriptionEn.dispose();
    _descriptionBn.dispose();
    _slug.dispose();
    _iconUrl.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_slugFollowsName) _slug.text = slugifyCategory(value);
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    final draft = HomeCategory(
      id: widget.existing?.id ?? '',
      nameEn: _nameEn.text.trim(),
      nameBn: _nameBn.text.trim().isEmpty ? null : _nameBn.text.trim(),
      descriptionEn: _descriptionEn.text.trim().isEmpty
          ? null
          : _descriptionEn.text.trim(),
      descriptionBn: _descriptionBn.text.trim().isEmpty
          ? null
          : _descriptionBn.text.trim(),
      slug: slugifyCategory(_slug.text),
      iconUrl: _iconUrl.text.trim().isEmpty ? null : _iconUrl.text.trim(),
      displayOrder: widget.existing?.displayOrder ?? 0,
      isActive: _isActive,
    );
    try {
      if (widget.existing == null) {
        await repo.create(draft);
      } else {
        await repo.update(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      MtToast.success(
        context,
        widget.existing == null ? 'Category added' : 'Category updated',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final (title, message) = _mapCategoryError(e);
      MtToast.error(context, title, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    // Built from the form's current text, not from the saved document, so the
    // preview is what pressing Save would produce.
    final preview = HomeCategory(
      id: 'preview',
      nameEn: _nameEn.text.trim().isEmpty ? 'Category' : _nameEn.text.trim(),
      nameBn: _nameBn.text.trim().isEmpty ? null : _nameBn.text.trim(),
      slug: slugifyCategory(_slug.text),
      iconUrl: _iconUrl.text.trim().isEmpty ? null : _iconUrl.text.trim(),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(isEdit ? 'Edit category' : 'Add category',
                        style: MtTextStyles.h3),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: MtColors.ink3),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('Name (English)'),
                      TextFormField(
                        controller: _nameEn,
                        onChanged: _onNameChanged,
                        decoration: _decoration('e.g. Nursing'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const _Label('Name (Bengali) — optional'),
                      TextFormField(
                        controller: _nameBn,
                        onChanged: (_) => setState(() {}),
                        decoration: _decoration('e.g. নার্সিং'),
                      ),
                      const SizedBox(height: 16),
                      // The blurb under the title on the patient's dedicated
                      // category view. Optional: the header falls back to the
                      // title plus the live service count on its own.
                      const _Label('Description (English) — optional'),
                      TextFormField(
                        controller: _descriptionEn,
                        maxLines: 2,
                        decoration: _decoration(
                          'e.g. Licensed doctors visiting your home for '
                          'consultations.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _Label('Description (Bengali) — optional'),
                      TextFormField(
                        controller: _descriptionBn,
                        maxLines: 2,
                        decoration: _decoration('e.g. বাড়িতে ডাক্তারের সেবা।'),
                      ),
                      const SizedBox(height: 16),
                      const _Label('Icon URL — optional'),
                      TextFormField(
                        controller: _iconUrl,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            _decoration('https://cdn.taafi.app/icons/nurse.png'),
                      ),
                      const SizedBox(height: 16),
                      _SlugField(
                        controller: _slug,
                        locked: !_slugFollowsName,
                        onUnlock: () => setState(() => _slugFollowsName = false),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _isActive,
                        activeThumbColor: MtColors.brand,
                        title: Text('Visible on app home',
                            style: MtTextStyles.labelMd),
                        subtitle: Text(
                          'Hidden pills stay editable and keep their services.',
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink3),
                        ),
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        decoration: BoxDecoration(
                          color: MtColors.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Preview',
                                style: MtTextStyles.labelSm
                                    .copyWith(color: MtColors.ink3)),
                            const SizedBox(height: 10),
                            HomePillPreview(
                              categories: [preview, HomeCategory.all],
                              selectedIndex: 0,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: MtButton(
                      label: 'Cancel',
                      isOutlined: true,
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MtButton(
                      label: isEdit ? 'Save changes' : 'Add category',
                      isLoading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The slug input. Read-only and auto-derived from the name until the admin
/// explicitly takes it over, with the consequence spelled out — this is the
/// field that decides which services a pill catches.
class _SlugField extends StatelessWidget {
  final TextEditingController controller;
  final bool locked;
  final VoidCallback onUnlock;
  final ValueChanged<String> onChanged;

  const _SlugField({
    required this.controller,
    required this.locked,
    required this.onUnlock,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _Label('Matching slug')),
            if (locked)
              TextButton(
                onPressed: onUnlock,
                style: TextButton.styleFrom(
                  foregroundColor: MtColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Edit', style: MtTextStyles.labelSm),
              ),
          ],
        ),
        TextFormField(
          controller: controller,
          readOnly: locked,
          onChanged: onChanged,
          style: MtTextStyles.bodyMd
              .copyWith(color: locked ? MtColors.ink3 : null),
          decoration: _decoration('doctor-in-home'),
          validator: (v) {
            final s = slugifyCategory(v ?? '');
            if (s.isEmpty) return 'Slug is required';
            return null;
          },
        ),
        const SizedBox(height: 6),
        Text(
          locked
              ? 'Derived from the English name. A service appears under this '
                  'pill when its category matches the slug.'
              : 'Changing this re-points the pill at a different set of '
                  'services. Existing services are not re-tagged.',
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
      );
}

InputDecoration _decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
      filled: true,
      fillColor: MtColors.bg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        borderSide: const BorderSide(color: MtColors.brand),
      ),
    );
