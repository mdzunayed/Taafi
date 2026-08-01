import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/saved_address.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../profile/patient_lifecycle_providers.dart';
import 'address_book_screen.dart';

/// Opens the saved-address picker during checkout. Returns the chosen
/// [SavedAddress] (with its pinned coordinates), or `null` if dismissed.
Future<SavedAddress?> showSelectAddressSheet(BuildContext context) {
  return showModalBottomSheet<SavedAddress>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MtColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SelectAddressSheet(),
  );
}

class _SelectAddressSheet extends ConsumerWidget {
  const _SelectAddressSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedAddressesProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            Text('Choose a delivery address',
                style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child:
                      Center(child: CircularProgressIndicator(color: MtColors.brand)),
                ),
                error: (e, _) => MtErrorState(
                  title: "Couldn't load addresses",
                  message: e.toString(),
                  onRetry: () => ref.invalidate(savedAddressesProvider),
                ),
                data: (addresses) {
                  if (addresses.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No saved addresses yet — add one below.',
                        style:
                            MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: addresses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final a = addresses[i];
                      return _AddressRow(
                        address: a,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(a);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AddressBookScreen()));
              },
              icon: const Icon(Icons.add_location_alt_outlined,
                  color: MtColors.brand),
              label: Text('Manage / add address',
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.brand)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: MtColors.brand),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final SavedAddress address;
  final VoidCallback onTap;
  const _AddressRow({required this.address, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: address.isDefault ? MtColors.brand : MtColors.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MtColors.brandSofter,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place_outlined,
                    color: MtColors.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(address.label,
                        style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(address.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: MtColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
