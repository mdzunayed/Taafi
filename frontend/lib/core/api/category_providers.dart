import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/home_category.dart';
import 'category_repository.dart';

/// Category repository on the **authenticated** Dio — the write endpoints are
/// admin-gated, and the public GET tolerates the bearer token just fine.
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  final repo = CategoryRepository(client.authedDio);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every category, including hidden ones — the admin management list.
///
/// The patient rail deliberately does NOT read this: it takes its pills from
/// `/api/home-data` along with the cards they filter, so the two can never
/// arrive out of step. See [homeCategoriesProvider].
final allCategoriesProvider = StreamProvider<List<HomeCategory>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll();
});
