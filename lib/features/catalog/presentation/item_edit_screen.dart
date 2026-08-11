/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [ItemEditScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class ItemEditScreen extends StatelessWidget {
  const ItemEditScreen({super.key, this.itemId});

  final String? itemId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Item')),
    body: const Center(child: Text('Not built yet')),
  );
}
