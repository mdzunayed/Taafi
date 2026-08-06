import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin_nav.dart';
import '../tabs/admin_dynamic_sections_page.dart';
import '../tabs/admin_home_categories_page.dart';
import '../tabs/admin_home_sections_page.dart';
import '../tabs/manage_services_tab.dart';
import 'hub_scaffold.dart';

/// Unified service catalog + storefront layout.
///
/// Collapses four former sidebar destinations — Manage services, Home
/// categories, Care services layout, and Home sections — into one link.
/// They were split by implementation (each has its own admin endpoint)
/// rather than by task: an admin adding a service almost always then places
/// it in a category and a home section, which used to mean three sidebar
/// trips.
class ServicesHub extends ConsumerWidget {
  const ServicesHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(servicesTabProvider);

    return HubScaffold<ServicesTab>(
      selected: selected,
      onSelect: (tab) => ref.read(servicesTabProvider.notifier).state = tab,
      tabs: [
        HubTab(
          value: ServicesTab.services,
          label: ServicesTab.services.label,
          icon: Icons.medical_services_outlined,
        ),
        HubTab(
          value: ServicesTab.categories,
          label: ServicesTab.categories.label,
          icon: Icons.label_outline,
        ),
        HubTab(
          value: ServicesTab.careLayout,
          label: ServicesTab.careLayout.label,
          icon: Icons.dashboard_outlined,
        ),
        HubTab(
          value: ServicesTab.homeSections,
          label: ServicesTab.homeSections.label,
          icon: Icons.dashboard_customize_outlined,
        ),
      ],
      body: switch (selected) {
        ServicesTab.services => const ManageServicesTab(),
        ServicesTab.categories => const AdminHomeCategoriesPage(),
        ServicesTab.careLayout => const AdminDynamicSectionsPage(),
        ServicesTab.homeSections => const AdminHomeSectionsPage(),
      },
    );
  }
}
