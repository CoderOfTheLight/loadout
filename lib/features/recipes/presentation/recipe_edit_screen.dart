/// STUB — the feature agent replaces this file's CONTENTS ONLY.
/// The router (lib/app/router.dart) is final: keep this file path, the
/// class name [RecipeEditScreen], and the constructor signature exactly as-is.
library;

import 'package:flutter/material.dart';

class RecipeEditScreen extends StatelessWidget {
  const RecipeEditScreen({super.key, this.recipeId});

  final String? recipeId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recipe')),
    body: const Center(child: Text('Not built yet')),
  );
}
