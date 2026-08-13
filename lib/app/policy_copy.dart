/// One place for the words that describe a [PlanningPolicy].
///
/// The policy is chosen twice — once during first run and once in Settings —
/// and the two used to disagree: onboarding showed "Balanced\n+10 % reserve"
/// while Settings showed "Balanced (+10 % reserve)". Both now read from
/// here, and both can offer the plain-English [policyBlurb] that says what
/// the percentage actually means for someone packing a van.
library;

import '../features/forecasting/domain/forecast_engine.dart';

/// "Balanced" — the bare name.
String policyName(PlanningPolicy policy) => switch (policy) {
  PlanningPolicy.lean => 'Lean',
  PlanningPolicy.balanced => 'Balanced',
  PlanningPolicy.cautious => 'Cautious',
};

/// "Balanced (+10 % reserve)" — shared caption shape.
String policyCaption(PlanningPolicy policy) =>
    '${policyName(policy)} (+${policy.reservePercent} % reserve)';

/// What the reserve means, in the owner's terms.
String policyBlurb(PlanningPolicy policy) => switch (policy) {
  PlanningPolicy.lean => 'Take about what you expect to sell.',
  PlanningPolicy.balanced => 'Take a little spare in case it gets busy.',
  PlanningPolicy.cautious => 'Take plenty spare — running out is the worst.',
};
