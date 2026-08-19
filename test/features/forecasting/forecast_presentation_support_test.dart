/// The forecast line, said in one sentence.
///
/// [forecastLineSentence] replaced a four-cell grid and a six-row assumptions
/// table, so it now carries the whole burden of being TRUE: every stored
/// shape a line can take — no history, one event, a cold-start guess of each
/// kind, confirmed history the arithmetic could not carry, an override in
/// force, an empty shelf — has to come out as words that are right, not as a
/// template with a hole in it. That is what this file pins.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/time.dart';
import 'package:loadout/features/catalog/domain/demand_basis.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/forecasting/domain/snapshot.dart';
import 'package:loadout/features/forecasting/presentation/forecast_presentation_support.dart';

void main() {
  EvidenceView day(
    int position, {
    required int exposure,
    required int used,
    bool ranOut = false,
  }) => EvidenceView(
    position: position,
    closeoutId: CloseoutId('closeout-$position'),
    sourceEventId: EventId('event-$position'),
    exposure: exposure,
    depletionMicros: used * 1000000,
    stockout: ranOut,
    approximate: false,
  );

  /// Evidence is stored newest first (the §4.3 label query orders by
  /// scheduled date DESC), which is what makes "last time … before that"
  /// mean what it says.
  ForecastLineView confirmed({
    required List<EvidenceView> history,
    required int load,
    int onHandMicros = 0,
    int confirmedInboundMicros = 0,
    DemandBasis demandBasis = DemandBasis.perPerson,
    OverrideView? override,
  }) => ForecastLineView(
    itemId: const ItemId('item'),
    packSizeMicros: 1000000,
    onHandMicros: onHandMicros,
    confirmedInboundMicros: confirmedInboundMicros,
    demandBasis: demandBasis,
    expectedUseMicros: load * 1000000,
    plannedMicros: load * 1000000,
    loadMicros: load * 1000000,
    acquireMicros: load * 1000000,
    evidenceGrade: history.length == 1
        ? EvidenceGrade.singleEvent
        : EvidenceGrade.observedRange,
    evidence: history,
    override: override,
  );

  String sentence(ForecastLineView line, {int exposure = 165}) =>
      forecastLineSentence(
        line,
        upcomingExposure: exposure,
        exposureLabel: 'people',
      );

  group('confirmed history', () {
    test('two or more events: last time, and the one before that', () {
      final line = confirmed(
        history: [
          day(0, exposure: 165, used: 16),
          day(1, exposure: 150, used: 14),
        ],
        load: 16,
        onHandMicros: 18000000,
      );
      expect(
        sentence(line),
        'Bring 16. Last time you used 16 for 165 people; before that, '
        '14 for 150. You have 18.',
      );
    });

    test('one event says so, and never invents a second', () {
      final line = confirmed(
        history: [day(0, exposure: 165, used: 16)],
        load: 16,
        onHandMicros: 18000000,
      );
      expect(
        sentence(line),
        'Bring 16. Last time you used 16 for 165 people. You have 18.',
      );
      expect(sentence(line), isNot(contains('before that')));
    });

    test('only the two most recent are quoted; the rows carry the rest', () {
      final line = confirmed(
        history: [
          day(0, exposure: 100, used: 30),
          day(1, exposure: 90, used: 28),
          day(2, exposure: 80, used: 25),
        ],
        load: 40,
      );
      expect(sentence(line), isNot(contains('25')));
    });

    test('a per-event item quotes no headcount — that is what it means', () {
      final line = confirmed(
        history: [
          day(0, exposure: 200, used: 2),
          day(1, exposure: 100, used: 2),
        ],
        load: 3,
        demandBasis: DemandBasis.perEvent,
      );
      expect(
        sentence(line, exposure: 2000),
        'Bring 3. Last time you used 2; before that, 2. You have none.',
      );
      expect(sentence(line, exposure: 2000), isNot(contains('200')));
    });

    test('the shelf is reported in words, never as a bare 0', () {
      final empty = confirmed(
        history: [day(0, exposure: 100, used: 30)],
        load: 40,
      );
      expect(sentence(empty), endsWith('You have none.'));

      // A negative derived on-hand is still "none", never "-30".
      final negative = confirmed(
        history: [day(0, exposure: 100, used: 30)],
        load: 40,
        onHandMicros: -30000000,
      );
      expect(sentence(negative), endsWith('You have none.'));
      expect(sentence(negative), isNot(contains('-30')));

      // Confirmed inbound counts toward what you have, as it always did.
      final inbound = confirmed(
        history: [day(0, exposure: 100, used: 30)],
        load: 40,
        onHandMicros: 5000000,
        confirmedInboundMicros: 7000000,
      );
      expect(sentence(inbound), endsWith('You have 12.'));
    });
  });

  group('no confirmed history', () {
    ForecastLineView baseline({
      int? servesPerUnitMicros,
      int? perPersonNumerator,
      int? perPersonDenominator,
      int? perEventMicros,
      required int load,
      DemandBasis demandBasis = DemandBasis.perPerson,
    }) => ForecastLineView(
      itemId: const ItemId('item'),
      packSizeMicros: 1000000,
      onHandMicros: 0,
      confirmedInboundMicros: 0,
      demandBasis: demandBasis,
      baselineServesPerUnitMicros: servesPerUnitMicros,
      baselinePerPersonNumerator: perPersonNumerator,
      baselinePerPersonDenominator: perPersonDenominator,
      baselinePerEventMicros: perEventMicros,
      baselineExpectedUseMicros: load * 1000000,
      baselinePlannedMicros: load * 1000000,
      baselineLoadMicros: load * 1000000,
      baselineAcquireMicros: load * 1000000,
      evidenceGrade: EvidenceGrade.insufficientData,
    );

    test('"1 serves N" is called a guess and shows its own arithmetic', () {
      final line = baseline(servesPerUnitMicros: 4000000, load: 42);
      expect(
        sentence(line, exposure: 150),
        'Bring 42. A guess — no past events to learn from yet. One serves 4, '
        'and you are expecting 150 people. You have none.',
      );
    });

    test('the flipped per-person ratio is called a guess too', () {
      final line = baseline(
        perPersonNumerator: 3,
        perPersonDenominator: 1,
        load: 660,
      );
      expect(
        sentence(line, exposure: 200),
        contains(
          'A guess — no past events to learn from yet. You said 3 per person, '
          'and you are expecting 200 people.',
        ),
      );
    });

    test('"you usually bring N" names no headcount', () {
      final line = baseline(
        perEventMicros: 2000000,
        load: 3,
        demandBasis: DemandBasis.perEvent,
      );
      expect(
        sentence(line, exposure: 2000),
        'Bring 3. A guess — no past events to learn from yet. You said you '
        'usually bring 2. You have none.',
      );
      expect(sentence(line, exposure: 2000), isNot(contains('2000')));
    });

    test('nothing at all: no number, and no pretence of a guess', () {
      final blank = ForecastLineView(
        itemId: const ItemId('item'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        confirmedInboundMicros: 0,
        evidenceGrade: EvidenceGrade.insufficientData,
      );
      expect(
        sentence(blank),
        'No number yet. No past events to learn from yet, and nothing saved '
        'for this item to guess from. You have none.',
      );
      // There is no guess here, so it must not be described as one.
      expect(sentence(blank), isNot(contains('A guess')));
      expect(sentence(blank), isNot(contains('Bring')));
    });
  });

  test('history the arithmetic could not carry is never called "no past '
      'events"', () {
    // The out-of-envelope refusal: stored as insufficient_data WITH its
    // evidence. Saying there is no history over real closeouts would be a lie.
    final line = ForecastLineView(
      itemId: const ItemId('item'),
      packSizeMicros: 1000000,
      onHandMicros: 0,
      confirmedInboundMicros: 0,
      evidenceGrade: EvidenceGrade.insufficientData,
      evidence: [day(0, exposure: 100, used: 30)],
    );
    expect(
      sentence(line),
      'No number yet. Loadout could not work out a number from your past '
      'events. You have none.',
    );
    expect(sentence(line), isNot(contains('no past events to learn from')));
    expect(isColdStartLine(line), isFalse);
    // …and the badge does not deny the closeouts listed under it either.
    expect(evidenceBadgeLabel(line), '1 event');
  });

  group('an override in force', () {
    test('says whose number it is, why, and what the app would have said', () {
      final line = confirmed(
        history: [
          day(0, exposure: 165, used: 16),
          day(1, exposure: 150, used: 14),
        ],
        load: 16,
        onHandMicros: 18000000,
        override: const OverrideView(
          id: 'o1',
          overrideLoadMicros: 24000000,
          reason: 'roadworks reroute foot traffic',
          createdAt: Instant(0),
        ),
      );
      expect(
        sentence(line),
        'Bring 24. You set that yourself: roadworks reroute foot traffic. '
        'Loadout worked out 16. Last time you used 16 for 165 people; before '
        'that, 14 for 150. You have 18.',
      );
    });

    test('a trailing full stop in the reason never doubles up', () {
      final line = confirmed(
        history: [day(0, exposure: 100, used: 30)],
        load: 40,
        override: const OverrideView(
          id: 'o1',
          overrideLoadMicros: 50000000,
          reason: 'big crowd expected.',
          createdAt: Instant(0),
        ),
      );
      expect(sentence(line), contains('yourself: big crowd expected. Loadout'));
      expect(sentence(line), isNot(contains('..')));
    });

    test('an override on a blank line admits the app had no number', () {
      final line = ForecastLineView(
        itemId: const ItemId('item'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        confirmedInboundMicros: 0,
        evidenceGrade: EvidenceGrade.insufficientData,
        override: const OverrideView(
          id: 'o1',
          overrideLoadMicros: 12000000,
          reason: 'baseline',
          createdAt: Instant(0),
        ),
      );
      expect(
        sentence(line),
        startsWith(
          'Bring 12. You set that yourself: baseline. Loadout had no number '
          'of its own.',
        ),
      );
    });

    test('a CLEARED override is the engine value again, said plainly', () {
      final line = confirmed(
        history: [day(0, exposure: 100, used: 30)],
        load: 40,
        override: const OverrideView(
          id: 'o2',
          reason: 'back to plan',
          createdAt: Instant(0),
        ),
      );
      expect(sentence(line), startsWith('Bring 40. Last time'));
      expect(sentence(line), isNot(contains('You set that yourself')));
    });
  });

  group('the cold-start collapse', () {
    test('speaks for both engine and baseline warnings, and nothing else', () {
      expect(
        isColdStartWarning(
          'No comparable confirmed outcomes. Create a baseline plan.',
        ),
        isTrue,
      );
      expect(
        isColdStartWarning(
          'Estimate only: worked out from "1 serves 4", not from confirmed '
          'outcomes.',
        ),
        isTrue,
      );
      expect(
        isColdStartWarning('Upcoming exposure is outside the observed range.'),
        isFalse,
      );
      expect(
        isColdStartWarning('History includes approximate closeouts.'),
        isFalse,
      );
    });

    test('a line with confirmed evidence is never a cold start', () {
      expect(
        isColdStartLine(
          confirmed(history: [day(0, exposure: 100, used: 30)], load: 40),
        ),
        isFalse,
      );
    });

    test('a line with no number at all is not called "a guess"', () {
      final blank = ForecastLineView(
        itemId: const ItemId('item'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        confirmedInboundMicros: 0,
        evidenceGrade: EvidenceGrade.insufficientData,
      );
      expect(coldStartNoteFor(blank), 'No past events to learn from yet.');
      expect(coldStartNoteFor(blank), isNot(contains('guess')));

      final guessed = ForecastLineView(
        itemId: const ItemId('item'),
        packSizeMicros: 1000000,
        onHandMicros: 0,
        confirmedInboundMicros: 0,
        baselineServesPerUnitMicros: 4000000,
        baselineExpectedUseMicros: 38000000,
        baselinePlannedMicros: 41800000,
        baselineLoadMicros: 42000000,
        baselineAcquireMicros: 42000000,
        evidenceGrade: EvidenceGrade.insufficientData,
      );
      expect(coldStartNoteFor(guessed), coldStartNote);
    });
  });

  group('shortEventDate', () {
    test('drops the year in the year being read', () {
      expect(shortEventDate('2026-08-07', contextYear: 2026), 'Aug 7');
      expect(shortEventDate('2026-01-31', contextYear: 2026), 'Jan 31');
    });

    test('keeps the year when it would otherwise be ambiguous', () {
      expect(shortEventDate('2025-08-07', contextYear: 2026), 'Aug 7 2025');
    });

    test('a malformed stored date is passed through, never guessed at', () {
      expect(shortEventDate('not a date', contextYear: 2026), 'not a date');
    });
  });
}
