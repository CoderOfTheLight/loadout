/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [ForecastReviewScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class ForecastReviewScreen extends StatelessWidget {
  const ForecastReviewScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forecast')),
    body: const Center(child: Text('Not built yet')),
  );
}
