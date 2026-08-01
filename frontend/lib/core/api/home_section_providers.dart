import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/home_section.dart';
import 'home_section_repository.dart';

/// Home-section repository built on the **authenticated** Dio (from
/// [dioClientProvider]) — the write endpoints are admin-gated, and the public
/// GET tolerates the (patient/admin) bearer token just fine.
final homeSectionRepositoryProvider = Provider<HomeSectionRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  final repo = HomeSectionRepository(client.authedDio);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every section (admin management list).
final allHomeSectionsProvider = StreamProvider<List<HomeSection>>((ref) {
  return ref.watch(homeSectionRepositoryProvider).watchAll();
});

/// Only active sections, ascending by order (the patient Home renderer).
final activeHomeSectionsProvider = StreamProvider<List<HomeSection>>((ref) {
  return ref.watch(homeSectionRepositoryProvider).watchActive();
});
