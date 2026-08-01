import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_prefs.dart';

/// SharedPreferences key for the persisted theme choice. Deliberately the
/// **same** key the settings screen already writes (`user.settings.dark_mode`)
/// so any preference saved before theme switching was wired up carries over —
/// one source of truth, no migration.
const String kDarkModePrefKey = 'user.settings.dark_mode';

/// Reactive, disk-persisted app theme mode.
///
/// Modeled as an **atomic leaf**, exactly like `tokenProvider`: it depends only
/// on [sharedPreferencesProvider] and touches no network / auth / repository
/// layer. That isolation matters — if it reached into those graphs Riverpod
/// could form a cycle and throw a `CircularDependencyError` during the very
/// first frame. As a leaf it can never point back.
///
/// The seed read is **synchronous** because prefs are `await`-loaded in
/// `main()` before `runApp`, so the correct theme is known on the first frame —
/// there is no light-then-dark startup flash.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final isDark = prefs.getBool(kDarkModePrefKey) ?? false;
    return isDark ? ThemeMode.dark : ThemeMode.light;
  }

  /// Flip between light and dark, persisting the new choice write-through so it
  /// survives the next boot cycle.
  Future<void> toggleTheme() =>
      setDark(state != ThemeMode.dark);

  /// Explicitly set dark on/off (used by the settings toggle).
  Future<void> setDark(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    await ref.read(sharedPreferencesProvider).setBool(kDarkModePrefKey, isDark);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
