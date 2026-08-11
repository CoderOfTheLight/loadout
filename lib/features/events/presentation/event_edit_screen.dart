/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [EventEditScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class EventEditScreen extends StatelessWidget {
  const EventEditScreen({super.key, this.eventId});

  final String? eventId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event')),
    body: const Center(child: Text('Not built yet')),
  );
}
