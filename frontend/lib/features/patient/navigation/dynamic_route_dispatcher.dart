import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/service_catalog_providers.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/service_catalog_item.dart';
import '../new_request/new_request_notifier.dart';
import 'patient_nav_provider.dart';

/// Dispatches a tap on a dynamic home-section card to whatever destination the
/// admin linked it to in the CMS (see `HomeSectionItem.targetType` +
/// `admin_home_sections_page.dart`'s "Linked target" section).
///
/// The headline case is [HomeItemTargetType.service]: the tap lands the patient
/// on the New Care Request flow with that catalog service **already selected**,
/// so the booking form opens past its service-picking step.
///
/// Every branch degrades gracefully — a link whose service was deleted, or a
/// route string this app version doesn't know, falls back to the booking form
/// unprefilled rather than dead-ending the tap.
void dispatchHomeItemTarget(WidgetRef ref, HomeSectionItem item) {
  switch (item.targetType) {
    case HomeItemTargetType.service:
      final service = _resolveService(ref, item);
      if (service == null) {
        // Link points at a service that's since been deleted (or the catalog
        // never loaded and the backend sent no snapshot).
        ref.goToNewRequest();
        return;
      }
      ref
          .read(newRequestProvider.notifier)
          .applyServicePrefill(service, fromLink: true);
      ref.goToNewRequest();
      return;

    case HomeItemTargetType.externalUrl:
      final uri = Uri.tryParse(item.customRoute.trim());
      if (uri != null && uri.hasScheme) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;

    case HomeItemTargetType.customRoute:
      dispatchDynamicRoute(
        ref,
        item.customRoute.isNotEmpty ? item.customRoute : item.navigationRoute,
        args: item.routeArguments,
      );
      return;

    case HomeItemTargetType.none:
      // Display-only card — the tap intentionally does nothing.
      return;
  }
}

/// The catalog entry behind a [HomeItemTargetType.service] item. Prefers the
/// live `/api/services` record (freshest price/description) and falls back to
/// the backend's populated snapshot, which is present even before the catalog
/// stream has emitted — so the very first tap after app launch still prefills.
ServiceCatalogItem? _resolveService(WidgetRef ref, HomeSectionItem item) {
  final id = item.serviceId;
  if (id == null || id.isEmpty) return null;

  final services = ref.read(activeServicesProvider).valueOrNull;
  final live = services?.where((s) => s.id == id).toList();
  if (live != null && live.isNotEmpty) return live.first;

  final snap = item.linkedService;
  if (snap == null || snap.id != id) return null;
  final now = DateTime.now();
  return ServiceCatalogItem(
    id: snap.id,
    title: snap.title,
    price: snap.price,
    category: snap.category,
    imageUrl: snap.imageUrl,
    createdAt: now,
    updatedAt: now,
  );
}

/// Dispatches a server-driven `navigationRoute` string onto the patient shell.
///
/// Supported route strings:
///   • `home` / `new_request` / `account`      — tab switch
///   • `activities`                            — Activities, default sub-tab
///   • `activities:under_review|tracking|history|medications`
///   • `service:<serviceId>`                   — prefill the booking form with
///     that catalog service and jump to New Request (same flow as tapping a
///     service card)
///   • `http://…` / `https://…`                — external browser
///
/// Anything else (including null) is a silent no-op so newer backends can
/// ship routes this app version doesn't know yet. [args] is the item's
/// `routeArguments` map — reserved for future route types.
///
/// Structured [HomeSectionItem] targets go through [dispatchHomeItemTarget];
/// this stays the raw-string path, used for `CUSTOM_ROUTE` items and by any
/// other caller holding only a route string.
void dispatchDynamicRoute(
  WidgetRef ref,
  String? route, {
  Map<String, String> args = const {},
}) {
  final value = route?.trim();
  if (value == null || value.isEmpty) return;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  if (value.startsWith('service:')) {
    final serviceId = value.substring('service:'.length).trim();
    final services = ref.read(activeServicesProvider).valueOrNull;
    final match = services?.where((s) => s.id == serviceId).toList();
    if (match == null || match.isEmpty) {
      // Catalog not loaded or the service is gone — land on the booking
      // form unprefilled rather than dead-ending the tap.
      ref.goToNewRequest();
      return;
    }
    ref
        .read(newRequestProvider.notifier)
        .applyServicePrefill(match.first, fromLink: true);
    ref.goToNewRequest();
    return;
  }

  switch (value) {
    case 'home':
      ref.goToHome();
      return;
    case 'new_request':
      ref.goToNewRequest();
      return;
    case 'account':
      ref.goToAccount();
      return;
    case 'activities':
      ref.goToActivities();
      return;
    case 'activities:under_review':
      ref.goToActivities(sub: PatientActivitiesTab.underReview);
      return;
    case 'activities:tracking':
      ref.goToActivities(sub: PatientActivitiesTab.tracking);
      return;
    case 'activities:history':
      ref.goToActivities(sub: PatientActivitiesTab.history);
      return;
    case 'activities:medications':
      ref.goToActivities(sub: PatientActivitiesTab.medications);
      return;
    default:
      debugPrint('dispatchDynamicRoute: unknown route "$value" — ignored');
  }
}
