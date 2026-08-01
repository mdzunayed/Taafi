import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dependent.dart';
import '../../../core/models/saved_address.dart';
import '../../auth/auth_provider.dart';

/// The signed-in patient's saved-address ledger (default first).
final savedAddressesProvider =
    FutureProvider.autoDispose<List<SavedAddress>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).listAddresses();
});

/// The signed-in patient's saved family members / dependents.
final dependentsProvider =
    FutureProvider.autoDispose<List<Dependent>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.read(dioClientProvider).listDependents();
});
