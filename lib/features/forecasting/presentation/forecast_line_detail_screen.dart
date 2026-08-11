/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [ForecastLineDetailScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class ForecastLineDetailScreen extends StatelessWidget {
  const ForecastLineDetailScreen({
    super.key,
    required this.eventId,
    required this.itemId,
  });

  final String eventId;
  final String itemId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forecast line')),
    body: const Center(child: Text('Not built yet')),
  );
}
