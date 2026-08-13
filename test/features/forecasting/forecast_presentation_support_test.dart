/// Pure presentation helpers that make a claim about stored numbers.
///
/// [selloutHandlingNote] describes an arithmetic correction that only exists
/// from method v2 on. A stored snapshot is frozen history, so the note has to
/// read the SNAPSHOT's version rather than the app's — otherwise every v1
/// forecast on the device starts claiming a correction that never ran, on a
/// closed event where no banner contradicts it and no refresh is offered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/presentation/forecast_presentation_support.dart';

void main() {
  EvidenceView day(int position, {required bool ranOut}) => EvidenceView(
    position: position,
    closeoutId: CloseoutId('closeout-$position'),
    sourceEventId: EventId('event-$position'),
    exposure: 100,
    depletionMicros: 40000000,
    stockout: ranOut,
    approximate: false,
  );

  ForecastLineView lineWith(List<EvidenceView> evidence) => ForecastLineView(
    itemId: const ItemId('item'),
    packSizeMicros: 1000000,
    onHandMicros: 0,
    confirmedInboundMicros: 0,
    expectedUseMicros: 55000000,
    evidenceGrade: evidence.length == 1
        ? EvidenceGrade.singleEvent
        : EvidenceGrade.observedRange,
    evidence: evidence,
  );

  final oneOfThree = lineWith([
    day(0, ranOut: true),
    day(1, ranOut: false),
    day(2, ranOut: false),
  ]);

  group('current method (v2)', () {
    test('says the sell-out days were raised to the typical rate', () {
      expect(
        selloutHandlingNote(oneOfThree, methodVersion: forecastMethodVersion),
        '1 of 3 — raised to your typical rate',
      );
    });

    test('says the busiest day was used when every day ran out', () {
      final all = lineWith([day(0, ranOut: true), day(1, ranOut: true)]);
      expect(
        selloutHandlingNote(all, methodVersion: forecastMethodVersion),
        '2 of 2 — busiest day used for all',
      );
    });

    test('stays silent when nothing ran out', () {
      final none = lineWith([day(0, ranOut: false), day(1, ranOut: false)]);
      expect(
        selloutHandlingNote(none, methodVersion: forecastMethodVersion),
        isNull,
      );
    });
  });

  group('a snapshot stored before the correction existed (v1)', () {
    test('never claims the sell-out days were allowed for', () {
      final note = selloutHandlingNote(oneOfThree, methodVersion: 1)!;
      expect(note, '1 of 3 — this forecast did not allow for them');
      expect(
        note,
        isNot(contains('raised')),
        reason: 'v1 numbers were never raised; saying so would be a lie',
      );
    });

    test('still reports that the days ran out — the flags are real', () {
      expect(
        selloutHandlingNote(oneOfThree, methodVersion: 1),
        startsWith('1 of 3'),
      );
    });

    test('an all-sell-out v1 line makes no busiest-day claim either', () {
      final all = lineWith([day(0, ranOut: true), day(1, ranOut: true)]);
      expect(
        selloutHandlingNote(all, methodVersion: 1),
        '2 of 2 — this forecast did not allow for them',
      );
    });
  });

  test('a line with no confirmed history has no arithmetic to describe', () {
    final blank = ForecastLineView(
      itemId: const ItemId('item'),
      packSizeMicros: 1000000,
      onHandMicros: 0,
      confirmedInboundMicros: 0,
      evidenceGrade: EvidenceGrade.insufficientData,
      evidence: const [],
    );
    expect(
      selloutHandlingNote(blank, methodVersion: forecastMethodVersion),
      isNull,
    );
  });
}
