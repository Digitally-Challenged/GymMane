import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../services/local_store.dart';
import '../../services/sync/store_health_delivery.dart';
import '../../services/sync/sync_controller.dart';
import '../../services/sync/sync_runtime.dart';
import '../../services/sync/sync_transport.dart';
import 'delivery_updates.dart';
import 'healthkit_section.dart';
import 'strava_section.dart';
import 'workout_delivery_details.dart';

class CompletedWorkoutDelivery extends StatefulWidget {
  const CompletedWorkoutDelivery({super.key, required this.workoutId});
  final String workoutId;

  @override
  State<CompletedWorkoutDelivery> createState() => _CompletedWorkoutDeliveryState();
}

class _CompletedWorkoutDeliveryState extends State<CompletedWorkoutDelivery> {
  DeliveryUpdates? _updates;
  String? _namespace;
  SyncJson? _workout;
  SyncController? _sync;
  bool _eligible = false;
  bool _synced = false;
  bool _conflicted = false;

  @override
  void initState() {
    super.initState();
    try {
      _namespace = Store.instance.repository.namespace;
      _sync = SyncRuntime.controller;
      _sync?.addListener(_refresh);
      _updates = DeliveryUpdates(_refresh, localProjection: _selectedSource);
      _refresh();
    } catch (_) {
      // Session previews have no durable store or native runtime.
    }
  }

  Object? _selectedSource() {
    final repository = Store.instance.repository;
    if (repository.namespace != _namespace) return null;
    return [
      repository.entityMetadata(_namespace!, 'workout', widget.workoutId),
      repository.conflicts(_namespace!)['workout:${widget.workoutId}'],
      repository.exportableWorkouts(_namespace!).where((e) => e['entityId'] == widget.workoutId).toList(),
    ];
  }

  void _refresh() {
    final repository = Store.instance.repository;
    final current = repository.namespace == _namespace;
    final source = current ? repository.entityMetadata(_namespace!, 'workout', widget.workoutId) : null;
    final matches = current
        ? repository.exportableWorkouts(_namespace!).where((e) => e['entityId'] == widget.workoutId)
        : <SyncJson>[];
    final candidate = matches.isEmpty ? null : matches.first;
    setState(() {
      _workout = source?['deleted'] == true ? null : source;
      _eligible = candidate != null;
      _synced = (candidate?['revision'] as int? ?? 0) > 0 && candidate?['pending'] == false;
      _conflicted = current && repository.conflicts(_namespace!).containsKey('workout:${widget.workoutId}');
    });
  }

  @override
  void didUpdateWidget(CompletedWorkoutDelivery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workoutId != widget.workoutId && _namespace != null) _refresh();
  }

  @override
  void dispose() {
    _updates?.dispose();
    _sync?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entity = _workout;
    if (entity == null) return const SizedBox.shrink();
    final sync = _sync;
    final health = SyncRuntime.health;
    final payload = jsonObject(entity['payload']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(workoutName(payload), style: Theme.of(context).textTheme.titleLarge),
            Text(workoutDate(context, payload['d'])),
            Text(t.syncSavedOnThisDevice),
            Text('${t.syncCloudSync}: ${_cloudStatus()}'),
            if (sync?.account != null && !_synced)
              TextButton(onPressed: sync!.busy ? null : sync.requestSync, child: Text(t.syncSyncNow)),
            if (!_eligible) Text(t.syncWorkoutChangedOrIsNotEligibleRefresh),
            if (_eligible && health != null) ...[
              const Divider(height: 32),
              HealthKitSection(
                key: ValueKey('health-${widget.workoutId}'),
                delivery: health,
                adapter: health.adapter,
                workoutId: widget.workoutId,
              ),
            ],
            if (_eligible && sync != null) ...[
              const Divider(height: 32),
              StravaSection(
                key: ValueKey('strava-${widget.workoutId}'),
                sync: sync,
                workouts: () => exportableWorkouts(Store.instance, syncedOnly: true),
                workoutId: widget.workoutId,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cloudStatus() {
    if (_sync?.account == null) return t.syncGuestCloudSyncOff;
    if (_conflicted) return t.syncConnectedConflictsNeedReview;
    if (_synced) return t.syncSynced;
    return switch (_sync!.phase) {
      SyncPhase.unavailable => t.syncUnavailable,
      SyncPhase.syncing => t.syncSyncing,
      SyncPhase.offline => t.syncOfflineChangesWaiting,
      SyncPhase.error => t.syncSyncNeedsAttention,
      SyncPhase.needsAuthorization => t.syncSessionExpiredSignOutAndSignIn,
      _ => t.syncWaitingForCloudSync,
    };
  }
}
