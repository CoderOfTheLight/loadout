/// Shared money entry: "what does one cost".
///
/// Dollars-and-cents entry over [MoneyCodec] — an optional leading `$`,
/// comma thousands, at most two fraction digits, invalid keystrokes
/// rejected as they are typed. Exact integer cents all the way through;
/// `double` never appears (v7 price design).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/money_codec.dart';

/// Largest unit price any form accepts, in cents ($1,000,000) — mirroring
/// the command validator (`maxUnitPriceCents`) and the schema CHECK
/// (`unitPriceCapCents`), so a price that passes here always saves.
const int maxPriceCents = 100000000;

/// Reject-at-keystroke formatter: digits, comma thousands, at most one `.`
/// followed by at most two digits, and an optional leading `$` (prefills
/// carry [MoneyCodec.format]'s `$`; edits must keep being legal around it).
/// Intermediate states ("12.") are allowed while typing; [MoneyCodec.parse]
/// is the final word at validation time.
final class MoneyInputFormatter extends TextInputFormatter {
  static final RegExp _allowed = RegExp(r'^\$?[0-9,]*(?:\.[0-9]{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _allowed.hasMatch(newValue.text) ? newValue : oldValue;
}

/// The shared money form field (v7 price design). Usage:
///
/// ```dart
/// MoneyFormField(
///   controller: _price,               // prefill with MoneyCodec.format
///   labelText: 'Price each (optional)',
/// )
/// ```
///
/// Always optional: empty is legal and means "no price" (on a whole-state
/// form save that CLEARS a stored price — the caller's helper text should
/// own that grammar). Unparseable text, a zero, and an amount over
/// [maxPriceCents] are rejected in plain words.
class MoneyFormField extends StatelessWidget {
  const MoneyFormField({
    super.key,
    this.controller,
    this.labelText,
    this.helperText,
    this.hintText,
    this.enabled = true,
    this.textInputAction,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? helperText;
  final String? hintText;
  final bool enabled;
  final TextInputAction? textInputAction;

  /// Fires with the parsed [Money], or null while the text is empty or not
  /// yet parseable (e.g. "12.").
  final ValueChanged<Money?>? onChanged;

  /// Parses [text] leniently for callers: null for empty or malformed.
  static Money? tryParse(String text) => MoneyCodec.tryParse(text.trim());

  /// Prefill text for the field: [MoneyCodec.format]'s render minus its
  /// leading `$`, because the field already paints one as `prefixText`
  /// ('$2.50' would otherwise show as '$$2.50'). Never hand-rolled digits.
  static String formatFieldText(Money value) =>
      MoneyCodec.format(value).substring(1);

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    textInputAction: textInputAction,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [MoneyInputFormatter()],
    decoration: InputDecoration(
      labelText: labelText,
      helperText: helperText,
      helperMaxLines: 3,
      hintText: hintText,
      prefixText: r'$',
      border: const OutlineInputBorder(),
    ),
    onChanged: onChanged == null ? null : (text) => onChanged!(tryParse(text)),
    validator: (text) {
      final trimmed = (text ?? '').trim();
      if (trimmed.isEmpty) {
        return null; // optional: empty = no price
      }
      final value = tryParse(trimmed);
      if (value == null || value.cents < 1) {
        return 'Enter a price like 12.50';
      }
      if (value.cents > maxPriceCents) {
        return r'Keep it under $1,000,000';
      }
      return null;
    },
  );
}
