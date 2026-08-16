import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/diagnostics/diag.dart';
import '../../../core/errors.dart';
import '../../../core/ids.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../data/db/app_database.dart';
import '../../forecasting/domain/snapshot.dart';
import '../../inventory/domain/movement.dart';
import '../../recipes/domain/recipe_drafts.dart';
import '../domain/approval_service.dart';
import '../domain/command_applier.dart';
import '../domain/command_codec.dart';
import '../domain/command_validator.dart';
import '../domain/commands.dart';
import '../domain/proposal.dart';
import '../domain/workspace_read_model.dart';
import 'drift_state_loader.dart';

/// The single write path over Drift (design §6.4): validates, applies every
/// effect plus the `commands` audit row in ONE transaction, threads
/// `source_command_id`, computes receipt warnings, and enforces
/// commandId idempotency. Also carries the v1 ApprovalService surface —
/// the agent path stays a frozen seam until Gate 4.
final class DriftCommandApplier implements CommandApplier, ApprovalService {
  /// Callers pass the public parameter names (`clock:`, `validator:`,
  /// `diag:`); the private named initializing formals keep the fields
  /// encapsulated.
  DriftCommandApplier(
    AppDatabase db, {
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
    this._validator = const CommandValidator(),
    this._diag = const NoopDiag(),
  }) : _db = db,
       _ids = idGenerator,
       _loader = DriftStateLoader(db);

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;
  final CommandValidator _validator;
  final Diag _diag;
  final DriftStateLoader _loader;

  /// Same-process idempotency caches: replaying a commandId returns the
  /// exact original outcome. Across restarts receipts are reconstructed
  /// from the audit trail (warnings are not persisted — best effort).
  final Map<String, CommandReceipt> _receipts = {};
  final Map<String, DomainError> _rejections = {};

  /// recordedAt monotonicity (design §6.3): nondecreasing in application
  /// order, +1 µs on clock ties, seeded from the stored maximum.
  int? _lastRecordedMicros;

  // ------------------------------------------------------ ApprovalService

  @override
  Future<Result<CommandReceipt>> submit(Proposal proposal) =>
      _db.transaction(() => _submitInTransaction(proposal));

  @override
  Future<Result<PendingProposal>> stage(Proposal proposal) async =>
      const Err(NotAvailableError('agent proposals arrive with Gate 4'));

  @override
  Future<Result<CommandReceipt>> approve(CommandId commandId) async =>
      const Err(NotAvailableError('agent proposals arrive with Gate 4'));

  @override
  Future<Result<void>> reject(
    CommandId commandId, {
    required String reason,
  }) async =>
      const Err(NotAvailableError('agent proposals arrive with Gate 4'));

  @override
  Future<List<PendingProposal>> pending() async => const [];

  // ------------------------------------------------------- CommandApplier

  @override
  Future<Result<CommandReceipt>> apply(
    ValidatedCommand command, {
    required CommandId commandId,
    required ProposalOrigin origin,
  }) => _db.transaction(() async {
    final id = commandId as String;
    if (id.length != 26) {
      return const Err<CommandReceipt>(
        ValidationError('command id must be a 26-character ULID'),
      );
    }
    final payload = encodeCommandPayload(command.command);
    final existing = await _commandRow(id);
    if (existing != null) return _replay(existing, payload);
    final state = await _loader.load(command.command);
    final receipt = await _applyEffects(
      command.command,
      commandId: id,
      origin: origin,
      createdAt: _clock.now(),
      payload: payload,
      state: state,
    );
    _receipts[id] = receipt;
    _diag.event(
      DiagEvent.commandApplied,
      count: receipt.createdRecordIds.length,
    );
    return Ok(receipt);
  });

  // ------------------------------------------------------------ pipeline

  Future<Result<CommandReceipt>> _submitInTransaction(Proposal proposal) async {
    final commandId = proposal.commandId as String;
    if (commandId.length != 26) {
      return const Err(
        ValidationError('command id must be a 26-character ULID'),
      );
    }
    final payload = encodeCommandPayload(proposal.command);
    final existing = await _commandRow(commandId);
    if (existing != null) return _replay(existing, payload);

    final state = await _loader.load(proposal.command);
    final validation = _validator.validate(proposal.command, state);
    switch (validation) {
      case Err<ValidatedCommand>(:final error):
        await _db
            .into(_db.commands)
            .insert(
              CommandsCompanion.insert(
                id: commandId,
                origin: proposal.origin.name,
                kind: commandKind(proposal.command),
                payloadJson: payload,
                status: 'rejected',
                createdAtMicros: proposal.createdAt.epochMicrosUtc,
                rejectedReason: Value('${error.code}: ${error.message}'),
              ),
            );
        _rejections[commandId] = error;
        _diag.event(
          DiagEvent.commandRejected,
          errorType: error.runtimeType.toString(),
        );
        return Err(error);
      case Ok<ValidatedCommand>(:final value):
        final receipt = await _applyEffects(
          value.command,
          commandId: commandId,
          origin: proposal.origin,
          createdAt: proposal.createdAt,
          payload: payload,
          state: state,
        );
        _receipts[commandId] = receipt;
        _diag.event(
          DiagEvent.commandApplied,
          count: receipt.createdRecordIds.length,
        );
        return Ok(receipt);
    }
  }

  Future<Command?> _commandRow(String id) => (_db.select(
    _db.commands,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<Result<CommandReceipt>> _replay(
    Command existing,
    String payload,
  ) async {
    if (existing.payloadJson != payload) {
      return const Err(
        DuplicateIdError(
          'this command id was already used with a different payload',
        ),
      );
    }
    switch (existing.status) {
      case 'applied':
        final cached = _receipts[existing.id];
        if (cached != null) return Ok(cached);
        return Ok(await _reconstructReceipt(existing));
      case 'rejected':
        final cached = _rejections[existing.id];
        if (cached != null) return Err(cached);
        return Err(_errorFromStored(existing.rejectedReason ?? ''));
      default:
        return const Err(
          NotAvailableError('staged proposals arrive with Gate 4'),
        );
    }
  }

  /// Cross-restart receipt reconstruction from `source_command_id` links.
  /// Ordering is closeouts, movements, snapshots (each by id); warnings are
  /// not persisted and come back empty.
  Future<CommandReceipt> _reconstructReceipt(Command existing) async {
    final created = <String>[];
    final closeouts =
        await (_db.select(_db.eventCloseouts)
              ..where((c) => c.sourceCommandId.equals(existing.id))
              ..orderBy([(c) => OrderingTerm.asc(c.id)]))
            .get();
    created.addAll(closeouts.map((c) => c.id));
    final movements =
        await (_db.select(_db.inventoryMovements)
              ..where((m) => m.sourceCommandId.equals(existing.id))
              ..orderBy([(m) => OrderingTerm.asc(m.id)]))
            .get();
    if (existing.kind == 'CreateItem' && movements.isNotEmpty) {
      // `items` carries no source_command_id, so a created item is normally
      // unreconstructible — but an opening count leaves exactly one movement
      // that names the item it opened, and callers expect the item id first.
      created.add(movements.first.itemId);
    }
    created.addAll(movements.map((m) => m.id));
    final snapshots =
        await (_db.select(_db.forecastSnapshots)
              ..where((s) => s.sourceCommandId.equals(existing.id))
              ..orderBy([(s) => OrderingTerm.asc(s.id)]))
            .get();
    created.addAll(snapshots.map((s) => s.id));
    return CommandReceipt(
      commandId: CommandId(existing.id),
      appliedAt: Instant(existing.appliedAtMicros ?? existing.createdAtMicros),
      createdRecordIds: created,
    );
  }

  DomainError _errorFromStored(String stored) {
    final split = stored.indexOf(': ');
    final code = split < 0 ? '' : stored.substring(0, split);
    final message = split < 0 ? stored : stored.substring(split + 2);
    return switch (code) {
      'NOT_FOUND' => NotFoundError(message),
      'DUPLICATE_ID' => DuplicateIdError(message),
      'IMMUTABLE_RECORD' => ImmutableRecordError(message),
      'ALREADY_REVERSED' => AlreadyReversedError(message),
      'RECIPE_NESTING' => RecipeNestingError(message),
      'RECIPE_CYCLE' => RecipeCycleError(message),
      'OVERFLOW' => DomainOverflowError(message),
      'STALE_STATE' => StaleStateError(message),
      'NOT_AVAILABLE' => NotAvailableError(message),
      _ => ValidationError(message),
    };
  }

  // -------------------------------------------------------------- effects

  Future<CommandReceipt> _applyEffects(
    WorkspaceCommand command, {
    required String commandId,
    required ProposalOrigin origin,
    required Instant createdAt,
    required String payload,
    required PrefetchedState state,
  }) async {
    final appliedAt = _clock.now();
    await _db
        .into(_db.commands)
        .insert(
          CommandsCompanion.insert(
            id: commandId,
            origin: origin.name,
            kind: commandKind(command),
            payloadJson: payload,
            status: 'applied',
            createdAtMicros: createdAt.epochMicrosUtc,
            appliedAtMicros: Value(appliedAt.epochMicrosUtc),
          ),
        );
    final now = appliedAt.epochMicrosUtc;
    final effects = switch (command) {
      CreateItem() => await _createItem(command, commandId, now),
      UpdateItem() => await _updateItem(command, now),
      SetItemArchived() => await _setItemArchived(command, now, state),
      DeleteItem() => await _deleteItem(command, now, state),
      DeleteAllItems() => await _deleteAllItems(now, state),
      CreateFolder() => await _createFolder(command, now, state),
      RenameFolder() => await _renameFolder(command, now),
      ReorderFolders() => await _reorderFolders(command, now),
      ArchiveFolder() => await _archiveFolder(command, now),
      SetFolderAppearance() => await _setFolderAppearance(command, now),
      SetFolderBasis() => await _setFolderBasis(command, now),
      MoveItemToFolder() => await _moveItemsToFolderIds(
        [command.itemId as String],
        command.folderId as String?,
        now,
      ),
      MoveItemsToFolder() => await _moveItemsToFolderIds(
        [for (final id in command.itemIds) id as String],
        command.folderId as String?,
        now,
      ),
      CreateEvent() => await _createEvent(command, now),
      UpdateEvent() => await _updateEvent(command, now),
      ActivateEvent() => await _setEventStatus(
        command.eventId as String,
        'active',
        now,
      ),
      CancelEvent() => await _setEventStatus(
        command.eventId as String,
        'cancelled',
        now,
      ),
      AppendMovement() => await _appendMovement(command, commandId),
      CorrectMovement() => await _correctMovement(command, commandId, state),
      RecordCloseout() => await _recordCloseout(command, commandId, now),
      ReviseCloseout() => await _reviseCloseout(command, commandId, now, state),
      CreateRecipe() => await _createRecipe(command, now, state),
      AddRecipeRevision() => await _addRecipeRevision(command, now, state),
      SetRecipeArchived() => await _setRecipeArchived(command, now, state),
      AddRecipeToItems() => await _addRecipeToItems(command, now, state),
      LinkRecipeLineToItem() => await _linkRecipeLine(command, state),
      UnlinkRecipeLine() => await _unlinkRecipeLine(command, state),
      SaveForecastSnapshot() => await _saveSnapshot(command, commandId, now),
      OverrideForecastLine() => await _overrideLine(command, now),
    };
    return CommandReceipt(
      commandId: CommandId(commandId),
      appliedAt: appliedAt,
      createdRecordIds: effects.createdIds,
      warnings: await _warnings(effects.touchedItemIds),
    );
  }

  Future<List<String>> _warnings(Set<String> touchedItemIds) async {
    for (final itemId in touchedItemIds.toList()..sort()) {
      if (await _db.ledgerDao.onHandMicros(itemId) < 0) {
        return const ['NEGATIVE_ON_HAND'];
      }
    }
    return const [];
  }

  // ------------------------------------------------------------- catalog

  /// The item row and — when the owner said how many she has — its opening
  /// `adjust` movement, in this one transaction. Either both land or
  /// neither does: no item without its opening count, no movement without
  /// its item.
  Future<_Effects> _createItem(CreateItem c, String commandId, int now) async {
    final id = _ids.newId();
    await _db
        .into(_db.items)
        .insert(
          ItemsCompanion.insert(
            id: id,
            name: c.name.trim(),
            unit: c.unit.dbValue,
            packSizeMicros: c.packSize.micros,
            unitLabel: Value(c.unitLabel?.trim()),
            servesPerUnitMicros: Value(c.servesPerUnit?.micros),
            perPersonNumerator: Value(c.perPersonRatio?.numerator),
            perPersonDenominator: Value(c.perPersonRatio?.denominator),
            folderId: Value(c.folderId as String?),
            demandBasis: Value(c.demandBasis?.dbValue),
            perEventBaselineMicros: Value(c.perEventBaseline?.micros),
            category: Value(c.category?.trim()),
            notes: Value(c.notes),
            createdAtMicros: now,
            updatedAtMicros: now,
          ),
        );
    final opening = c.openingCount?.micros ?? 0;
    if (opening == 0) return _Effects([id]);
    final movementId = await _insertMovement(
      itemId: id,
      kind: MovementKind.adjust,
      deltaMicros: opening,
      note: 'Opening count',
      commandId: commandId,
    );
    return _Effects([id, movementId], touchedItemIds: {id});
  }

  Future<_Effects> _updateItem(UpdateItem c, int now) async {
    await (_db.update(
      _db.items,
    )..where((i) => i.id.equals(c.itemId as String))).write(
      ItemsCompanion(
        name: c.name == null ? const Value.absent() : Value(c.name!.trim()),
        unit: c.unit == null ? const Value.absent() : Value(c.unit!.dbValue),
        packSizeMicros: c.packSize == null
            ? const Value.absent()
            : Value(c.packSize!.micros),
        unitLabel: switch (c) {
          UpdateItem(unitLabel: final label?) => Value(label.trim()),
          UpdateItem(clearUnitLabel: true) => const Value(null),
          _ => const Value.absent(),
        },
        servesPerUnitMicros: switch (c) {
          UpdateItem(servesPerUnit: final serves?) => Value(serves.micros),
          UpdateItem(clearServesPerUnit: true) => const Value(null),
          _ => const Value.absent(),
        },
        perPersonNumerator: switch (c) {
          UpdateItem(perPersonRatio: final ratio?) => Value(ratio.numerator),
          UpdateItem(clearPerPersonRatio: true) => const Value(null),
          _ => const Value.absent(),
        },
        perPersonDenominator: switch (c) {
          UpdateItem(perPersonRatio: final ratio?) => Value(ratio.denominator),
          UpdateItem(clearPerPersonRatio: true) => const Value(null),
          _ => const Value.absent(),
        },
        folderId: switch (c) {
          UpdateItem(folderId: final folder?) => Value(folder as String),
          UpdateItem(clearFolder: true) => const Value(null),
          _ => const Value.absent(),
        },
        demandBasis: switch (c) {
          UpdateItem(demandBasis: final basis?) => Value(basis.dbValue),
          UpdateItem(clearDemandBasis: true) => const Value(null),
          _ => const Value.absent(),
        },
        perEventBaselineMicros: switch (c) {
          UpdateItem(perEventBaseline: final baseline?) => Value(
            baseline.micros,
          ),
          UpdateItem(clearPerEventBaseline: true) => const Value(null),
          _ => const Value.absent(),
        },
        category: c.category == null
            ? const Value.absent()
            : Value(c.category!.trim()),
        notes: c.notes == null ? const Value.absent() : Value(c.notes!),
        updatedAtMicros: Value(now),
      ),
    );
    if (c.name != null) {
      // One name in both directions: renaming a recipe's output item renames
      // the recipe too. At most one live recipe binds an output item, but
      // the update covers every matching row.
      await (_db.update(_db.recipes)
            ..where((r) => r.outputItemId.equals(c.itemId as String)))
          .write(RecipesCompanion(name: Value(c.name!.trim())));
    }
    return const _Effects([]);
  }

  // ------------------------------------------------------------- folders

  Future<_Effects> _createFolder(
    CreateFolder c,
    int now,
    PrefetchedState state,
  ) async {
    final id = _ids.newId();
    // Next position after the live folders; archived positions may be
    // reused — archived folders never render, so a collision is harmless.
    final live = state.liveFolders();
    final position = live.isEmpty ? 0 : live.last.position + 1;
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            name: c.name.trim(),
            position: position,
            demandBasis: c.demandBasis.dbValue,
            alwaysPlanned: Value(c.alwaysPlanned),
            hueName: Value(c.hue?.dbValue),
            iconName: Value(c.iconName),
            createdAtMicros: now,
            updatedAtMicros: now,
          ),
        );
    return _Effects([id]);
  }

  Future<_Effects> _setFolderAppearance(SetFolderAppearance c, int now) async {
    await (_db.update(
      _db.folders,
    )..where((f) => f.id.equals(c.folderId as String))).write(
      FoldersCompanion(
        hueName: c.hue == null ? const Value.absent() : Value(c.hue!.dbValue),
        iconName: c.iconName == null
            ? const Value.absent()
            : Value(c.iconName!),
        updatedAtMicros: Value(now),
      ),
    );
    return const _Effects([]);
  }

  Future<_Effects> _renameFolder(RenameFolder c, int now) async {
    await (_db.update(
      _db.folders,
    )..where((f) => f.id.equals(c.folderId as String))).write(
      FoldersCompanion(name: Value(c.name.trim()), updatedAtMicros: Value(now)),
    );
    return const _Effects([]);
  }

  Future<_Effects> _reorderFolders(ReorderFolders c, int now) async {
    for (var i = 0; i < c.orderedFolderIds.length; i++) {
      await (_db.update(
        _db.folders,
      )..where((f) => f.id.equals(c.orderedFolderIds[i] as String))).write(
        FoldersCompanion(position: Value(i), updatedAtMicros: Value(now)),
      );
    }
    return const _Effects([]);
  }

  /// Archives the folder and moves its items to Unfiled in this one
  /// transaction — a folder can never take items down with it.
  Future<_Effects> _archiveFolder(ArchiveFolder c, int now) async {
    final id = c.folderId as String;
    await (_db.update(_db.items)..where((i) => i.folderId.equals(id))).write(
      ItemsCompanion(folderId: const Value(null), updatedAtMicros: Value(now)),
    );
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        archivedAtMicros: Value(now),
        updatedAtMicros: Value(now),
      ),
    );
    return const _Effects([]);
  }

  Future<_Effects> _setFolderBasis(SetFolderBasis c, int now) async {
    await (_db.update(
      _db.folders,
    )..where((f) => f.id.equals(c.folderId as String))).write(
      FoldersCompanion(
        demandBasis: c.demandBasis == null
            ? const Value.absent()
            : Value(c.demandBasis!.dbValue),
        alwaysPlanned: c.alwaysPlanned == null
            ? const Value.absent()
            : Value(c.alwaysPlanned!),
        updatedAtMicros: Value(now),
      ),
    );
    return const _Effects([]);
  }

  /// Shared by MoveItemToFolder (a batch of one) and MoveItemsToFolder.
  Future<_Effects> _moveItemsToFolderIds(
    List<String> itemIds,
    String? folderId,
    int now,
  ) async {
    for (final itemId in itemIds) {
      await (_db.update(_db.items)..where((i) => i.id.equals(itemId))).write(
        ItemsCompanion(folderId: Value(folderId), updatedAtMicros: Value(now)),
      );
    }
    return const _Effects([]);
  }

  Future<_Effects> _setItemArchived(
    SetItemArchived c,
    int now,
    PrefetchedState state,
  ) async {
    final item = state.item(c.itemId as String)!;
    if (item.archived == c.archived) return const _Effects([]);
    await (_db.update(_db.items)..where((i) => i.id.equals(item.id))).write(
      ItemsCompanion(
        archivedAtMicros: Value(c.archived ? now : null),
        updatedAtMicros: Value(now),
      ),
    );
    return const _Effects([]);
  }

  Future<_Effects> _deleteItem(
    DeleteItem c,
    int now,
    PrefetchedState state,
  ) async {
    await _deleteOrArchiveItem(state.item(c.itemId as String)!, now);
    return const _Effects([]);
  }

  /// The per-item delete routine over every LIVE item, in id order, inside
  /// this one command transaction. Previously-archived items are left alone.
  Future<_Effects> _deleteAllItems(int now, PrefetchedState state) async {
    final live = [
      for (final item in state.items.values)
        if (!item.archived) item,
    ]..sort((a, b) => a.id.compareTo(b.id));
    for (final item in live) {
      await _deleteOrArchiveItem(item, now);
    }
    return const _Effects([]);
  }

  /// "Delete" against an append-only ledger: hard-delete when physically
  /// possible, archive-fallback when history exists. Both paths first clear
  /// the item's mutable references — recipe_lines_v2 links (the ONLY column
  /// its limited-update trigger lets change; every line keeps its own
  /// ingredient_name, so unlinking never orphans one), the recipe output
  /// binding (the recipe simply leaves the items list — the v5 decoupled
  /// model), and plan rows on not-yet-closed events (plans are mutable; a
  /// deleted item must leave upcoming lists). Blocker rows — movements,
  /// closeout lines, frozen v1 recipe lines, forecast rows, closed-event
  /// plan rows — are never touched: any of them forces the archive path,
  /// where the live-name partial index frees the name for reuse. A blocked
  /// already-archived item keeps its original archived_at (successful no-op).
  Future<void> _deleteOrArchiveItem(ItemState item, int now) async {
    await (_db.update(_db.recipeLinesV2)
          ..where((l) => l.ingredientItemId.equals(item.id)))
        .write(const RecipeLinesV2Companion(ingredientItemId: Value(null)));
    await (_db.update(_db.recipes)
          ..where((r) => r.outputItemId.equals(item.id)))
        .write(const RecipesCompanion(outputItemId: Value(null)));
    await _db.customStatement(
      'DELETE FROM event_items WHERE item_id = ?1 AND event_id IN '
      "(SELECT id FROM events WHERE status != 'closed')",
      [item.id],
    );
    // Every remaining FK to items(id): the ledger, closeout history, the
    // frozen v1 recipe lines, the three forecast tables, and closed-event
    // plan rows (every other event_items row was deleted above).
    final blocked =
        (await _db
                .customSelect(
                  'SELECT EXISTS(SELECT 1 FROM inventory_movements '
                  'WHERE item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM closeout_lines WHERE item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM recipe_lines '
                  'WHERE ingredient_item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM forecast_lines WHERE item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM forecast_evidence '
                  'WHERE item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM forecast_overrides '
                  'WHERE item_id = ?1) '
                  'OR EXISTS(SELECT 1 FROM event_items WHERE item_id = ?1) '
                  'AS blocked',
                  variables: [Variable<String>(item.id)],
                )
                .getSingle())
            .read<int>('blocked') !=
        0;
    if (!blocked) {
      await (_db.delete(_db.items)..where((i) => i.id.equals(item.id))).go();
      return;
    }
    if (item.archived) return;
    await (_db.update(_db.items)..where((i) => i.id.equals(item.id))).write(
      ItemsCompanion(archivedAtMicros: Value(now), updatedAtMicros: Value(now)),
    );
  }

  // -------------------------------------------------------------- events

  Future<_Effects> _createEvent(CreateEvent c, int now) async {
    final id = _ids.newId();
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            id: id,
            name: c.name.trim(),
            venue: Value(c.venue),
            scheduledDate: c.scheduledDate,
            startsAtMicros: Value(c.startsAt?.epochMicrosUtc),
            endsAtMicros: Value(c.endsAt?.epochMicrosUtc),
            plannedExposure: Value(c.plannedExposure),
            notes: Value(c.notes),
            createdAtMicros: now,
            updatedAtMicros: now,
          ),
        );
    await _writePlannedItems(id, [
      for (final itemId in c.plannedItemIds) itemId as String,
    ]);
    return _Effects([id]);
  }

  Future<_Effects> _updateEvent(UpdateEvent c, int now) async {
    final id = c.eventId as String;
    await (_db.update(_db.events)..where((e) => e.id.equals(id))).write(
      EventsCompanion(
        name: c.name == null ? const Value.absent() : Value(c.name!.trim()),
        scheduledDate: c.scheduledDate == null
            ? const Value.absent()
            : Value(c.scheduledDate!),
        startsAtMicros: c.startsAt == null
            ? const Value.absent()
            : Value(c.startsAt!.epochMicrosUtc),
        endsAtMicros: c.endsAt == null
            ? const Value.absent()
            : Value(c.endsAt!.epochMicrosUtc),
        plannedExposure: c.plannedExposure == null
            ? const Value.absent()
            : Value(c.plannedExposure),
        venue: c.venue == null ? const Value.absent() : Value(c.venue),
        notes: c.notes == null ? const Value.absent() : Value(c.notes),
        updatedAtMicros: Value(now),
      ),
    );
    if (c.plannedItemIds != null) {
      await (_db.delete(
        _db.eventItems,
      )..where((e) => e.eventId.equals(id))).go();
      await _writePlannedItems(id, [
        for (final itemId in c.plannedItemIds!) itemId as String,
      ]);
    }
    return const _Effects([]);
  }

  Future<void> _writePlannedItems(String eventId, List<String> itemIds) async {
    for (var i = 0; i < itemIds.length; i++) {
      await _db
          .into(_db.eventItems)
          .insert(
            EventItemsCompanion.insert(
              eventId: eventId,
              itemId: itemIds[i],
              position: i,
            ),
          );
    }
  }

  Future<_Effects> _setEventStatus(String id, String status, int now) async {
    await (_db.update(_db.events)..where((e) => e.id.equals(id))).write(
      EventsCompanion(status: Value(status), updatedAtMicros: Value(now)),
    );
    return const _Effects([]);
  }

  // -------------------------------------------------------------- ledger

  Future<_Effects> _appendMovement(AppendMovement c, String commandId) async {
    final id = await _insertMovement(
      itemId: c.draft.itemId as String,
      kind: c.draft.kind,
      deltaMicros: c.draft.deltaMicros,
      eventId: c.draft.eventId as String?,
      occurredAt: c.draft.occurredAt,
      note: c.draft.note,
      commandId: commandId,
    );
    return _Effects([id], touchedItemIds: {c.draft.itemId as String});
  }

  Future<_Effects> _correctMovement(
    CorrectMovement c,
    String commandId,
    PrefetchedState state,
  ) async {
    final target = state.movement(c.target as String)!;
    final createdIds = <String>[];
    final touched = <String>{target.itemId};
    createdIds.add(
      await _insertMovement(
        itemId: target.itemId,
        kind: MovementKind.reversal,
        deltaMicros: -target.deltaMicros,
        eventId: target.eventId,
        reversesMovementId: target.id,
        note: c.reason.trim(),
        commandId: commandId,
      ),
    );
    final replacement = c.replacement;
    if (replacement != null) {
      createdIds.add(
        await _insertMovement(
          itemId: replacement.itemId as String,
          kind: replacement.kind,
          deltaMicros: replacement.deltaMicros,
          eventId: replacement.eventId as String?,
          occurredAt: replacement.occurredAt,
          note: replacement.note,
          commandId: commandId,
        ),
      );
      touched.add(replacement.itemId as String);
    }
    return _Effects(createdIds, touchedItemIds: touched);
  }

  Future<String> _insertMovement({
    required String itemId,
    required MovementKind kind,
    required int deltaMicros,
    String? eventId,
    String? reversesMovementId,
    Instant? occurredAt,
    required String note,
    required String commandId,
  }) async {
    final recordedAt = await _nextRecordedAt();
    final id = _ids.newId();
    await _db
        .into(_db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: id,
            itemId: itemId,
            kind: kind.dbValue,
            deltaMicros: deltaMicros,
            eventId: Value(eventId),
            reversesMovementId: Value(reversesMovementId),
            sourceCommandId: commandId,
            occurredAtMicros: (occurredAt ?? recordedAt).epochMicrosUtc,
            recordedAtMicros: recordedAt.epochMicrosUtc,
            note: Value(note),
          ),
        );
    return id;
  }

  Future<Instant> _nextRecordedAt() async {
    if (_lastRecordedMicros == null) {
      final row = await _db
          .customSelect(
            'SELECT COALESCE(MAX(recorded_at_micros), 0) AS m '
            'FROM inventory_movements',
          )
          .getSingle();
      _lastRecordedMicros = row.read<int>('m');
    }
    var next = _clock.now().epochMicrosUtc;
    if (next <= _lastRecordedMicros!) next = _lastRecordedMicros! + 1;
    _lastRecordedMicros = next;
    return Instant(next);
  }

  // ------------------------------------------------------------ closeout

  Future<_Effects> _recordCloseout(
    RecordCloseout c,
    String commandId,
    int now,
  ) async {
    final eventId = c.eventId as String;
    final closeoutId = _ids.newId();
    final effects = await _writeCloseoutBody(
      closeoutId: closeoutId,
      eventId: eventId,
      revision: 1,
      supersedesCloseoutId: null,
      confirmedExposure: c.confirmedExposure,
      note: c.note,
      lines: c.lines,
      commandId: commandId,
      now: now,
    );
    await (_db.update(_db.events)..where((e) => e.id.equals(eventId))).write(
      EventsCompanion(
        status: const Value('closed'),
        closedAtMicros: Value(now),
        updatedAtMicros: Value(now),
      ),
    );
    return effects;
  }

  Future<_Effects> _reviseCloseout(
    ReviseCloseout c,
    String commandId,
    int now,
    PrefetchedState state,
  ) async {
    final eventId = c.eventId as String;
    final latest = state.latestCloseout(eventId)!;
    final createdIds = <String>[];
    final touched = <String>{};

    // Mirror reversals of EVERY event-linked movement revision N wrote (§5).
    final targets =
        await (_db.select(_db.inventoryMovements)
              ..where((m) => m.id.isIn(latest.eventLinkedMovementIds))
              ..orderBy([(m) => OrderingTerm.asc(m.id)]))
            .get();
    for (final target in targets) {
      createdIds.add(
        await _insertMovement(
          itemId: target.itemId,
          kind: MovementKind.reversal,
          deltaMicros: -target.deltaMicros,
          eventId: target.eventId,
          reversesMovementId: target.id,
          note: 'closeout revision',
          commandId: commandId,
        ),
      );
      touched.add(target.itemId);
    }

    final closeoutId = _ids.newId();
    final body = await _writeCloseoutBody(
      closeoutId: closeoutId,
      eventId: eventId,
      revision: latest.revision + 1,
      supersedesCloseoutId: latest.id,
      confirmedExposure: c.confirmedExposure,
      note: c.note,
      lines: c.lines,
      commandId: commandId,
      now: now,
    );
    // Primary record first (like every other receipt), then the mirror
    // reversals, then the fresh movements.
    return _Effects(
      [closeoutId, ...createdIds, ...body.createdIds.skip(1)],
      touchedItemIds: {...touched, ...body.touchedItemIds},
    );
  }

  /// Fresh consume/waste movements, header, and lines — shared by confirm
  /// and revise. Order matters for FKs: movements before lines, header
  /// before lines.
  Future<_Effects> _writeCloseoutBody({
    required String closeoutId,
    required String eventId,
    required int revision,
    required String? supersedesCloseoutId,
    required int confirmedExposure,
    required String note,
    required List<CloseoutLineDraft> lines,
    required String commandId,
    required int now,
  }) async {
    final createdIds = <String>[closeoutId];
    final touched = <String>{};
    final lineCompanions = <CloseoutLinesCompanion>[];
    for (final line in lines) {
      final itemId = line.itemId as String;
      touched.add(itemId);
      String? consumeId;
      String? wasteId;
      // A confirmed zero is a legal label but deltas are never zero (§5).
      if (line.depletion.micros > 0) {
        consumeId = await _insertMovement(
          itemId: itemId,
          kind: MovementKind.consume,
          deltaMicros: -line.depletion.micros,
          eventId: eventId,
          note: '',
          commandId: commandId,
        );
        createdIds.add(consumeId);
      }
      final wasteMicros = line.waste?.micros ?? 0;
      if (wasteMicros > 0) {
        wasteId = await _insertMovement(
          itemId: itemId,
          kind: MovementKind.waste,
          deltaMicros: -wasteMicros,
          eventId: eventId,
          note: '',
          commandId: commandId,
        );
        createdIds.add(wasteId);
      }
      lineCompanions.add(
        CloseoutLinesCompanion.insert(
          closeoutId: closeoutId,
          itemId: itemId,
          loadedMicros: Value(line.loaded?.micros),
          returnedMicros: Value(line.returned?.micros),
          wasteMicros: Value(line.waste?.micros),
          depletionMicros: line.depletion.micros,
          stockout: Value(line.stockout),
          approximate: Value(line.approximate),
          consumptionMovementId: Value(consumeId),
          wasteMovementId: Value(wasteId),
        ),
      );
    }
    await _db
        .into(_db.eventCloseouts)
        .insert(
          EventCloseoutsCompanion.insert(
            id: closeoutId,
            eventId: eventId,
            revision: revision,
            supersedesCloseoutId: Value(supersedesCloseoutId),
            confirmedExposure: confirmedExposure,
            note: Value(note),
            sourceCommandId: commandId,
            confirmedAtMicros: now,
          ),
        );
    for (final companion in lineCompanions) {
      await _db.into(_db.closeoutLines).insert(companion);
    }
    // A draft is not a record; it dies with the confirm (§4).
    await (_db.delete(
      _db.closeoutDrafts,
    )..where((d) => d.eventId.equals(eventId))).go();
    return _Effects(createdIds, touchedItemIds: touched);
  }

  // ------------------------------------------------------------- recipes

  Future<_Effects> _createRecipe(
    CreateRecipe c,
    int now,
    PrefetchedState state,
  ) async {
    final recipeId = _ids.newId();
    await _db
        .into(_db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: recipeId,
            outputItemId: Value(c.outputItemId as String?),
            name: c.name.trim(),
            createdAtMicros: now,
          ),
        );
    final revisionId = await _insertRevision(
      recipeId: recipeId,
      revision: 1,
      draft: c.firstRevision,
      now: now,
      state: state,
    );
    return _Effects([recipeId, revisionId]);
  }

  Future<_Effects> _addRecipeRevision(
    AddRecipeRevision c,
    int now,
    PrefetchedState state,
  ) async {
    final recipe = state.recipe(c.recipeId as String)!;
    // The rename that rides the revise: one name for the recipe and its
    // output item, updated together in this transaction. A name equal to
    // the current one is a no-op — nothing's updated_at moves.
    final trimmed = c.name?.trim();
    if (trimmed != null && trimmed != recipe.name) {
      await (_db.update(_db.recipes)..where((r) => r.id.equals(recipe.id)))
          .write(RecipesCompanion(name: Value(trimmed)));
      if (recipe.outputItemId != null) {
        await (_db.update(
          _db.items,
        )..where((i) => i.id.equals(recipe.outputItemId!))).write(
          ItemsCompanion(name: Value(trimmed), updatedAtMicros: Value(now)),
        );
      }
    }
    final revisionId = await _insertRevision(
      recipeId: recipe.id,
      revision: recipe.latestRevision + 1,
      draft: c.revision,
      now: now,
      state: state,
    );
    return _Effects([revisionId]);
  }

  Future<String> _insertRevision({
    required String recipeId,
    required int revision,
    required RecipeRevisionDraft draft,
    required int now,
    required PrefetchedState state,
  }) async {
    final revisionId = _ids.newId();
    await _db
        .into(_db.recipeRevisions)
        .insert(
          RecipeRevisionsCompanion.insert(
            id: revisionId,
            recipeId: recipeId,
            revision: revision,
            yieldMicros: draft.yieldQuantity.micros,
            yieldLabel: Value(draft.yieldLabel),
            sourceKind: draft.sourceKind.dbValue,
            note: Value(draft.note),
            createdAtMicros: now,
          ),
        );
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      // Every stored line carries a name: the draft's own, or a snapshot of
      // the linked item's name — so unlinking can never orphan the line.
      // The validator guarantees one of the two exists.
      final name =
          line.name?.trim() ??
          state.item(line.ingredientItemId! as String)!.name;
      await _db
          .into(_db.recipeLinesV2)
          .insert(
            RecipeLinesV2Companion.insert(
              revisionId: revisionId,
              lineIndex: i,
              ingredientName: name,
              unitLabel: Value(line.unitLabel?.trim()),
              ingredientItemId: Value(line.ingredientItemId as String?),
              quantityPerBatchMicros: line.quantityPerBatch.micros,
            ),
          );
    }
    return revisionId;
  }

  /// v5: the recipe joins the item list — its output item is created in the
  /// chosen folder, `recipes.output_item_id` is bound, and each chosen free
  /// line gets an item created (in ITS chosen folder) and linked, all inside
  /// this one command transaction. Receipt ids: output item first, then the
  /// ingredient items in the order they were chosen.
  Future<_Effects> _addRecipeToItems(
    AddRecipeToItems c,
    int now,
    PrefetchedState state,
  ) async {
    final recipe = state.recipe(c.recipeId as String)!;
    final outputItemId = _ids.newId();
    await _db
        .into(_db.items)
        .insert(
          ItemsCompanion.insert(
            id: outputItemId,
            name: recipe.name.trim(),
            unit: 'each',
            packSizeMicros: 1000000,
            folderId: Value(c.folderId as String?),
            createdAtMicros: now,
            updatedAtMicros: now,
          ),
        );
    await (_db.update(_db.recipes)..where((r) => r.id.equals(recipe.id))).write(
      RecipesCompanion(outputItemId: Value(outputItemId)),
    );
    final createdIds = <String>[outputItemId];
    for (final ingredient in c.ingredients) {
      final line = recipe.currentLines.firstWhere(
        (l) => l.lineIndex == ingredient.lineIndex,
      );
      final itemId = _ids.newId();
      await _db
          .into(_db.items)
          .insert(
            ItemsCompanion.insert(
              id: itemId,
              name: line.name.trim(),
              unit: 'each',
              packSizeMicros: 1000000,
              unitLabel: Value(line.unitLabel),
              folderId: Value(ingredient.folderId as String?),
              createdAtMicros: now,
              updatedAtMicros: now,
            ),
          );
      await _writeLineLink(
        revisionId: recipe.latestRevisionId!,
        lineIndex: ingredient.lineIndex,
        itemId: itemId,
      );
      createdIds.add(itemId);
    }
    return _Effects(createdIds);
  }

  Future<_Effects> _linkRecipeLine(
    LinkRecipeLineToItem c,
    PrefetchedState state,
  ) async {
    final recipe = state.recipe(c.recipeId as String)!;
    await _writeLineLink(
      revisionId: recipe.latestRevisionId!,
      lineIndex: c.lineIndex,
      itemId: c.itemId as String,
    );
    return const _Effects([]);
  }

  Future<_Effects> _unlinkRecipeLine(
    UnlinkRecipeLine c,
    PrefetchedState state,
  ) async {
    final recipe = state.recipe(c.recipeId as String)!;
    await _writeLineLink(
      revisionId: recipe.latestRevisionId!,
      lineIndex: c.lineIndex,
      itemId: null,
    );
    return const _Effects([]);
  }

  /// The ONLY legal UPDATE on `recipe_lines_v2` — the link column; the
  /// limited-update trigger aborts anything wider.
  Future<void> _writeLineLink({
    required String revisionId,
    required int lineIndex,
    required String? itemId,
  }) async {
    await (_db.update(_db.recipeLinesV2)..where(
          (l) =>
              l.revisionId.equals(revisionId) & l.lineIndex.equals(lineIndex),
        ))
        .write(RecipeLinesV2Companion(ingredientItemId: Value(itemId)));
  }

  Future<_Effects> _setRecipeArchived(
    SetRecipeArchived c,
    int now,
    PrefetchedState state,
  ) async {
    final recipe = state.recipe(c.recipeId as String)!;
    if (recipe.archived == c.archived) return const _Effects([]);
    await (_db.update(_db.recipes)..where((r) => r.id.equals(recipe.id))).write(
      RecipesCompanion(archivedAtMicros: Value(c.archived ? now : null)),
    );
    return const _Effects([]);
  }

  // ---------------------------------------------------------- forecasting

  Future<_Effects> _saveSnapshot(
    SaveForecastSnapshot c,
    String commandId,
    int now,
  ) async {
    final draft = c.snapshot;
    final snapshotId = _ids.newId();
    await _db
        .into(_db.forecastSnapshots)
        .insert(
          ForecastSnapshotsCompanion.insert(
            id: snapshotId,
            eventId: draft.eventId as String,
            method: forecastMethodDirectMedian,
            methodVersion: forecastMethodVersion,
            policy: draft.policy.name,
            upcomingExposure: draft.upcomingExposure,
            historyWindow: draft.historyWindow,
            inputsHash: draft.inputsHash,
            assumptionsJson: Value(draft.assumptionsJson),
            sourceCommandId: commandId,
            createdAtMicros: now,
          ),
        );
    for (final line in draft.lines) {
      await _db
          .into(_db.forecastLines)
          .insert(
            ForecastLinesCompanion.insert(
              snapshotId: snapshotId,
              itemId: line.itemId as String,
              packSizeMicros: line.packSizeMicros,
              onHandMicros: line.onHandMicros,
              confirmedInboundMicros: Value(line.confirmedInboundMicros),
              demandBasis: Value(line.demandBasis.dbValue),
              expectedUseMicros: Value(line.expectedUseMicros),
              plannedMicros: Value(line.plannedMicros),
              loadMicros: Value(line.loadMicros),
              acquireMicros: Value(line.acquireMicros),
              baselineServesPerUnitMicros: Value(
                line.baselineServesPerUnitMicros,
              ),
              baselinePerPersonNumerator: Value(
                line.baselinePerPersonNumerator,
              ),
              baselinePerPersonDenominator: Value(
                line.baselinePerPersonDenominator,
              ),
              baselinePerEventMicros: Value(line.baselinePerEventMicros),
              baselineExpectedUseMicros: Value(line.baselineExpectedUseMicros),
              baselinePlannedMicros: Value(line.baselinePlannedMicros),
              baselineLoadMicros: Value(line.baselineLoadMicros),
              baselineAcquireMicros: Value(line.baselineAcquireMicros),
              evidenceGrade: evidenceGradeToDb(line.evidenceGrade),
              warningsJson: Value(jsonEncode(line.warnings)),
            ),
          );
      for (var i = 0; i < line.evidence.length; i++) {
        final evidence = line.evidence[i];
        await _db
            .into(_db.forecastEvidence)
            .insert(
              ForecastEvidenceCompanion.insert(
                snapshotId: snapshotId,
                itemId: line.itemId as String,
                position: i,
                closeoutId: evidence.closeoutId,
                sourceEventId: evidence.sourceEventId,
                exposure: evidence.exposure,
                depletionMicros: evidence.depletionMicros,
                stockout: evidence.stockout,
                approximate: evidence.approximate,
              ),
            );
      }
    }
    return _Effects([snapshotId]);
  }

  Future<_Effects> _overrideLine(OverrideForecastLine c, int now) async {
    final overrideId = _ids.newId();
    await _db
        .into(_db.forecastOverrides)
        .insert(
          ForecastOverridesCompanion.insert(
            id: overrideId,
            snapshotId: c.snapshotId as String,
            itemId: c.itemId as String,
            overrideLoadMicros: Value(c.overrideLoad?.micros),
            reason: c.reason.trim(),
            createdAtMicros: now,
          ),
        );
    return _Effects([overrideId]);
  }
}

final class _Effects {
  const _Effects(this.createdIds, {this.touchedItemIds = const {}});

  final List<String> createdIds;

  /// Items whose derived on-hand may have changed — checked for the
  /// NEGATIVE_ON_HAND receipt warning (§5: warns, never blocks).
  final Set<String> touchedItemIds;
}
