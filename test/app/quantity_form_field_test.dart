/// §9.1 quantity entry: keystroke-level rejection over [QuantityCodec] —
/// `.` and `,` both accepted, at most 6 fraction digits, `double` never
/// involved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/widgets/quantity_form_field.dart';
import 'package:loadout/core/quantity.dart';

TextEditingValue _v(String text) => TextEditingValue(text: text);

void main() {
  group('QuantityInputFormatter', () {
    final formatter = QuantityInputFormatter();

    String apply(String oldText, String newText) =>
        formatter.formatEditUpdate(_v(oldText), _v(newText)).text;

    test('accepts digits and one separator, either . or ,', () {
      expect(apply('', '1'), '1');
      expect(apply('1', '1.'), '1.', reason: 'intermediate state while typing');
      expect(apply('1.', '1.5'), '1.5');
      expect(apply('1', '1,'), '1,');
      expect(apply('1,', '1,5'), '1,5');
      expect(apply('', '.'), '.');
    });

    test('rejects a second separator at the keystroke', () {
      expect(apply('1.5', '1.5.'), '1.5');
      expect(apply('1,5', '1,5,'), '1,5');
      expect(apply('1.5', '1.5,'), '1.5');
    });

    test('rejects a seventh fraction digit at the keystroke', () {
      expect(apply('0.123456', '0.1234567'), '0.123456');
    });

    test('rejects non-digit characters at the keystroke', () {
      expect(apply('12', '12a'), '12');
      expect(apply('', '-'), '');
      expect(apply('1', '1e'), '1');
      expect(apply('', ' '), '');
    });

    test('rejects fraction characters unless fractions were asked for', () {
      expect(apply('1', '1/'), '1');
      expect(apply('1', '1 '), '1');
    });
  });

  group('QuantityInputFormatter(allowFractions: true)', () {
    final formatter = QuantityInputFormatter(allowFractions: true);

    String apply(String oldText, String newText) =>
        formatter.formatEditUpdate(_v(oldText), _v(newText)).text;

    test('accepts simple and mixed fractions with typing intermediates', () {
      expect(apply('1', '1/'), '1/');
      expect(apply('1/', '1/2'), '1/2');
      expect(apply('1', '1 '), '1 ');
      expect(apply('1 ', '1 1'), '1 1');
      expect(apply('1 1', '1 1/'), '1 1/');
      expect(apply('1 1/', '1 1/2'), '1 1/2');
    });

    test('decimals keep working exactly as before', () {
      expect(apply('1', '1.'), '1.');
      expect(apply('1.', '1.5'), '1.5');
      expect(apply('0.123456', '0.1234567'), '0.123456');
    });

    test('still rejects malformed input at the keystroke', () {
      expect(apply('', ' '), ''); // no leading space
      expect(apply('1/2', '1/2/'), '1/2'); // one slash only
      expect(apply('1.5', '1.5/'), '1.5'); // no slash after a decimal
      expect(apply('1 1', '1 1 '), '1 1'); // one space only
      expect(apply('12', '12a'), '12');
    });
  });

  group('QuantityFormField', () {
    Future<GlobalKey<FormState>> pump(
      WidgetTester tester, {
      void Function(Quantity?)? onChanged,
    }) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: QuantityFormField(
                labelText: 'Quantity',
                unitLabel: 'kg',
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      );
      return formKey;
    }

    testWidgets('parses to exact micros with either separator', (tester) async {
      Quantity? parsed;
      final formKey = await pump(tester, onChanged: (q) => parsed = q);

      await tester.enterText(find.byType(TextFormField), '1.5');
      expect(parsed?.micros, 1500000);
      await tester.enterText(find.byType(TextFormField), '1,25');
      expect(parsed?.micros, 1250000);
      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('blocks invalid text at entry, not just validation', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField), '1.2.3');
      expect(find.text('1.2.3'), findsNothing);
    });

    testWidgets('rejects empty, incomplete, and zero values on validate', (
      tester,
    ) async {
      final formKey = await pump(tester);

      expect(formKey.currentState!.validate(), isFalse); // required
      await tester.pump();
      expect(find.text('Enter a quantity'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '1.');
      expect(formKey.currentState!.validate(), isFalse); // incomplete
      await tester.pump();
      expect(find.text('Enter a valid quantity'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '0');
      expect(formKey.currentState!.validate(), isFalse); // zero
      await tester.pump();
      expect(find.text('Must be more than zero'), findsOneWidget);
    });
  });
}
