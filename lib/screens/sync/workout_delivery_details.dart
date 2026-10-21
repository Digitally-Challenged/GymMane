import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../services/sync/sync_transport.dart';

String workoutName(SyncJson payload) => (payload['n'] ?? payload['name']) as String? ?? t.syncWorkout;

String workoutDate(BuildContext context, Object? value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  if (date == null) return '';
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${t.shortDateYear(date)} · $time';
}

/// Keep actions below their descriptions so large text has the full width.
class WorkoutDeliveryTile extends StatelessWidget {
  const WorkoutDeliveryTile({super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
        if (action != null) Align(alignment: Alignment.centerLeft, child: action),
      ],
    ),
  );
}
