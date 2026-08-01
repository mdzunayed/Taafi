import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/doctor_dashboard.dart';
import '../auth/auth_provider.dart';

/// Async surface backing the nurse dashboard. The backend route
/// (`GET /doctor/dashboard`) already unions doctor + nurse assignments
/// when a provider id is passed, so we can ride the same Dio method
/// — the nurse dashboard just reads from a separately-keyed provider
/// so its invalidation lifecycle doesn't tangle with the doctor one.
final nurseDashboardProvider =
    FutureProvider.autoDispose<DoctorDashboard>((ref) async {
  return ref.read(dioClientProvider).getDoctorDashboard();
});
