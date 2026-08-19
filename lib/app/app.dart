/// The root widget: M3 theme (seed 0xff356859, light + dark, brightness
/// chosen by the owner through [themeChoiceProvider] — "Follow phone" until
/// she says otherwise), the single router, and the lifecycle hook that
/// sweeps scratch space on `AppLifecycleState.paused` (§10; bootstrap
/// covers app start).
///
/// Every route inherits the choice from this one MaterialApp, including the
/// pre-workspace ones (`/welcome`, `/recovery`) — that is why the provider
/// reads the preference on its own rather than off the workspace.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/domain/app_theme_choice.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class LoadoutApp extends ConsumerStatefulWidget {
  const LoadoutApp({super.key});

  @override
  ConsumerState<LoadoutApp> createState() => _LoadoutAppState();
}

class _LoadoutAppState extends ConsumerState<LoadoutApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(ref.read(scratchSpaceProvider).sweepAll());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Loadout',
    debugShowCheckedModeBanner: false,
    themeMode: ref.watch(themeChoiceProvider).themeMode,
    theme: loadoutTheme(Brightness.light),
    darkTheme: loadoutTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}

/// The one place the appearance preference meets Flutter's own enum; the
/// choice itself stays Flutter-free (see [AppThemeChoice]).
extension AppThemeChoiceMode on AppThemeChoice {
  ThemeMode get themeMode => switch (this) {
    AppThemeChoice.system => ThemeMode.system,
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.dark => ThemeMode.dark,
  };
}
