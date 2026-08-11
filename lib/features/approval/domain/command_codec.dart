import 'dart:convert';

import '../../inventory/domain/inventory_ledger.dart';
import '../../recipes/domain/recipe_drafts.dart';
import 'commands.dart';

/// Stable machine kind stored in `commands.kind` (max 64 chars).
String commandKind(WorkspaceCommand command) => switch (command) {
  CreateItem() => 'CreateItem',
  UpdateItem() => 'UpdateItem',
  SetItemArchived() => 'SetItemArchived',
  CreateEvent() => 'CreateEvent',
  UpdateEvent() => 'UpdateEvent',
  ActivateEvent() => 'ActivateEvent',
  CancelEvent() => 'CancelEvent',
  AppendMovement() => 'AppendMovement',
  CorrectMovement() => 'CorrectMovement',
  RecordCloseout() => 'RecordCloseout',
  ReviseCloseout() => 'ReviseCloseout',
  CreateRecipe() => 'CreateRecipe',
  AddRecipeRevision() => 'AddRecipeRevision',
  SetRecipeArchived() => 'SetRecipeArchived',
  SaveForecastSnapshot() => 'SaveForecastSnapshot',
  OverrideForecastLine() => 'OverrideForecastLine',
};

/// Canonical payload encoding stored in `commands.payload_json` and compared
/// byte-for-byte for idempotency (design §6.4): fixed key order, quantities
/// as micros, instants as UTC epoch micros, enums as their stored names.
/// Nulls are written explicitly so equal commands always encode equally.
String encodeCommandPayload(WorkspaceCommand command) =>
    jsonEncode(_payload(command));

Map<String, Object?> _payload(WorkspaceCommand command) => switch (command) {
  CreateItem() => {
    'name': command.name,
    'unit': command.unit.dbValue,
    'pack_size_micros': command.packSize.micros,
    'category': command.category,
    'notes': command.notes,
  },
  UpdateItem() => {
    'item_id': command.itemId as String,
    'name': command.name,
    'unit': command.unit?.dbValue,
    'pack_size_micros': command.packSize?.micros,
    'category': command.category,
    'notes': command.notes,
  },
  SetItemArchived() => {
    'item_id': command.itemId as String,
    'archived': command.archived,
  },
  CreateEvent() => {
    'name': command.name,
    'scheduled_date': command.scheduledDate,
    'starts_at_micros': command.startsAt?.epochMicrosUtc,
    'ends_at_micros': command.endsAt?.epochMicrosUtc,
    'planned_exposure': command.plannedExposure,
    'venue': command.venue,
    'notes': command.notes,
    'planned_item_ids': [for (final id in command.plannedItemIds) id as String],
  },
  UpdateEvent() => {
    'event_id': command.eventId as String,
    'name': command.name,
    'scheduled_date': command.scheduledDate,
    'starts_at_micros': command.startsAt?.epochMicrosUtc,
    'ends_at_micros': command.endsAt?.epochMicrosUtc,
    'planned_exposure': command.plannedExposure,
    'venue': command.venue,
    'notes': command.notes,
    'planned_item_ids': command.plannedItemIds == null
        ? null
        : [for (final id in command.plannedItemIds!) id as String],
  },
  ActivateEvent() => {'event_id': command.eventId as String},
  CancelEvent() => {
    'event_id': command.eventId as String,
    'reason': command.reason,
  },
  AppendMovement() => {'draft': _movementDraft(command.draft)},
  CorrectMovement() => {
    'target': command.target as String,
    'replacement': command.replacement == null
        ? null
        : _movementDraft(command.replacement!),
    'reason': command.reason,
  },
  RecordCloseout() => _closeout(
    command.eventId as String,
    command.confirmedExposure,
    command.lines,
    command.note,
  ),
  ReviseCloseout() => _closeout(
    command.eventId as String,
    command.confirmedExposure,
    command.lines,
    command.note,
  ),
  CreateRecipe() => {
    'output_item_id': command.outputItemId as String,
    'name': command.name,
    'first_revision': _revision(command.firstRevision),
  },
  AddRecipeRevision() => {
    'recipe_id': command.recipeId as String,
    'revision': _revision(command.revision),
  },
  SetRecipeArchived() => {
    'recipe_id': command.recipeId as String,
    'archived': command.archived,
  },
  SaveForecastSnapshot() => {
    'event_id': command.snapshot.eventId as String,
    'policy': command.snapshot.policy.name,
    'upcoming_exposure': command.snapshot.upcomingExposure,
    'history_window': command.snapshot.historyWindow,
    'inputs_hash': command.snapshot.inputsHash,
    'assumptions_json': command.snapshot.assumptionsJson,
    'lines': [
      for (final line in command.snapshot.lines)
        {
          'item_id': line.itemId as String,
          'pack_size_micros': line.packSizeMicros,
          'on_hand_micros': line.onHandMicros,
          'confirmed_inbound_micros': line.confirmedInboundMicros,
          'expected_use_micros': line.expectedUseMicros,
          'planned_micros': line.plannedMicros,
          'load_micros': line.loadMicros,
          'acquire_micros': line.acquireMicros,
          'evidence_grade': line.evidenceGrade.name,
          'warnings': line.warnings,
          'evidence': [
            for (final e in line.evidence)
              {
                'closeout_id': e.closeoutId,
                'source_event_id': e.sourceEventId,
                'exposure': e.exposure,
                'depletion_micros': e.depletionMicros,
                'stockout': e.stockout,
                'approximate': e.approximate,
              },
          ],
        },
    ],
  },
  OverrideForecastLine() => {
    'snapshot_id': command.snapshotId as String,
    'item_id': command.itemId as String,
    'override_load_micros': command.overrideLoad?.micros,
    'reason': command.reason,
  },
};

Map<String, Object?> _movementDraft(MovementDraft draft) => {
  'item_id': draft.itemId as String,
  'kind': draft.kind.dbValue,
  'delta_micros': draft.deltaMicros,
  'event_id': draft.eventId as String?,
  'occurred_at_micros': draft.occurredAt?.epochMicrosUtc,
  'note': draft.note,
};

Map<String, Object?> _closeout(
  String eventId,
  int confirmedExposure,
  List<CloseoutLineDraft> lines,
  String note,
) => {
  'event_id': eventId,
  'confirmed_exposure': confirmedExposure,
  'note': note,
  'lines': [
    for (final line in lines)
      {
        'item_id': line.itemId as String,
        'loaded_micros': line.loaded?.micros,
        'returned_micros': line.returned?.micros,
        'waste_micros': line.waste?.micros,
        'depletion_micros': line.depletion.micros,
        'stockout': line.stockout,
        'approximate': line.approximate,
      },
  ],
};

Map<String, Object?> _revision(RecipeRevisionDraft draft) => {
  'yield_micros': draft.yieldQuantity.micros,
  'yield_label': draft.yieldLabel,
  'note': draft.note,
  'source_kind': draft.sourceKind.dbValue,
  'lines': [
    for (final line in draft.lines)
      {
        'ingredient_item_id': line.ingredientItemId as String,
        'quantity_per_batch_micros': line.quantityPerBatch.micros,
      },
  ],
};
