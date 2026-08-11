/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [CorrectionScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class CorrectionScreen extends StatelessWidget {
  const CorrectionScreen({super.key, required this.movementId});

  final String movementId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Correct entry')),
    body: const Center(child: Text('Not built yet')),
  );
}
