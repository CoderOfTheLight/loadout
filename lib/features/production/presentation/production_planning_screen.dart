/// §9 `/production` — ProductionPlanningScreen (Gate 5 stub).
///
/// Static by design: "Production planning is coming", two sentences on what
/// it will do, and the readiness checklist ("You're ready: recipes ✓,
/// forecasts ✓"). No service, no state — the real screen arrives with
/// `ProductionPlanService` in a later release (design §13).
library;

import 'package:flutter/material.dart';

import '../../../app/widgets/content_column.dart';

class ProductionPlanningScreen extends StatelessWidget {
  const ProductionPlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Production')),
      body: SingleChildScrollView(
        child: ContentColumn(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(
                avatar: Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                label: const Text('Coming in a later release'),
                backgroundColor: theme.colorScheme.secondaryContainer,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                side: BorderSide.none,
              ),
              const SizedBox(height: 24),
              Icon(
                Icons.factory_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Production planning is coming',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Loadout will turn your recipes and event forecasts into a '
                'batch plan: how many batches of each recipe to prep, and '
                'what those batches consume. Every recipe you enter now '
                'feeds straight into it the day it lands.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text("You're ready:", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const _ReadinessRow(label: 'Recipes'),
              const _ReadinessRow(label: 'Forecasts'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('$label ✓', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
