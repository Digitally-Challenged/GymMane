import 'sync_status_label.dart';
import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../services/integrations/healthkit/healthkit_adapter.dart';
import '../../services/sync/healthkit_delivery.dart';
import '../../services/sync/sync_transport.dart';
import '../../services/sync/sync_runtime.dart';
import 'delivery_updates.dart';
import 'workout_delivery_details.dart';

/// Permission is an explicit opt-in. Delivery opt-in and history adoption are
/// separate concerns; obtaining permission never initiates a historical upload.
class HealthKitSection extends StatefulWidget {
  const HealthKitSection({
    super.key,
    required this.delivery,
    this.adapter = const HealthKitAdapter(),
    this.workoutId,
  });
  final HealthKitAdapter adapter;
  final HealthKitDelivery delivery;
  final String? workoutId;
  @override
  State<HealthKitSection> createState() => _HealthKitSectionState();
}

class _HealthKitSectionState extends State<HealthKitSection> with WidgetsBindingObserver {
  late final DeliveryUpdates _updates;
  HealthKitAuthorization? _status;
  String? _error;
  bool _busy = true;
  int _accountGeneration = 0;
  late String _namespace;
  String? _account;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _namespace = widget.delivery.store.namespace;
    _account = SyncRuntime.controller?.account;
    _updates = DeliveryUpdates(_changed, sync: SyncRuntime.controller);
    _check();
  }

  void _changed() {
    if (_namespace != widget.delivery.store.namespace || _account != SyncRuntime.controller?.account) {
      _namespace = widget.delivery.store.namespace;
      _account = SyncRuntime.controller?.account;
      ++_accountGeneration;
      widget.delivery.invalidate();
    }
    widget.delivery.refresh();
  }

  @override
  void dispose() {
    _updates.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _check();
  }

  Future<void> _check({bool request = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final available = await widget.adapter.availability();
      final status = !available
          ? HealthKitAuthorization.unsupported
          : request
          ? await widget.adapter.requestAuthorization()
          : await widget.adapter.authorization();
      await widget.delivery.refresh();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        setState(() => _error = t.syncAppleHealthCouldNotBeReachedCheck);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.syncAppleHealth, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(switch (_status) {
        null => t.syncCheckingAvailability,
        HealthKitAuthorization.unsupported => t.syncUnavailableOnThisDevice,
        HealthKitAuthorization.notDetermined => t.syncWorkoutWritePermissionHasNotBeenRequested,
        HealthKitAuthorization.denied => t.syncWorkoutWritePermissionDeniedChangeAccessIn,
        HealthKitAuthorization.authorized => t.syncWorkoutWritePermissionGranted,
      }),
      if (_error != null) Text(_error!),
      if (widget.workoutId == null || _status == HealthKitAuthorization.notDetermined)
        Text(t.syncOnlyWorkoutWritePermissionIsRequestedThis),
      if (_status == HealthKitAuthorization.notDetermined)
        FilledButton(
          onPressed: _busy ? null : () => _check(request: true),
          child: Text(t.syncAllowAppleHealthAccess),
        ),
      TextButton(onPressed: _busy ? null : _check, child: Text(t.syncRefreshPermissionStatus)),
      if (_status == HealthKitAuthorization.authorized) _deliveryControls(),
    ],
  );
  Widget _deliveryControls() => ListenableBuilder(
    listenable: widget.delivery,
    builder: (context, _) {
      final delivery = widget.delivery;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.workoutId == null || !delivery.enabled)
            SwitchListTile(
              title: Text(t.syncUseThisIPhoneForAppleHealthExports),
              subtitle: Text(t.syncChooseOnlyOneDeviceEachWorkoutStill),
              value: delivery.enabled,
              onChanged: delivery.busy ? null : delivery.designate,
            ),
          if (delivery.message != null) Text(delivery.message!),
          if (delivery.enabled) ...[
            if (widget.workoutId == null) Text(t.syncSelectAGymManeOriginWorkoutImportedHistory),
            for (final workout in delivery.workouts.where(
              (w) => widget.workoutId == null || w['id'] == widget.workoutId,
            ))
              WorkoutDeliveryTile(
                title: workoutName(workout),
                subtitle: workoutDate(context, workout['d']),
                action: TextButton(
                  onPressed: delivery.busy ? null : () => _export(workout),
                  child: Text(t.syncExport),
                ),
              ),
          ],
          for (final entry in delivery.records.entries.where(
            (e) => widget.workoutId == null || e.key == widget.workoutId,
          ))
            WorkoutDeliveryTile(
              title:
                  '${_recordName(entry.key, jsonObject(entry.value))} · ${syncStatusLabel(jsonObject(entry.value)['status'])}',
              subtitle: workoutDate(context, jsonObject(jsonObject(entry.value)['payload'])['endTime']),
              action: ['sending', 'unknown'].contains(jsonObject(entry.value)['status'])
                  ? TextButton(
                      onPressed: delivery.busy || !delivery.enabled
                          ? null
                          : () => delivery.reconcile(entry.key),
                      child: Text(t.syncReconcile),
                    )
                  : jsonObject(entry.value)['status'] == 'confirmed'
                  ? TextButton(
                      onPressed: delivery.busy ? null : () => _remove(entry.key),
                      child: Text(t.syncRemoveFromHealth),
                    )
                  : null,
            ),
        ],
      );
    },
  );

  String _recordName(String id, SyncJson record) {
    for (final workout in widget.delivery.workouts) {
      if (workout['id'] == id) return workoutName(workout);
    }
    return jsonObject(record['payload'])['name'] as String? ?? t.syncWorkout;
  }

  Future<void> _remove(String id) async {
    final namespace = widget.delivery.store.namespace;
    final generation = _accountGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t.syncRemoveThisExportFromAppleHealth),
        content: Text(t.syncOnlyThisGymManeExportIsRemovedThe),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncRemove)),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        namespace == widget.delivery.store.namespace &&
        generation == _accountGeneration) {
      await widget.delivery.remove(id);
    }
  }

  Future<void> _export(SyncJson workout) async {
    final namespace = widget.delivery.store.namespace;
    final generation = _accountGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t.syncExportThisWorkoutToAppleHealth),
        content: Text(
          '${workoutName(workout)}\n${workoutDate(context, workout['d'])}\n\n${t.syncThisSendsOnlyTheSelectedWorkoutFrom}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncExport)),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        namespace == widget.delivery.store.namespace &&
        generation == _accountGeneration &&
        (widget.workoutId == null || widget.workoutId == workout['id'])) {
      await widget.delivery.export(workout);
    }
  }
}
