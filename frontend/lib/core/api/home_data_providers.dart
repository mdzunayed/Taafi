import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/patient_home_data.dart';
import 'home_data_repository.dart';

/// Home-data repository on the **authenticated** Dio, matching every sibling
/// repository. The endpoint is public — Home renders before sign-in — but the
/// bearer token is harmless when present and the shared client carries the
/// base URL and interceptors.
final homeDataRepositoryProvider = Provider<HomeDataRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  final repo = HomeDataRepository(client.authedDio);
  ref.onDispose(repo.dispose);
  return repo;
});

/// The whole patient Home payload.
///
/// Stays in `AsyncLoading` until the first fetch settles and then never
/// errors — a failure degrades to [PatientHomeData.fallback]. See
/// [HomeDataRepository] for why.
final patientHomeDataProvider = StreamProvider<PatientHomeData>((ref) {
  return ref.watch(homeDataRepositoryProvider).watch();
});

/// The ONLY correct way to re-fetch from a pull-to-refresh.
///
/// `ref.refresh(patientHomeDataProvider)` re-subscribes to the same repository
/// and replays its cached snapshot without issuing a request — the same trap
/// [refreshServiceCatalog] documents for the catalog.
Future<void> refreshHomeData(WidgetRef ref) {
  return ref.read(homeDataRepositoryProvider).refresh();
}
