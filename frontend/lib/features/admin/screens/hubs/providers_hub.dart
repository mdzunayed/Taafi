import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/doctor_profile.dart';
import '../../admin_nav.dart';
import '../../admin_providers.dart';
import '../tabs/provider_verification_tab.dart';
import '../tabs/providers_tab.dart';
import 'hub_scaffold.dart';

/// Provider directory + credential review behind one sidebar link.
///
/// Doctor verification and Nurse verification used to be two separate
/// destinations that differed only by a role string. They are now the single
/// "Pending verification" pill, which mounts the review queue unscoped so
/// both roles are worked from one list — the credential labels (BMDC vs
/// BNMC) were always derived per row, so a mixed queue reads correctly.
///
/// The other pills show the directory table filtered in place. Reviewing
/// needs the full registration detail a table row can't carry, which is why
/// "Pending verification" swaps the body rather than just narrowing it.
class ProvidersHub extends ConsumerWidget {
  const ProvidersHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(providersFilterProvider);
    final rows = ref.watch(adminProvidersListProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <DoctorProfile>[],
        );

    int countFor(ProvidersFilter f) => switch (f) {
          ProvidersFilter.all => rows.length,
          ProvidersFilter.pending =>
            rows.where((p) => !p.isVerified && !p.isSuspended).length,
          ProvidersFilter.active =>
            rows.where((p) => p.isVerified && !p.isSuspended).length,
          ProvidersFilter.suspended => rows.where((p) => p.isSuspended).length,
        };

    return HubScaffold<ProvidersFilter>(
      selected: selected,
      onSelect: (f) => ref.read(providersFilterProvider.notifier).state = f,
      tabs: [
        HubTab(
          value: ProvidersFilter.all,
          label: ProvidersFilter.all.label,
          icon: Icons.local_hospital_outlined,
          count: countFor(ProvidersFilter.all),
        ),
        HubTab(
          value: ProvidersFilter.pending,
          label: ProvidersFilter.pending.label,
          icon: Icons.verified_outlined,
          count: countFor(ProvidersFilter.pending),
        ),
        HubTab(
          value: ProvidersFilter.active,
          label: ProvidersFilter.active.label,
          icon: Icons.check_circle_outline,
          count: countFor(ProvidersFilter.active),
        ),
        HubTab(
          value: ProvidersFilter.suspended,
          label: ProvidersFilter.suspended.label,
          icon: Icons.block_outlined,
          count: countFor(ProvidersFilter.suspended),
        ),
      ],
      body: switch (selected) {
        // Merged doctor + nurse credential queue.
        ProvidersFilter.pending =>
          const ProviderVerificationTab(embedded: true),
        // Directory table, narrowed in place. Onboarding a new provider
        // lives here via the table's "Add doctor / nurse" action.
        _ => ProvidersTab(filter: selected, embedded: true),
      },
    );
  }
}
