/// The root widget: M3 theme (seed 0xff356859, light + dark,
/// `ThemeMode.system`), the single router, and the lifecycle hook that
/// sweeps scratch space on `AppLifecycleState.paused` (§10; bootstrap
/// covers app start).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    themeMode: ThemeMode.system,
    theme: loadoutTheme(Brightness.light),
    darkTheme: loadoutTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}
