/// Shared quantity entry (design §9.1): decimal-string entry over
/// [QuantityCodec] — `.` and `,` both accepted, at most 6 fraction digits,
/// invalid keystrokes rejected as they are typed. `double` never appears.
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
final class QuantityInputFormatter extends TextInputFormatter {
  QuantityInputFormatter();

  static final RegExp _allowed = RegExp(
    '^[0-9]*(?:[.,][0-9]{0,${QuantityCodec.maxFractionDigits}})?\$',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _allowed.hasMatch(newValue.text) ? newValue : oldValue;
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
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [QuantityInputFormatter()],
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
