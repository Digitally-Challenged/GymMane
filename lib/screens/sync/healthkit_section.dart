import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../services/integrations/healthkit/healthkit_adapter.dart';
import '../../services/sync/healthkit_delivery.dart';
import '../../services/sync/sync_transport.dart';

/// Permission is an explicit opt-in. Delivery opt-in and history adoption are
/// separate concerns; obtaining permission never initiates a historical upload.
class HealthKitSection extends StatefulWidget {
  const HealthKitSection({super.key, required this.delivery, this.adapter = const HealthKitAdapter()});
  final HealthKitAdapter adapter;
  final HealthKitDelivery delivery;
  @override
  State<HealthKitSection> createState() => _HealthKitSectionState();
}

class _HealthKitSectionState extends State<HealthKitSection> {
  HealthKitAuthorization? _status;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _check();
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
          SwitchListTile(
            title: Text(t.syncUseThisIPhoneForAppleHealthExports),
            subtitle: Text(t.syncChooseOnlyOneDeviceEachWorkoutStill),
            value: delivery.enabled,
            onChanged: delivery.busy ? null : delivery.designate,
          ),
          if (delivery.message != null) Text(delivery.message!),
          if (delivery.enabled) ...[
            Text(t.syncSelectAGymManeOriginWorkoutImportedHistory),
            for (final workout in delivery.workouts)
              ListTile(
                title: Text('${workout['n'] ?? t.syncWorkout}'),
                subtitle: Text('${workout['d']}'),
                trailing: TextButton(
                  onPressed: delivery.busy ? null : () => _export(workout),
                  child: Text(t.syncExport),
                ),
              ),
          ],
          for (final entry in delivery.records.entries)
            ListTile(
              title: Text('${jsonObject(entry.value)['status']} · ${entry.key}'),
              trailing: ['sending', 'unknown'].contains(jsonObject(entry.value)['status'])
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

  Future<void> _remove(String id) async {
    final namespace = widget.delivery.store.namespace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.syncRemoveThisExportFromAppleHealth),
        content: Text(t.syncOnlyThisGymManeExportIsRemovedThe),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncRemove)),
        ],
      ),
    );
    if (confirmed == true && mounted && namespace == widget.delivery.store.namespace) {
      await widget.delivery.remove(id);
    }
  }

  Future<void> _export(SyncJson workout) async {
    final namespace = widget.delivery.store.namespace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.syncExportThisWorkoutToAppleHealth),
        content: Text(t.syncThisSendsOnlyTheSelectedWorkoutFrom),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncExport)),
        ],
      ),
    );
    if (confirmed == true && mounted && namespace == widget.delivery.store.namespace) {
      await widget.delivery.export(workout);
    }
  }
}
