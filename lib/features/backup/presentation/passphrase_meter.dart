/// Advisory passphrase strength meter (design §8.1, §12.20): the hard
/// minimum is 8 characters; the meter *recommends* 12+ but never blocks.
library;

import 'package:flutter/material.dart';

enum PassphraseStrength { tooShort, acceptable, good, strong }

/// Deterministic advisory grading. Length dominates on purpose — long
/// passphrases beat short complex ones against an offline Argon2id attack.
PassphraseStrength gradePassphrase(String passphrase) {
  if (passphrase.length < 8) return PassphraseStrength.tooShort;
  if (passphrase.length < 12) return PassphraseStrength.acceptable;
  var classes = 0;
  for (final pattern in [
    RegExp(r'[a-z]'),
    RegExp(r'[A-Z]'),
    RegExp(r'[0-9]'),
    RegExp(r'[^A-Za-z0-9]'),
  ]) {
    if (pattern.hasMatch(passphrase)) classes++;
  }
  if (passphrase.length >= 16 || classes >= 3) return PassphraseStrength.strong;
  return PassphraseStrength.good;
}

/// Bar + sentence, icon-free but never color-only (the sentence carries the
/// meaning). Purely advisory: the create button is gated on the hard
/// minimum and match, not on this grade.
class PassphraseMeter extends StatelessWidget {
  const PassphraseMeter({super.key, required this.passphrase});

  final String passphrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = gradePassphrase(passphrase);
    final (fraction, label) = switch (strength) {
      PassphraseStrength.tooShort => (
        0.15,
        'Too short — at least 8 characters are required.',
      ),
      PassphraseStrength.acceptable => (
        0.45,
        'Meets the minimum — 12 or more characters is much safer.',
      ),
      PassphraseStrength.good => (0.75, 'Good length.'),
      PassphraseStrength.strong => (1.0, 'Strong passphrase.'),
    };
    final color = switch (strength) {
      PassphraseStrength.tooShort => theme.colorScheme.error,
      PassphraseStrength.acceptable => theme.colorScheme.tertiary,
      PassphraseStrength.good ||
      PassphraseStrength.strong => theme.colorScheme.primary,
    };
    return Semantics(
      label: 'Passphrase strength: $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: passphrase.isEmpty ? 0 : fraction,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Text(
            passphrase.isEmpty ? 'Use 12 or more characters.' : label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
