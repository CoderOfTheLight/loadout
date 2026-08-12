/// Shared events-feature UI helpers: the status chip (icon + text — meaning
/// never color-only, design §9) and `YYYY-MM-DD` calendar-date formatting
/// (design §3: business dates are calendar-day strings).
library;

import 'package:flutter/material.dart';

import '../../../core/time.dart';
import '../domain/event.dart';

String eventStatusLabel(EventStatus status) => switch (status) {
  EventStatus.planned => 'Planned',
  EventStatus.active => 'Active',
  EventStatus.closed => 'Closed',
  EventStatus.cancelled => 'Cancelled',
};

IconData eventStatusIcon(EventStatus status) => switch (status) {
  EventStatus.planned => Icons.event_outlined,
  EventStatus.active => Icons.play_circle_outline,
  EventStatus.closed => Icons.check_circle_outline,
  EventStatus.cancelled => Icons.cancel_outlined,
};

/// Status chip: icon + text so meaning is never color-only (design §9).
class EventStatusChip extends StatelessWidget {
  const EventStatusChip({super.key, required this.status});

  final EventStatus status;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(eventStatusIcon(status), size: 18),
    label: Text(eventStatusLabel(status)),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// Formats a calendar day as the stored `YYYY-MM-DD` TEXT form (design §3).
String formatYmd(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Today in the owner's local calendar, as `YYYY-MM-DD`.
String todayYmd() => formatYmd(DateTime.now());

/// Parses a stored `YYYY-MM-DD` string; null when malformed.
DateTime? parseYmd(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// Renders an [Instant] as the local calendar day it fell on.
String instantYmd(Instant instant) => formatYmd(
  DateTime.fromMicrosecondsSinceEpoch(
    instant.epochMicrosUtc,
    isUtc: true,
  ).toLocal(),
);
