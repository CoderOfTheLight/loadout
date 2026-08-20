/// The root widget `main()` runs when the app could not start: a
/// MaterialApp whose only screen is [StartupFailureScreen], over a
/// `ProviderScope` holding whatever bootstrap managed to wire before it
/// threw.
///
/// It is a *root* rather than a route because the failure happens before the
/// router exists — there is no [StartupState] to redirect on and no
/// database to build the shell over.
///
/// "Try again" re-runs the same bootstrap over the same services (see
/// `bootstrapOrFail`). If it succeeds, this widget hands over to the real
/// [LoadoutApp] in place, so a restore or a transient failure does not need
/// the owner to know what "force quit" means.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/presentation/startup_failure_screen.dart';
import 'app.dart';
import 'bootstrap.dart';
import 'theme.dart';

class StartupFailureApp extends StatefulWidget {
  const StartupFailureApp({
    super.key,
    required this.failure,
    required this.retry,
  });

  final BootstrapFailed failure;

  /// Runs the bootstrap again. Must reuse the services the first attempt
  /// wired, or a retry after a restore would open a second handle on the
  /// same database file.
  final Future<BootstrapOutcome> Function() retry;

  @override
  State<StartupFailureApp> createState() => _StartupFailureAppState();
}

class _StartupFailureAppState extends State<StartupFailureApp> {
  late BootstrapFailed _failure = widget.failure;
  AppBootstrap? _ready;
  bool _retrying = false;

  /// Bumped on every attempt so the swap to a new `ProviderScope` builds a
  /// clean container rather than reusing the failed one.
  int _attempt = 0;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final outcome = await widget.retry();
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _attempt++;
      switch (outcome) {
        case BootstrapReady(:final boot):
          _ready = boot;
        case final BootstrapFailed failed:
          _failure = failed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready != null) {
      return ProviderScope(
        key: ValueKey('loadout-$_attempt'),
        overrides: ready.overrides,
        child: const LoadoutApp(),
      );
    }
    return ProviderScope(
      key: ValueKey('startup-failure-$_attempt'),
      overrides: _failure.overrides,
      child: MaterialApp(
        title: 'Loadout',
        debugShowCheckedModeBanner: false,
        theme: loadoutTheme(Brightness.light),
        darkTheme: loadoutTheme(Brightness.dark),
        home: StartupFailureScreen(
          kind: _failure.kind,
          canRetry: _failure.canRetry,
          canRestore: _failure.canRestore,
          busy: _retrying,
          onRetry: _retry,
        ),
      ),
    );
  }
}
