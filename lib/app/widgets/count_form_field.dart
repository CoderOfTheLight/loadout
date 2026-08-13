/// Shared whole-number entry: "how many things".
///
/// The owner's model of an item is a counted thing — a number of packs,
/// trays, boxes or burgers — so the forms that ask "how many" ask for a
/// plain whole number on a numeric keyboard. Nothing here can express a
/// fraction: the formatter rejects every non-digit as it is typed, and the
/// parsed value becomes exact micros through [Quantity.whole]. `double`
/// never appears, and neither does a unit.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/quantity.dart';

/// Largest count any form accepts. Matches the app's working envelope
/// (design §3: the depletion cap is 1e12 micros = one million whole
/// things), so a number that passes here always survives the ledger.
const int maxCountValue = 1000000;

/// Whole-number form field. Usage:
///
/// ```dart
/// CountFormField(
///   controller: _count,
///   labelText: 'How many do you have?',
///   helperText: 'Leave blank if you have none yet.',
/// )
/// ```
///
/// Empty is legal unless [isRequired]; the value is otherwise validated to
/// [minValue]..[maxValue]. Pass [validator] to add checks on top.
class CountFormField extends StatelessWidget {
  const CountFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.labelText,
    this.helperText,
    this.hintText,
    this.enabled = true,
    this.isRequired = false,
    this.requiredMessage = 'Enter a number',
    this.minValue = 0,
    this.maxValue = maxCountValue,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.validator,
  }) : assert(
         controller == null || initialValue == null,
         'pass a controller or an initialValue, not both',
       );

  final TextEditingController? controller;
  final String? initialValue;
  final String? labelText;
  final String? helperText;
  final String? hintText;
  final bool enabled;
  final bool isRequired;
  final String requiredMessage;
  final int minValue;
  final int maxValue;
  final bool autofocus;
  final TextInputAction? textInputAction;

  /// Fires with the parsed count, or null while the field is empty.
  final ValueChanged<int?>? onChanged;

  /// Extra validation over the parsed count; return a message or null.
  final String? Function(int value)? validator;

  /// Parses digits to a count. Null for empty, blank or out-of-range text.
  static int? tryParseCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value < 0 || value > maxCountValue) return null;
    return value;
  }

  /// Parses digits to exact micros ([Quantity.whole]); null when [text] is
  /// not a usable count.
  static Quantity? tryParseQuantity(String text) {
    final count = tryParseCount(text);
    return count == null ? null : Quantity.whole(count);
  }

  /// The number as this field would show it: whole, no unit, no separators.
  static String format(int count) => '$count';

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    initialValue: controller == null ? initialValue : null,
    enabled: enabled,
    autofocus: autofocus,
    textInputAction: textInputAction,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      // Seven digits is one more than [maxCountValue] needs, so the
      // validator — not the keyboard — explains the limit.
      LengthLimitingTextInputFormatter(7),
    ],
    decoration: InputDecoration(
      labelText: labelText,
      helperText: helperText,
      hintText: hintText,
      helperMaxLines: 3,
      errorMaxLines: 2,
      border: const OutlineInputBorder(),
    ),
    onChanged: onChanged == null
        ? null
        : (text) => onChanged!(tryParseCount(text)),
    validator: (text) {
      final trimmed = (text ?? '').trim();
      if (trimmed.isEmpty) {
        return isRequired ? requiredMessage : null;
      }
      final value = int.tryParse(trimmed);
      if (value == null || value < minValue || value > maxValue) {
        return 'Enter a whole number from $minValue to '
            '${_grouped(maxValue)}';
      }
      return validator?.call(value);
    },
  );

  /// `1000000` → `1,000,000`, so the limit reads like a number a person
  /// would say out loud.
  static String _grouped(int value) {
    final digits = '$value';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
