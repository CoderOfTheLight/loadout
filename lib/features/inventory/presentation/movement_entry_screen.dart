/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [MovementEntryScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class MovementEntryScreen extends StatelessWidget {
  const MovementEntryScreen({super.key, this.kind, this.itemId});

  final String? kind;
  final String? itemId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record movement')),
    body: const Center(child: Text('Not built yet')),
  );
}
