import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/network/dispatch_overlay.dart';
import 'core/storage/app_prefs.dart';
import 'core/theme/app_themes.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Preload SharedPreferences once so [sharedPreferencesProvider] (and thus the
  // Dio auth interceptor's [tokenProvider]) is available synchronously from the
  // first frame — no async gap, no cold-start 401 race.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Taafi',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Wrap every routed screen so the authenticated socket stays alive
      // app-wide and the intrusive incoming-dispatch overlay can paint on
      // top of any screen the instant a `dispatch:incoming` event lands.
      builder: (context, child) =>
          DispatchOverlayHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
