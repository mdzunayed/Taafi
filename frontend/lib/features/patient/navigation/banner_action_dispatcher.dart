import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/promo_banner.dart';
import '../../../core/models/service_catalog_item.dart';
import '../new_request/new_request_notifier.dart';
import '../screens/service_catalog_screen.dart';
import '../screens/service_detail_screen.dart';
import 'patient_nav_provider.dart';

/// Dispatches a tap on a patient Home promo-banner's CTA button to whatever
/// destination the admin configured on it (see `PromoBanner.actionType` +
/// `admin_banner_management_page.dart`'s "Action / Target destination"
/// section).
///
/// Mirrors `dynamic_route_dispatcher.dart`'s job for server-driven home
/// sections, but kept separate: banners carry a resolved [BannerActionType]
/// + populated target snapshot rather than a raw route string, so the
/// dispatch logic (and its fallbacks) differ enough to not share one
/// function. Every branch degrades gracefully when its target is missing
/// (a banner saved before this feature shipped, or a linked service/URL
/// that's since been deleted) — landing on the booking flow unprefilled
/// rather than dead-ending the tap, matching the promo carousel's original
/// behavior.
Future<void> handleBannerTap(
  BuildContext context,
  WidgetRef ref,
  PromoBanner banner,
) async {
  switch (banner.actionType) {
    case BannerActionType.service:
      final target = banner.targetService;
      if (target == null) {
        ref.goToNewRequest();
        return;
      }
      final item = ServiceCatalogItem(
        id: target.id,
        title: target.title,
        price: target.price,
        category: target.category,
        imageUrl: target.imageUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // Land on the service's detail page (photo, price, description) rather
      // than jumping straight into the booking form — the spec calls this
      // out explicitly ("navigate directly to a Service Page"). Booking from
      // there pops `true`, which we use to advance to New Request.
      final booked = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ServiceDetailScreen(item: item)),
      );
      if (booked == true) ref.goToNewRequest();
      return;

    case BannerActionType.category:
      final category = banner.targetCategoryId?.trim();
      if (category == null || category.isEmpty) {
        ref.goToNewRequest();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ServiceCatalogScreen(initialCategory: category),
        ),
      );
      return;

    case BannerActionType.externalUrl:
      final url = banner.targetUrl.trim();
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasScheme) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;

    case BannerActionType.promoCode:
      final code = banner.promoCode.trim();
      if (code.isEmpty) {
        ref.goToNewRequest();
        return;
      }
      ref.read(newRequestProvider.notifier).applyPromoCode(code);
      ref.goToNewRequest();
      return;

    case BannerActionType.none:
      // Display-only banner — the button intentionally does nothing.
      return;
  }
}
