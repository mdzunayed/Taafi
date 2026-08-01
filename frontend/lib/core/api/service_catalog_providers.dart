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

/// The ONLY correct way to re-fetch the catalog from a Retry button or a
/// pull-to-refresh.
///
/// `ref.refresh(activeServicesProvider)` looks like it re-fetches but does not:
/// the StreamProvider is rebuilt, yet its dependency
/// ([serviceCatalogRepositoryProvider]) is not, so it re-subscribes to the same
/// repository, which immediately replays the cached `_initialError` — the same
/// error re-renders without a single network call. That is why the "Couldn't
/// load / Retry" card on Home was unrecoverable: the button was inert.
///
/// Going through the repository issues a real GET and pushes the result onto
/// both watched streams, which flips every listening provider back to data.
Future<void> refreshServiceCatalog(WidgetRef ref) {
  return ref.read(serviceCatalogRepositoryProvider).refreshQuietly();
}
