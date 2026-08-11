/// §11.1 family F (closeout semantics, §5): confirm writes header + lines +
/// movements atomically and closes the event; revision N+1 mirror-reverses
/// every event-linked movement of revision N; worksheet arithmetic and
/// envelope caps are enforced; the label query reads only the latest
/// revision of closed events.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/errors.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/approval/domain/proposal.dart';

import 'write_path_harness.dart';

void main() {
  late WritePathHarness h;
  late String item1;
  late String item2;
  late String eventId;

  setUp(() async {
    h = WritePathHarness();
    item1 = await h.createItem(name: 'Tortillas');
    item2 = await h.createItem(name: 'Salsa', packMicros: 500000);
    eventId = await h.createEvent(
      name: 'Market',
      plannedExposure: 100,
      plannedItemIds: [item1, item2],
    );
    await h.ok(ActivateEvent(EventId(eventId)));
    await h.receive(item1, 50000000);
    await h.receive(item2, 10000000);
  });

  tearDown(() => h.close());

  CloseoutLineDraft line(
    String itemId,
    int depletionMicros, {
    int? loaded,
    int? returned,
    int? waste,
    bool stockout = false,
    bool approximate = false,
  }) => CloseoutLineDraft(
    itemId: ItemId(itemId),
    loaded: loaded == null ? null : Quantity.fromMicros(loaded),
    returned: returned == null ? null : Quantity.fromMicros(returned),
    waste: waste == null ? null : Quantity.fromMicros(waste),
    depletion: Quantity.fromMicros(depletionMicros),
    stockout: stockout,
    approximate: approximate,
  );

  Future<CommandReceipt> confirm({
    int exposure = 100,
    List<CloseoutLineDraft>? lines,
  }) => h.ok(
    RecordCloseout(
      eventId: EventId(eventId),
      confirmedExposure: exposure,
      lines:
          lines ??
          [
            line(
              item1,
              30000000,
              loaded: 40000000,
              returned: 5000000,
              waste: 5000000,
              stockout: true,
            ),
            line(item2, 0),
          ],
    ),
  );

  group('closeout confirm (revision 1, §5 one transaction)', () {
    test('writes header + lines + movements and closes the event', () async {
      // A draft that must die with the confirm.
      await h.db.closeoutDao.upsertDraft(
        eventId: eventId,
        payloadJson: '{}',
        updatedAtMicros: 1,
      );
      final receipt = await confirm();
      final closeoutId = receipt.createdRecordIds.first;
      final commandId = receipt.commandId as String;

      final event = await h.eventRow(eventId);
      expect(event.status, 'closed');
      expect(event.closedAtMicros, isNotNull);

      final header = await h.db.closeoutDao.latestHeaderForEvent(eventId);
      expect(header!.id, closeoutId);
      expect(header.revision, 1);
      expect(header.supersedesCloseoutId, isNull);
      expect(header.confirmedExposure, 100);
      expect(header.sourceCommandId, commandId);

      final lines = await h.db.closeoutDao.linesFor(closeoutId);
      expect(lines, hasLength(2));
      final line1 = lines.singleWhere((l) => l.itemId == item1);
      expect(line1.depletionMicros, 30000000);
      expect(line1.stockout, isTrue);
      final consume = await h.movementRow(line1.consumptionMovementId!);
      expect(consume.kind, 'consume');
      expect(consume.deltaMicros, -30000000);
      expect(consume.eventId, eventId);
      expect(consume.sourceCommandId, commandId);
      final waste = await h.movementRow(line1.wasteMovementId!);
      expect(waste.kind, 'waste');
      expect(waste.deltaMicros, -5000000);
      expect(waste.eventId, eventId);

      // A confirmed zero is a legal label but deltas are never zero.
      final line2 = lines.singleWhere((l) => l.itemId == item2);
      expect(line2.depletionMicros, 0);
      expect(line2.consumptionMovementId, isNull);
      expect(line2.wasteMovementId, isNull);

      expect(await h.onHand(item1), 50000000 - 30000000 - 5000000);
      expect(await h.onHand(item2), 10000000);
      expect(await h.count('closeout_drafts'), 0, reason: 'draft deleted');
    });

    test('worksheet mismatch rejected, nothing written', () async {
      final error = await h.err(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 100,
          lines: [
            line(
              item1,
              31000000, // 40 - 5 - 5 = 30, not 31
              loaded: 40000000,
              returned: 5000000,
              waste: 5000000,
            ),
          ],
        ),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('worksheet'));
      expect((await h.eventRow(eventId)).status, 'active');
      expect(await h.count('event_closeouts'), 0);
      expect(await h.count('inventory_movements'), 2, reason: 'only setup');
    });

    test('envelope caps enforced', () async {
      expect(
        (await h.err(
          RecordCloseout(
            eventId: EventId(eventId),
            confirmedExposure: 0,
            lines: const [],
          ),
        )),
        isA<ValidationError>(),
      );
      expect(
        (await h.err(
          RecordCloseout(
            eventId: EventId(eventId),
            confirmedExposure: 1000001,
            lines: const [],
          ),
        )),
        isA<ValidationError>(),
      );
      final overCap = await h.err(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 100,
          lines: [line(item1, 1000000000001)], // > 1e12
        ),
      );
      expect(overCap, isA<ValidationError>());
      expect(overCap.message, contains('envelope'));
    });

    test('closeout is valid only for active events; lines only for planned '
        'items', () async {
      final planned = await h.createEvent(name: 'Future', plannedExposure: 10);
      expect(
        await h.err(
          RecordCloseout(
            eventId: EventId(planned),
            confirmedExposure: 10,
            lines: const [],
          ),
        ),
        isA<ValidationError>(),
      );
      final stranger = await h.createItem(name: 'Napkins');
      final notPlanned = await h.err(
        RecordCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 100,
          lines: [line(stranger, 1000000)],
        ),
      );
      expect(notPlanned, isA<ValidationError>());
      expect(notPlanned.message, contains('planned'));
    });

    test('negative on-hand never blocks the label factory', () async {
      // Deplete far more than on hand: warn, still close.
      final receipt = await confirm(
        lines: [line(item1, 900000000000)], // 900k units on 50 on hand
      );
      expect(receipt.warnings, contains('NEGATIVE_ON_HAND'));
      expect((await h.eventRow(eventId)).status, 'closed');
    });
  });

  group('closeout revision N+1 (§5 one transaction)', () {
    test('mirror-reverses every event-linked movement of revision N and '
        'appends fresh movements + header + lines', () async {
      final first = await confirm();
      final rev1Id = first.createdRecordIds.first;
      final rev1Lines = await h.db.closeoutDao.linesFor(rev1Id);
      final rev1MovementIds = [
        for (final l in rev1Lines) ...[
          if (l.consumptionMovementId != null) l.consumptionMovementId!,
          if (l.wasteMovementId != null) l.wasteMovementId!,
        ],
      ];
      expect(rev1MovementIds, hasLength(2)); // consume + waste for item1

      final revise = await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 90,
          lines: [line(item1, 25000000), line(item2, 2000000)],
        ),
      );
      final rev2Id = revise.createdRecordIds.first;

      final header = await h.db.closeoutDao.latestHeaderForEvent(eventId);
      expect(header!.id, rev2Id);
      expect(header.revision, 2);
      expect(header.supersedesCloseoutId, rev1Id);
      expect(header.confirmedExposure, 90);

      // Every rev-1 event-linked movement got exactly one mirror reversal.
      for (final movementId in rev1MovementIds) {
        final original = await h.movementRow(movementId);
        final reversal = await (h.db.select(
          h.db.inventoryMovements,
        )..where((m) => m.reversesMovementId.equals(movementId))).getSingle();
        expect(reversal.kind, 'reversal');
        expect(reversal.deltaMicros, -original.deltaMicros);
        expect(reversal.itemId, original.itemId);
        expect(reversal.eventId, original.eventId);
        expect(reversal.sourceCommandId, revise.commandId as String);
      }

      // Fresh movements linked from the new lines.
      final rev2Lines = await h.db.closeoutDao.linesFor(rev2Id);
      final newConsume1 = await h.movementRow(
        rev2Lines.singleWhere((l) => l.itemId == item1).consumptionMovementId!,
      );
      expect(newConsume1.deltaMicros, -25000000);

      // Inventory and labels agree: on-hand reflects ONLY revision 2.
      expect(await h.onHand(item1), 50000000 - 25000000);
      expect(await h.onHand(item2), 10000000 - 2000000);

      // Historical revision stays queryable.
      expect(await h.count('event_closeouts'), 2);
    });

    test('the label query returns only the latest revision of closed '
        'events', () async {
      await confirm();
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 90,
          lines: [line(item1, 25000000)],
        ),
      );
      final history = await h.db.forecastDao.labelHistory(
        item1,
        historyWindow: 12,
      );
      expect(history, hasLength(1));
      expect(history.single.confirmedExposure, 90);
      expect(history.single.depletionMicros, 25000000);
    });

    test('revision 3 mirrors revision 2, not revision 1', () async {
      await confirm();
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 90,
          lines: [line(item1, 25000000)],
        ),
      );
      // Revision 1's movements are already reversed; a third revision must
      // only reverse revision 2's (UNIQUE(reverses_movement_id) would abort
      // otherwise).
      await h.ok(
        ReviseCloseout(
          eventId: EventId(eventId),
          confirmedExposure: 95,
          lines: [line(item1, 27000000)],
        ),
      );
      final header = await h.db.closeoutDao.latestHeaderForEvent(eventId);
      expect(header!.revision, 3);
      expect(await h.onHand(item1), 50000000 - 27000000);
    });

    test('revise requires a closed event with an existing closeout', () async {
      expect(
        await h.err(
          ReviseCloseout(
            eventId: EventId(eventId), // still active
            confirmedExposure: 90,
            lines: const [],
          ),
        ),
        isA<ValidationError>(),
      );
    });

    test('closeout-written movements cannot be corrected directly', () async {
      final receipt = await confirm();
      final lines = await h.db.closeoutDao.linesFor(
        receipt.createdRecordIds.first,
      );
      final consumeId = lines
          .singleWhere((l) => l.itemId == item1)
          .consumptionMovementId!;
      final error = await h.err(
        CorrectMovement(target: MovementId(consumeId), reason: 'nope'),
      );
      expect(error, isA<ValidationError>());
      expect(error.message, contains('closeout revision'));
    });
  });
}
