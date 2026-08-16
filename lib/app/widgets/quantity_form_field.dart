/// Shared quantity entry (design §9.1): decimal-string entry over
/// [QuantityCodec] — `.` and `,` both accepted, at most 6 fraction digits,
/// invalid keystrokes rejected as they are typed — and, where a field opts
/// in via `allowFractions` (v5 amount ruling), simple fractions ("1/2") and
/// mixed numbers ("1 1/2") too. `double` never appears; fraction math is
/// exact integer math in the codec (1/3 → 333333 micros).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/quantity.dart';
import '../../core/quantity_codec.dart';

/// Reject-at-keystroke formatter: the field can only ever contain digits and
/// at most one `.` or `,` followed by at most
/// [QuantityCodec.maxFractionDigits] digits. Intermediate states ("1.",
/// ".") are allowed while typing; [QuantityCodec.parse] is the final word
/// at validation time.
///
/// With [allowFractions] (v5 amount ruling) the simple-fraction forms
/// [QuantityCodec.parse] reads — "1/2" and "1 1/2" — are additionally let
/// through, including their intermediate states ("1 ", "1 1/"). Decimals
/// keep working exactly as before; a field that never asked for fractions
/// behaves byte-for-byte as it always did.
final class QuantityInputFormatter extends TextInputFormatter {
  QuantityInputFormatter({this.allowFractions = false});

  final bool allowFractions;

  static final RegExp _allowed = RegExp(
    '^[0-9]*(?:[.,][0-9]{0,${QuantityCodec.maxFractionDigits}})?\$',
  );

  /// Decimal form, or `n/d` / `w n/d` (with typing intermediates).
  static final RegExp _allowedWithFractions = RegExp(
    '^(?:[0-9]*(?:[.,][0-9]{0,${QuantityCodec.maxFractionDigits}})?'
    '|[0-9]+(?: [0-9]*(?:/[0-9]*)?|/[0-9]*))\$',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final allowed = allowFractions ? _allowedWithFractions : _allowed;
    return allowed.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// The shared quantity form field (design §9.1). Usage:
///
/// ```dart
/// QuantityFormField(
///   controller: _controller,          // or initialValue:
///   labelText: 'Pack size',
///   unitLabel: 'kg',                  // Semantics: 'Quantity in kg'
///   onChanged: (q) => ...,            // null while unparseable
/// )
/// ```
///
/// Validation: empty → [requiredMessage] when [isRequired]; unparseable →
/// content-free message; zero rejected unless [allowZero]. Pass [validator]
/// to add checks on top (runs only after the built-ins pass).
class QuantityFormField extends StatelessWidget {
  const QuantityFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.labelText,
    this.helperText,
    this.unitLabel,
    this.enabled = true,
    this.isRequired = true,
    this.allowZero = false,
    this.allowFractions = false,
    this.requiredMessage = 'Enter a quantity',
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.validator,
  }) : assert(
         controller == null || initialValue == null,
         'pass a controller or an initialValue, not both',
       );

  final TextEditingController? controller;
  final Quantity? initialValue;
  final String? labelText;
  final String? helperText;

  /// Unit for the semantic label ('Quantity in kg', §9 MovementEntryScreen).
  final String? unitLabel;
  final bool enabled;
  final bool isRequired;
  final bool allowZero;

  /// v5 amount ruling: also accept simple fractions ("1/2") and mixed
  /// numbers ("1 1/2"), exactly as [QuantityCodec.parse] reads them. The
  /// keyboard switches to text so `/` and space are typeable.
  final bool allowFractions;
  final String requiredMessage;
  final bool autofocus;
  final TextInputAction? textInputAction;

  /// Fires with the parsed [Quantity], or null while the text is empty or
  /// not yet parseable (e.g. "1.").
  final ValueChanged<Quantity?>? onChanged;

  /// Extra validation over the parsed value; return an error message or null.
  final String? Function(Quantity value)? validator;

  /// Parses [text] leniently for callers (returns null instead of throwing).
  static Quantity? tryParse(String text) {
    try {
      return QuantityCodec.parse(text);
    } on Exception {
      return null;
    } on Error {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      initialValue: controller == null && initialValue != null
          ? QuantityCodec.format(initialValue!)
          : null,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: textInputAction,
      keyboardType: allowFractions
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      autocorrect: !allowFractions,
      inputFormatters: [QuantityInputFormatter(allowFractions: allowFractions)],
      decoration: InputDecoration(
        labelText: labelText,
        helperText: helperText,
        suffixText: unitLabel,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged == null
          ? null
          : (text) => onChanged!(tryParse(text)),
      validator: (text) {
        final trimmed = (text ?? '').trim();
        if (trimmed.isEmpty) {
          return isRequired ? requiredMessage : null;
        }
        final value = tryParse(trimmed);
        if (value == null) {
          return 'Enter a valid quantity';
        }
        if (!allowZero && value.micros == 0) {
          return 'Must be more than zero';
        }
        return validator?.call(value);
      },
    );
    final unit = unitLabel;
    if (unit == null) {
      return field;
    }
    return Semantics(label: 'Quantity in $unit', child: field);
  }
}
