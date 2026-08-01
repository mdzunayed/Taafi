import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/promo_banner.dart';
import 'promo_banner_repository.dart';

/// Promo-banner repository built on the **authenticated** Dio (from
/// [dioClientProvider]) — the write endpoints are admin-gated, and the public
/// GET tolerates the (patient/admin) bearer token just fine.
final promoBannerRepositoryProvider = Provider<PromoBannerRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  final repo = PromoBannerRepository(client.authedDio);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every banner (admin management list).
final allBannersProvider = StreamProvider<List<PromoBanner>>((ref) {
  return ref.watch(promoBannerRepositoryProvider).watchAll();
});

/// Only active banners, ascending by priority (the client Home slider).
final activeBannersProvider = StreamProvider<List<PromoBanner>>((ref) {
  return ref.watch(promoBannerRepositoryProvider).watchActive();
});
