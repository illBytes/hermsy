import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// True when [a] and [b] fall on the same local calendar day.
bool isSameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// 'TODAY', 'YESTERDAY', 'THU 10 SEP', or 'THU 10 SEP 2025' for another year.
String dayLabel(DateTime date, {DateTime? now}) {
  final day = date.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (isSameDay(day, today)) {
    return 'TODAY';
  }
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (isSameDay(day, yesterday)) {
    return 'YESTERDAY';
  }
  final label =
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return day.year == today.year ? label : '$label ${day.year}';
}

/// A quiet day marker in the thread: a micro label between two hairlines
/// that fade out toward the screen edges.
class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.date, this.now});

  final DateTime date;

  /// Overrides the clock (tests).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.reading,
        vertical: AppSpace.x6,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            const Expanded(child: _FadingRule(toEnd: true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
              child: Text(dayLabel(date, now: now), style: AppText.micro),
            ),
            const Expanded(child: _FadingRule(toEnd: false)),
          ],
        ),
      ),
    );
  }
}

class _FadingRule extends StatelessWidget {
  const _FadingRule({required this.toEnd});

  /// Brightens toward the end (the label) when true.
  final bool toEnd;

  @override
  Widget build(BuildContext context) {
    final faded = AppColors.hairline.withValues(alpha: 0);
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: toEnd
                ? [faded, AppColors.hairline]
                : [AppColors.hairline, faded],
          ),
        ),
      ),
    );
  }
}
