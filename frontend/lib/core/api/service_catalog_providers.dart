import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/service_catalog_item.dart';
import 'service_catalog_repository.dart';

/// Service-catalog repository built on the **authenticated** Dio (from
/// [dioClientProvider]), matching [promoBannerRepositoryProvider] and the
/// other admin repositories.
///
/// This used to construct a bare `Dio` with no auth interceptor, which worked
/// only because the `/api/services` write routes were missing their
/// `requireRole('admin')` guard. Now that they're gated, admin create/update/
/// delete needs the bearer token like every sibling router.
final serviceCatalogRepositoryProvider = Provider<ServiceCatalogRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  final repo = ServiceCatalogRepository(client.authedDio);
  ref.onDispose(repo.dispose);
  return repo;
});

final allServicesProvider = StreamProvider<List<ServiceCatalogItem>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).watchAll();
});

final activeServicesProvider = StreamProvider<List<ServiceCatalogItem>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).watchActive();
});
