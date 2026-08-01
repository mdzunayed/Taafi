// Verifies the theme system's core state logic end-to-end without a device:
//   1. themeModeProvider seeds synchronously from the preloaded prefs (the
//      no-startup-flash guarantee).
//   2. toggleTheme / setDark flip the state AND write through to disk so the
//      choice survives the next boot.
//
// This mirrors main()'s wiring: sharedPreferencesProvider is overridden with a
// preloaded SharedPreferences, exactly as ThemeModeNotifier.build() expects.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taafi/core/storage/app_prefs.dart';
import 'package:taafi/core/theme/theme_provider.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds ThemeMode.light when no preference is saved', () async {
    final container = await _containerWith({});
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('seeds ThemeMode.dark from a persisted dark preference', () async {
    final container = await _containerWith({kDarkModePrefKey: true});
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('toggleTheme flips state and writes through to disk', () async {
    final container = await _containerWith({});
    expect(container.read(themeModeProvider), ThemeMode.light);

    await container.read(themeModeProvider.notifier).toggleTheme();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    // Persisted, so a fresh boot would seed dark.
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kDarkModePrefKey), true);
  });

  test('setDark(false) turns dark off and persists', () async {
    final container = await _containerWith({kDarkModePrefKey: true});
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await container.read(themeModeProvider.notifier).setDark(false);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      container.read(sharedPreferencesProvider).getBool(kDarkModePrefKey),
      false,
    );
  });
}
