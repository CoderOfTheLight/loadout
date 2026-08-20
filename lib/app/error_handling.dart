/// Process-wide error handling, installed before `runApp`.
///
/// ## Why `PlatformDispatcher.instance.onError` and not `runZonedGuarded`
///
/// Flutter routes every uncaught asynchronous error through
/// [PlatformDispatcher.onError] (`_reportUnhandledError`), so on 3.44 a
/// custom error zone buys nothing that this callback does not already give
/// — and it costs the one thing that is easy to get wrong: the binding must
/// be created in the SAME zone that later calls `runApp`, or the framework
/// trips its "Zone mismatch" assertion and every subsequent
/// `WidgetsBinding.instance` lookup is served from the wrong zone. Keeping
/// `WidgetsFlutterBinding.ensureInitialized()` and `runApp` in the root zone
/// makes that class of bug unreachable. This is also the arrangement
/// flutter.dev/testing/errors documents.
///
/// [FlutterError.onError] is deliberately left at its default
/// ([FlutterError.presentError]): overriding it to do the same work adds a
/// hook with no behaviour. What the owner sees is [ErrorWidget.builder],
/// which is set here; what a developer sees is the console dump the default
/// already produces.
///
/// Nothing here writes to the diagnostics log. A build failure inside a
/// screen is reported by the widget below, and a firehose of runtime errors
/// would push the startup and data-integrity lines that matter out of the
/// 256 KB ring (§10). The one failure that IS logged is the one that stops
/// the app starting — see `bootstrapOrFail`.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// Installs the error-presentation floor. Call once, after
/// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
void installLoadoutErrorHandlers() {
  ErrorWidget.builder = loadoutErrorWidget;
  PlatformDispatcher.instance.onError = (error, stack) {
    // Present it (the default reporter is skipped once this returns true),
    // then keep the app alive: a failed background future must not take
    // down a screen the owner is working in.
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'loadout'),
    );
    return true;
  };
}

/// What a widget that fails to build renders instead of the framework's grey
/// rectangle (release) or red screen (debug) — in every build mode, so the
/// thing under test is the thing that ships.
///
/// Built from raw widgets on purpose: [ErrorWidget.builder] can be invoked
/// above `MaterialApp`, where there is no `Theme`, no `Directionality` and
/// no `MediaQuery` to lean on. [details] is never rendered (§10: no
/// exception text, no stack trace, no identifiers on screen); the default
/// [FlutterError.onError] has already dumped it to the console.
Widget loadoutErrorWidget(FlutterErrorDetails details) => const Directionality(
  textDirection: TextDirection.ltr,
  // LimitedBox: an error widget can land in an unbounded slot (inside a Row,
  // a ListView, a Column), where a plain box would fail to lay out and start
  // the whole cycle again.
  child: LimitedBox(
    maxWidth: 480,
    maxHeight: 240,
    child: ColoredBox(
      // Opaque, and legible against either brightness — there is no theme to
      // ask at this point.
      color: Color(0xFFFFDAD6),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Something on this screen could not be shown. Nothing has been '
            'changed. Go back, or close Loadout and open it again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF410002),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  ),
);
