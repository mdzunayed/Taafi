import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/api/service_catalog_providers.dart';
import '../../../core/models/dependent.dart';
import '../../../core/models/request_document.dart';
import '../../../core/models/saved_address.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/age.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../auth/auth_provider.dart' show dioClientProvider;
import '../checkout/booking_summary_screen.dart';
import '../checkout/widgets/booking_stepper.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import '../new_request/new_request_state.dart';
import '../profile/patient_lifecycle_providers.dart';
import 'family_profiles_screen.dart';
import 'widgets/active_booking_banner.dart';

/// New care-request flow. Pure ConsumerWidget — all form state lives in
/// [newRequestProvider], all dependency data flows through Riverpod providers.
class NewRequestTab extends ConsumerStatefulWidget {
  const NewRequestTab({super.key});

  @override
  ConsumerState<NewRequestTab> createState() => _NewRequestTabState();
}

/// Mirrors the 8 MB cap on `POST /patient/documents` (multer). Checked
/// client-side too so an oversized scan fails instantly instead of after a
/// full upload.
const int _kMaxDocumentBytes = 8 * 1024 * 1024;

class _NewRequestTabState extends ConsumerState<NewRequestTab> {
  late final TextEditingController _notesController;

  /// A document upload is in flight — the attach row shows a spinner and
  /// refuses a second pick until it lands.
  bool _uploadingDocument = false;
  // Tracks whether the form has been hydrated from the notifier on first
  // build, so we don't fight the user every time they type.
  String? _lastNotesSnapshot;

  // Drives the "resume at the next step" scroll after a link-driven prefill.
  final _scrollController = ScrollController();
  final _recipientSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Skips the patient past the service step after they arrived from a card
  /// that already answered it — the form scrolls to "Who is this care session
  /// for?", the next unanswered question. Deferred a frame so the collapsed
  /// summary card has laid out before we measure. No-ops while the tab is
  /// off-screen in the shell's IndexedStack (nothing to scroll yet); the
  /// tab-switch that follows the tap rebuilds and runs it.
  void _scrollToRecipientStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ctx = _recipientSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  void _syncControllers(NewRequestState s) {
    // Only push notifier changes into the controller when they originate from
    // outside (e.g. prefill). Typing back through the controller already
    // updates the notifier via onChanged.
    if (_lastNotesSnapshot != s.notes && s.notes != _notesController.text) {
      _notesController.text = s.notes;
      _notesController.selection = TextSelection.collapsed(
        offset: s.notes.length,
      );
    }
    _lastNotesSnapshot = s.notes;
  }

  /// Step 1 → Step 2. Nothing is sent to the backend here: the booking is
  /// only created once the patient confirms on the Checkout step, so backing
  /// out of the summary leaves no orphaned `awaiting_deposit` rows behind.
  void _continueToSummary() {
    HapticFeedback.lightImpact();
    // Commit anything still sitting in the notes field (the patient can tap
    // Continue without unfocusing it).
    ref.read(newRequestProvider.notifier).setNotes(_notesController.text);
    Navigator.of(context).push(BookingSummaryScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newRequestProvider);
    final servicesAsync = ref.watch(activeServicesProvider);
    final hasActiveBooking = ref.watch(patientActiveRequestProvider) != null;
    _syncControllers(state);

    // A card the patient tapped (home section linked to a service, promo
    // banner, catalog entry) already answered the service question — jump the
    // form to the next one instead of reopening a list they just chose from.
    ref.listen<bool>(
      newRequestProvider.select((s) => s.servicePrefilled),
      (was, now) {
        if (now && was != true) _scrollToRecipientStep();
      },
    );

    // The catalog deliberately opens with nothing selected. It used to
    // auto-select `list.first` to keep the form immediately usable, but that
    // put a service the patient never chose behind an enabled "Continue" — and
    // once the form stopped being reset between visits it was indistinguishable
    // from stale state. `validate()` already has the message for the empty
    // case, and the submit bar stays disabled until a real choice is made.

    // Hydrate the location card from the user's saved-address book. The API
    // returns the default (`is_default`) address first, so `list.first` is the
    // primary. We only apply it while the form still has no address chosen, so
    // we never stomp a selection the patient made via the address picker.
    ref.listen<AsyncValue<List<SavedAddress>>>(savedAddressesProvider,
        (prev, next) {
      next.whenData((list) {
        if (list.isEmpty) return;
        if (!ref.read(newRequestProvider).address.isEmpty) return;
        Future.microtask(() {
          if (!mounted) return;
          if (!ref.read(newRequestProvider).address.isEmpty) return;
          ref
              .read(newRequestProvider.notifier)
              .applyAddress(_toRequestAddress(list.first));
        });
      });
    });

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
      children: [
        _Header(
          onBack: ref.goToHome,
        ),
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (state.promoCode != null && state.promoCode!.isNotEmpty) ...[
                _PromoCodeBanner(
                  code: state.promoCode!,
                  onClear: () =>
                      ref.read(newRequestProvider.notifier).clearPromoCode(),
                ),
                const SizedBox(height: 16),
              ],
              const _SectionHeader(en: 'Type of care', bn: 'সেবার ধরন'),
              const SizedBox(height: 8),
              // Pre-selected from the card the patient tapped → show what was
              // chosen with a "Change" escape hatch, rather than a list.
              if (state.servicePrefilled && state.selectedService != null)
                _PreselectedServiceCard(
                  service: state.selectedService!,
                  onChange: () => ref
                      .read(newRequestProvider.notifier)
                      .expandServiceSelection(),
                )
              else
                _ServiceSelector(
                  async: servicesAsync,
                  selectedId: state.selectedService?.id,
                ),
              const SizedBox(height: 20),
              _SectionHeader(
                key: _recipientSectionKey,
                en: 'Who is this care session for?',
                bn: 'এই সেবা কার জন্য?',
              ),
              const SizedBox(height: 8),
              _CareRecipientChips(selected: state.careRecipient),
              const SizedBox(height: 20),
              // Location + timing moved to the Checkout step (step 3) —
              // this step answers *what care and for whom*, checkout answers
              // *where, when and how you pay*.
              const _SectionHeader(
                en: 'Notes for medical team',
                bn: 'চিকিৎসা সংক্রান্ত তথ্য',
              ),
              const SizedBox(height: 8),
              _NotesCard(
                controller: _notesController,
                documents: state.documents,
                uploading: _uploadingDocument,
                onNotesChanged: (v) =>
                    ref.read(newRequestProvider.notifier).setNotes(v),
                onAttachDocument: _attachDocument,
                onRemoveDocument: (d) =>
                    ref.read(newRequestProvider.notifier).removeDocument(d),
              ),
              if (state.validationError != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: state.validationError ?? ''),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
        _SubmitBar(
          // One booking at a time — `POST /patient/requests` answers 409
          // while a non-terminal request is open, so the flow is sealed at
          // its entrance and the banner offers the way out (jump to the open
          // booking) rather than letting the patient reach checkout first.
          blocked: hasActiveBooking,
          enabled: state.selectedService != null && !hasActiveBooking,
          onSubmit: _continueToSummary,
        ),
      ],
      ),
    );
  }

  // --------------------------------------------------------------- dialogs

  /// Maps a saved-address-book entry into the booking form's [RequestAddress].
  /// Used by the default-address hydration listener above; the Checkout step
  /// applies the same mapping when the patient picks a different address.
  static RequestAddress _toRequestAddress(SavedAddress a) {
    return RequestAddress(
      line1: a.flatFloorHolding,
      areaCityZip: a.fullAddressText,
      label: a.label,
      landmark: a.landmarkInstructions.trim().isEmpty
          ? null
          : a.landmarkInstructions.trim(),
      latitude: a.latitude,
      longitude: a.longitude,
    );
  }

  /// Attach a previous medical document (PDF or image) from device storage.
  ///
  /// Uploads immediately rather than at submit: the booking doesn't exist
  /// yet, and uploading here means the patient sees a failure (wrong type,
  /// too large, no signal) while they can still do something about it,
  /// instead of at the moment they confirm and pay.
  Future<void> _attachDocument() async {
    if (_uploadingDocument) return;
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.appColors.danger;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      // The bytes are what we post; on mobile the picker only fills `path`
      // unless this is set.
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    if (bytes.length > _kMaxDocumentBytes) {
      messenger.showSnackBar(SnackBar(
        content: const Text('That file is larger than the 8 MB limit.'),
        backgroundColor: dangerColor,
      ));
      return;
    }

    setState(() => _uploadingDocument = true);
    try {
      final doc = await ref.read(dioClientProvider).uploadPatientDocument(
            bytes: bytes,
            filename: file.name,
            mimeType: _mimeForExtension(file.extension),
          );
      if (!mounted) return;
      ref.read(newRequestProvider.notifier).addDocument(doc);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(SnackBar(
        content: Text(raw.length > 160 ? '${raw.substring(0, 160)}…' : raw),
        backgroundColor: dangerColor,
      ));
    } finally {
      if (mounted) setState(() => _uploadingDocument = false);
    }
  }

  /// The picker reports an extension, not a MIME type, and the backend
  /// validates both — so the two have to agree.
  static String _mimeForExtension(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      color: c.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.title),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New care request',
                        style: MtTextStyles.h3.copyWith(color: c.title),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose your care and who it is for',
                        style: MtTextStyles.bodySm.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Step 1 of the checkout. Nothing behind it is tappable — the back
          // arrow above is the only way out of the flow from here.
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: BookingStepper(current: BookingStep.service),
          ),
        ],
      ),
    );
  }
}

/// Shown when a promo code was carried in from a
/// [BannerActionType.promoCode] promo-banner tap. Purely informational for
/// the patient — the admin sees `promo_code` on the submitted request and
/// applies the discount manually during pricing.
class _PromoCodeBanner extends StatelessWidget {
  final String code;
  final VoidCallback onClear;
  const _PromoCodeBanner({required this.code, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: c.brand, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: MtTextStyles.bodySm.copyWith(color: c.body),
                children: [
                  const TextSpan(text: 'Promo code applied: '),
                  TextSpan(
                    text: code,
                    style: TextStyle(fontWeight: FontWeight.w800, color: c.brand),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: c.muted),
            tooltip: 'Remove promo code',
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String en;
  final String? bn;
  const _SectionHeader({super.key, required this.en, this.bn});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          en.toUpperCase(),
          style: MtTextStyles.sectionLabel.copyWith(
            color: c.muted,
            letterSpacing: 1.0,
          ),
        ),
        if (bn != null)
          Text(
            bn ?? '',
            style: MtTextStyles.sectionLabel.copyWith(
              color: c.muted,
              fontFamily: 'Kalpurush',
            ),
          ),
      ],
    );
  }
}

/// The collapsed "Type of care" step, shown when the patient arrived from a
/// card that already picked the service (an admin-linked home-section item, a
/// promo banner, a catalog entry). Confirms what they tapped — title, price,
/// category — and offers "Change" to reopen the full list, so the pre-selection
/// is never a trap.
class _PreselectedServiceCard extends StatelessWidget {
  final ServiceCatalogItem service;
  final VoidCallback onChange;

  const _PreselectedServiceCard({
    required this.service,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: c.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.brand, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 20, color: c.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: MtTextStyles.labelLg.copyWith(color: c.title),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (service.category.trim().isNotEmpty)
                      service.category.trim(),
                    '৳${service.price.round()}',
                  ].join(' · '),
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(foregroundColor: c.brand),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _ServiceSelector extends ConsumerWidget {
  final AsyncValue<List<ServiceCatalogItem>> async;
  final String? selectedId;

  const _ServiceSelector({
    required this.async,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<ServiceCatalogItem>>(
      value: async,
      onRetry: () => refreshServiceCatalog(ref),
      loadingBuilder: (_) => Column(
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MtSkeleton.box(height: 76, radius: 12),
          ),
        ),
      ),
      isEmpty: (list) => list.isEmpty,
      emptyBuilder: (_) => const MtEmptyState(
        icon: Icons.medical_services_outlined,
        title: 'No services available',
        subtitle: 'New services will appear here once the admin team enables them.',
      ),
      dataBuilder: (_, items) {
        return Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _CareTypeOption(
                item: items[i],
                selected: items[i].id == selectedId,
                onTap: () => ref
                    .read(newRequestProvider.notifier)
                    .selectService(items[i]),
              ),
              if (i != items.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _CareTypeOption extends StatelessWidget {
  final ServiceCatalogItem item;
  final bool selected;
  final VoidCallback onTap;

  const _CareTypeOption({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected ? c.brand.withValues(alpha: 0.08) : c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? c.brand : c.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _Radio(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: MtTextStyles.labelLg.copyWith(color: c.title),
                    ),
                    if (item.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.category,
                        style: MtTextStyles.bodySm.copyWith(
                          color: c.body,
                          fontFamily: 'Kalpurush',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? c.brand : c.muted,
          width: 2,
        ),
        color: selected ? c.brand : Colors.transparent,
      ),
      child: selected
          ? Center(
              child: Icon(Icons.circle, size: 8, color: c.onAccent),
            )
          : null,
    );
  }
}


class _NotesCard extends StatelessWidget {
  final TextEditingController controller;

  /// Documents already uploaded and attached to this request.
  final List<RequestDocument> documents;

  /// An upload is in flight — the attach row becomes a spinner.
  final bool uploading;

  final ValueChanged<String> onNotesChanged;
  final VoidCallback onAttachDocument;
  final ValueChanged<RequestDocument> onRemoveDocument;

  const _NotesCard({
    required this.controller,
    required this.documents,
    required this.uploading,
    required this.onNotesChanged,
    required this.onAttachDocument,
    required this.onRemoveDocument,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: controller,
              onChanged: onNotesChanged,
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: MtTextStyles.bodyMd.copyWith(color: c.title),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText:
                    'Describe symptoms, existing conditions, or anything the '
                    'medical team should know before the visit.',
                hintStyle: MtTextStyles.bodyMd.copyWith(color: c.muted),
              ),
            ),
          ),
          Divider(height: 1, color: c.cardBorder),
          // Attached documents list — one row per file, with a remove action.
          if (documents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
              child: Column(
                children: [
                  for (final d in documents)
                    _DocumentRow(
                      document: d,
                      onRemove: () => onRemoveDocument(d),
                    ),
                ],
              ),
            ),
          _AttachDocumentButton(
            uploading: uploading,
            onTap: onAttachDocument,
            hasDocuments: documents.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

/// The single attachment affordance on the service step: pick a PDF or an
/// image of a previous discharge summary / prescription / lab report.
class _AttachDocumentButton extends StatelessWidget {
  final bool uploading;
  final bool hasDocuments;
  final VoidCallback onTap;

  const _AttachDocumentButton({
    required this.uploading,
    required this.hasDocuments,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            if (uploading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(c.brand),
                ),
              )
            else
              Text('📄', style: TextStyle(fontSize: 17, color: c.brand)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uploading
                        ? 'Uploading…'
                        : hasDocuments
                            ? 'Attach another document'
                            : 'Attach Previous Medical Documents',
                    style: MtTextStyles.labelLg.copyWith(color: c.brand),
                  ),
                  if (!uploading && !hasDocuments) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Discharge summary, prescription or lab report · PDF or image',
                      style: MtTextStyles.bodySm.copyWith(color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (!uploading) Icon(Icons.attach_file, size: 18, color: c.brand),
          ],
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final RequestDocument document;
  final VoidCallback onRemove;

  const _DocumentRow({required this.document, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final size = document.readableSize;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.surfaceHi,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              document.isPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
              size: 18,
              color: document.isPdf ? c.danger : c.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd.copyWith(color: c.title),
                ),
                if (size.isNotEmpty)
                  Text(size,
                      style: MtTextStyles.bodySm.copyWith(color: c.muted)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close, size: 18, color: c.muted),
            tooltip: 'Remove ${document.name}',
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.dangerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: MtTextStyles.bodySm.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 1's bottom bar. Advances to the Care Summary — it does **not**
/// submit, so there is no loading state to model here.
class _SubmitBar extends StatelessWidget {
  final bool enabled;

  /// Progress is barred specifically because another booking is still open
  /// (as opposed to a merely incomplete form) — swaps the pricing note for
  /// the tappable active-booking banner.
  final bool blocked;
  final VoidCallback onSubmit;

  const _SubmitBar({
    required this.enabled,
    required this.blocked,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Next up is the cart, where the price is assembled — so the note
            // here just says what happens next. While a booking is already
            // open that note is moot; the reason the button is dead is the
            // more useful thing to say.
            if (blocked)
              const ActiveBookingBanner()
            else
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Next: review your care summary, add-ons and total.',
                      style: MtTextStyles.bodySm.copyWith(color: c.body),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: enabled ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  disabledBackgroundColor: c.surfaceHi,
                  disabledForegroundColor: c.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue to summary',
                      // No explicit color: inherits the button's foreground,
                      // so the disabled state can dim the label too.
                      style: MtTextStyles.labelLg,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Horizontal "Who is this for?" chips: `Myself` (default) followed by the
/// patient's saved family members. Selecting a member binds their profile +
/// critical history into the outbound booking via `setCareRecipient`.
/// Horizontal card carousel of "who is this visit for" — Myself, each saved
/// family member (name + relation + age/sex), and a trailing "Add" card that
/// opens the family-member editor inline and auto-selects the new profile.
class _CareRecipientChips extends ConsumerWidget {
  final CareRecipient? selected;
  const _CareRecipientChips({required this.selected});

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final saved = await openMemberEditorSheet(context);
    if (saved == null) return;
    // Auto-select the freshly created profile.
    ref
        .read(newRequestProvider.notifier)
        .setCareRecipient(CareRecipient.fromDependent(saved));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final async = ref.watch(dependentsProvider);
    final dependents = async.valueOrNull ?? const <Dependent>[];
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _card(
            c: c,
            icon: Icons.person,
            title: 'Myself',
            subtitle: 'Account holder',
            active: selected == null,
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(newRequestProvider.notifier).setCareRecipient(null);
            },
          ),
          for (final d in dependents)
            _card(
              c: c,
              icon: Icons.family_restroom,
              title: d.fullName,
              subtitle: _dependentSubtitle(d),
              active: selected?.dependentId == d.id,
              onTap: () {
                HapticFeedback.lightImpact();
                ref
                    .read(newRequestProvider.notifier)
                    .setCareRecipient(CareRecipient.fromDependent(d));
              },
            ),
          _addCard(c: c, onTap: () => _addMember(context, ref)),
        ],
      ),
    );
  }

  /// "Mother · 62 / F" style line, dropping whichever parts are unknown.
  String _dependentSubtitle(Dependent d) {
    final parts = <String>[d.relationshipLabel];
    final as = ageSexLabel(d.dateOfBirth, d.gender);
    if (as.isNotEmpty) parts.add(as);
    return parts.join(' · ');
  }

  Widget _card({
    required AppColors c,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: active ? c.brand.withValues(alpha: 0.10) : c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? c.brand : c.cardBorder,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 22, color: active ? c.brand : c.muted),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.labelMd.copyWith(
                        color: active ? c.brand : c.body,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm.copyWith(color: c.muted),
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

  Widget _addCard({required AppColors c, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: c.cardBorder,
              width: 1,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person_add_alt_1_outlined, size: 22, color: c.brand),
              const SizedBox(height: 8),
              Text(
                'Add family\nmember',
                style: MtTextStyles.labelMd.copyWith(
                  color: c.brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
