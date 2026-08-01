// Boot smoke test for the app shell.
//
// This file used to hold the stock `flutter create` counter test, which pumped
// MyApp with no ProviderScope and asserted on a "+" button and a counter label
// that have never existed in this app. It threw "Bad state: No ProviderScope
// found" before reaching a single assertion.
//
// What is actually worth guarding at this level is that the shell composes:
// MyApp resolves its router and theme from Riverpod and hands MaterialApp.router
// a real config, under both themes, without throwing. Anything screen-specific
// belongs in a focused test instead.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taafi/core/storage/app_prefs.dart';
import 'package:taafi/core/theme/theme_provider.dart';
import 'package:taafi/main.dart';

/// Mirrors main()'s wiring: prefs are preloaded and injected so the theme and
/// auth-token providers can seed synchronously on the first frame.
Future<Widget> _bootApp(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MyApp(),
  );
}

void main() {
  testWidgets('boots into a routed MaterialApp with no preference saved',
      (tester) async {
    await tester.pumpWidget(await _bootApp({}));
    await tester.pump();

    expect(tester.takeException(), isNull);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.routerConfig, isNotNull);
    expect(app.title, 'Taafi');
    expect(app.themeMode, ThemeMode.light);
  });

  testWidgets('honours a persisted dark preference on boot', (tester) async {
    await tester.pumpWidget(await _bootApp({kDarkModePrefKey: true}));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
