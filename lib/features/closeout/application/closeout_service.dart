import '../../../core/errors.dart';
import '../../../core/ids.dart';
import '../../../core/quantity.dart';
import '../../../core/result.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../../../data/db/app_database.dart' as db;
import '../../approval/domain/approval_service.dart';
import '../../approval/domain/commands.dart';
import '../../approval/domain/proposal.dart';
import '../../forecasting/application/forecast_service.dart';
import '../domain/closeout.dart';
import '../domain/closeout_form.dart';

/// Prefill for the closeout form (design §6.5): per planned item the latest
/// snapshot's load (or its live override), blank when no snapshot exists.
final class CloseoutPrefill {
  const CloseoutPrefill({
    required this.eventId,
    this.plannedExposure,
    this.lines = const [],
  });

  final String eventId;

  /// "estimate was N" caption source.
  final int? plannedExposure;
  final List<CloseoutPrefillLine> lines;
}

final class CloseoutPrefillLine {
  const CloseoutPrefillLine({
    required this.itemId,
    required this.itemName,
    required this.unit,
    this.plannedLoadMicros,
  });

  final String itemId;
  final String itemName;
  final ItemUnit unit;

  /// "planned load was N" caption source; null when no snapshot exists.
  final int? plannedLoadMicros;
}

/// The label factory's screen surface (design §6.5). Draft autosave is an
/// explicit exception to the command path; confirm/revise go through it.
abstract interface class CloseoutService {
  Future<CloseoutPrefill> prefill(String eventId);

  /// Upsert `closeout_drafts` (autosave; not a record).
  Future<void> saveDraft(CloseoutFormDraft draft);
  Future<CloseoutFormDraft?> loadDraft(String eventId);
  Future<Result<CommandReceipt>> confirm(CloseoutFormDraft draft);
  Future<Result<CommandReceipt>> revise(CloseoutFormDraft draft);
  Stream<List<EventCloseout>> watchRevisions(String eventId);
}

final class DriftCloseoutService implements CloseoutService {
  DriftCloseoutService(
    db.AppDatabase database,
    ApprovalService approval, {
    required ForecastService forecastService,
    IdGenerator idGenerator = const UlidIdGenerator(),
    this._clock = const SystemClock(),
  }) : _db = database,
       _approval = approval,
       _forecast = forecastService,
       _ids = idGenerator;

  final db.AppDatabase _db;
  final ApprovalService _approval;
  final ForecastService _forecast;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<CloseoutPrefill> prefill(String eventId) async {
    final event = await _db.eventDao.byId(eventId);
    if (event == null) {
      return CloseoutPrefill(eventId: eventId);
    }
    final planned = await _db.eventDao.plannedItems(eventId);
    final items = await _db.itemDao.byIds([for (final p in planned) p.itemId]);
    final itemsById = {for (final item in items) item.id: item};
    final snapshot = await _forecast.watchLatestSnapshot(eventId).first;
    final loadByItem = {
      for (final line in snapshot?.lines ?? const [])
        line.itemId as String: line.effectiveLoadMicros,
    };
    return CloseoutPrefill(
      eventId: eventId,
      plannedExposure: event.plannedExposure,
      lines: [
        for (final p in planned)
          if (itemsById[p.itemId] != null)
            CloseoutPrefillLine(
              itemId: p.itemId,
              itemName: itemsById[p.itemId]!.name,
              unit: ItemUnit.fromDb(itemsById[p.itemId]!.unit),
              plannedLoadMicros: loadByItem[p.itemId],
            ),
      ],
    );
  }

  @override
  Future<void> saveDraft(CloseoutFormDraft draft) =>
      _db.closeoutDao.upsertDraft(
        eventId: draft.eventId,
        payloadJson: encodeCloseoutFormDraft(draft),
        updatedAtMicros: _clock.now().epochMicrosUtc,
      );

  @override
  Future<CloseoutFormDraft?> loadDraft(String eventId) async {
    final row = await _db.closeoutDao.draftFor(eventId);
    return row == null ? null : decodeCloseoutFormDraft(row.payloadJson);
  }

  @override
  Future<Result<CommandReceipt>> confirm(CloseoutFormDraft draft) async {
    final lines = _toCommandLines(draft);
    return lines.fold(
      (value) => _submit(
        RecordCloseout(
          eventId: EventId(draft.eventId),
          confirmedExposure: draft.confirmedExposure ?? 0,
          lines: value,
          note: draft.note,
        ),
      ),
      (error) => Future.value(Err(error)),
    );
  }

  @override
  Future<Result<CommandReceipt>> revise(CloseoutFormDraft draft) async {
    final lines = _toCommandLines(draft);
    return lines.fold(
      (value) => _submit(
        ReviseCloseout(
          eventId: EventId(draft.eventId),
          confirmedExposure: draft.confirmedExposure ?? 0,
          lines: value,
          note: draft.note,
        ),
      ),
      (error) => Future.value(Err(error)),
    );
  }

  @override
  Stream<List<EventCloseout>> watchRevisions(String eventId) => _db.closeoutDao
      .watchHeadersForEvent(eventId)
      .asyncMap(
        (headers) async => [
          for (final header in headers)
            EventCloseout(
              id: CloseoutId(header.id),
              eventId: EventId(header.eventId),
              revision: header.revision,
              supersedes: header.supersedesCloseoutId == null
                  ? null
                  : CloseoutId(header.supersedesCloseoutId!),
              confirmedExposure: header.confirmedExposure,
              note: header.note,
              confirmedAt: Instant(header.confirmedAtMicros),
              lines: [
                for (final line in await _db.closeoutDao.linesFor(header.id))
                  CloseoutLine(
                    itemId: ItemId(line.itemId),
                    loaded: line.loadedMicros == null
                        ? null
                        : Quantity.fromMicros(line.loadedMicros!),
                    returned: line.returnedMicros == null
                        ? null
                        : Quantity.fromMicros(line.returnedMicros!),
                    waste: line.wasteMicros == null
                        ? null
                        : Quantity.fromMicros(line.wasteMicros!),
                    depletion: Quantity.fromMicros(line.depletionMicros),
                    stockout: line.stockout,
                    approximate: line.approximate,
                    consumptionMovementId: line.consumptionMovementId == null
                        ? null
                        : MovementId(line.consumptionMovementId!),
                    wasteMovementId: line.wasteMovementId == null
                        ? null
                        : MovementId(line.wasteMovementId!),
                  ),
              ],
            ),
        ],
      );

  /// Form → command lines. The command path re-validates everything; this
  /// only rejects forms that are structurally incomplete.
  Result<List<CloseoutLineDraft>> _toCommandLines(CloseoutFormDraft draft) {
    if (draft.confirmedExposure == null) {
      return const Err(
        ValidationError('confirmed exposure is required to close out'),
      );
    }
    final lines = <CloseoutLineDraft>[];
    for (final line in draft.lines) {
      if (line.skipped) continue;
      final depletion = line.depletion;
      if (depletion == null) {
        return const Err(
          ValidationError(
            'every confirmed line needs a depletion (or skip the item)',
          ),
        );
      }
      lines.add(
        CloseoutLineDraft(
          itemId: ItemId(line.itemId),
          loaded: line.loaded,
          returned: line.returned,
          waste: line.waste,
          depletion: depletion,
          stockout: line.stockout,
          approximate: line.approximate,
        ),
      );
    }
    return Ok(lines);
  }

  Future<Result<CommandReceipt>> _submit(WorkspaceCommand command) =>
      _approval.submit(
        Proposal(
          commandId: CommandId(_ids.newId()),
          origin: ProposalOrigin.form,
          command: command,
          createdAt: _clock.now(),
        ),
      );
}
