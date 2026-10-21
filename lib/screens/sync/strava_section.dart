import 'dart:async';
import 'sync_status_label.dart';
import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/sync/sync_controller.dart';
import '../../services/sync/sync_transport.dart';
import 'delivery_updates.dart';
import 'workout_delivery_details.dart';

class StravaSection extends StatefulWidget {
  const StravaSection({super.key, required this.sync, required this.workouts, this.workoutId});
  final SyncController sync;
  final Future<List<SyncJson>> Function() workouts;
  final String? workoutId;
  @override
  State<StravaSection> createState() => _StravaSectionState();
}

class _StravaSectionState extends State<StravaSection> with WidgetsBindingObserver {
  SyncJson? _status;
  List<SyncJson> _workouts = [];
  String? _message;
  String? _account;
  bool _busy = false;
  int _generation = 0;
  bool _refreshAfterBusy = false;
  bool _revocationUnconfirmed = false;
  late final DeliveryUpdates _updates;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sync.addListener(_accountChanged);
    _account = widget.sync.account;
    _updates = DeliveryUpdates(_refresh, sync: widget.sync);
    _refresh();
  }

  @override
  void dispose() {
    _updates.dispose();
    widget.sync.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _accountChanged() {
    if (_account == widget.sync.account) return;
    _account = widget.sync.account;
    ++_generation;
    _revocationUnconfirmed = false;
    setState(() {
      _status = null;
      _workouts = [];
      _message = null;
    });
    if (_busy) {
      _refreshAfterBusy = true;
    } else {
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<SyncJson> _request(String method, String path, {SyncJson? body}) async {
    final generation = _generation;
    final account = widget.sync.account;
    if (account == null) throw SyncFailure(t.syncSignInToConnectStrava);
    final token = await widget.sync.auth.accessToken();
    if (account != widget.sync.account || generation != _generation) {
      throw SyncFailure(t.syncAccountChangedRefreshConnections);
    }
    final result = await widget.sync.transport.request(method, path, token, body: body);
    if (account != widget.sync.account || generation != _generation) {
      throw SyncFailure(t.syncAccountChangedRefreshConnections);
    }
    return result;
  }

  Future<void> _refresh() {
    if (_busy) {
      _refreshAfterBusy = true;
      return Future.value();
    }
    return _run(() async {
      if (widget.sync.account == null) return;
      final generation = _generation;
      final status = await _request('GET', '/v1/strava/status');
      if (status['configured'] is! bool || status['connected'] is! bool) {
        throw const FormatException('Invalid Strava status');
      }
      for (final job in jsonList(status['jobs'])) {
        if (job['workoutId'] is! String || job['status'] is! String) {
          throw const FormatException('Invalid Strava job');
        }
      }
      final workouts = await widget.workouts();
      if (generation != _generation) return;
      if (mounted) {
        setState(() {
          _status = status;
          _workouts = workouts;
        });
      }
    });
  }

  Future<void> _connect() => _run(() async {
    final result = await _request('POST', '/v1/strava/connect', body: {});
    final uri = Uri.parse(result['authorizationUrl'] as String);
    if (uri.scheme != 'https' ||
        !['strava.com', 'www.strava.com'].contains(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid authorization URL');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw SyncFailure(t.syncCouldNotOpenStravaAuthorization);
    }
  });
  Future<void> _export(SyncJson workout, {bool retry = false}) async {
    final account = widget.sync.account;
    final generation = _generation;
    final payload = jsonObject(workout['payload']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(retry ? '${t.syncStrava} · ${t.syncRetry}' : t.syncExportThisWorkoutToStrava),
        content: Text(
          '${workoutName(payload)}\n${workoutDate(context, payload['d'])}\n\n${t.syncOnlyThisCompletedWorkoutWillBeSent}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(retry ? t.syncRetry : t.syncExport),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        account != widget.sync.account ||
        generation != _generation ||
        (widget.workoutId != null && widget.workoutId != workout['entityId'])) {
      return;
    }
    await _run(() async {
      await _request(
        'POST',
        retry ? '/v1/strava/retry' : '/v1/strava/export',
        body: {'workoutId': workout['entityId'], 'revision': workout['revision']},
      );
    });
    await _refresh();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on SyncFailure catch (error) {
      if (mounted && generation == _generation) setState(() => _message = error.message);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = t.syncStravaCouldNotCompleteThisRequestRefresh);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshAfterBusy) {
          _refreshAfterBusy = false;
          unawaited(_refresh());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _status?['jobs'] is List ? jsonList(_status!['jobs']) : <SyncJson>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.syncStrava, style: Theme.of(context).textTheme.headlineSmall),
        if (widget.sync.account == null)
          Text(t.syncSignInToConnectStrava)
        else ...[
          Text(
            _status == null
                ? t.syncStatusNotLoaded
                : _status!['configured'] != true
                ? t.syncUnavailableServerStravaConfigurationIsIncomplete
                : _status!['connected'] == true
                ? t.syncConnected
                : t.syncNotConnected,
          ),
          if (_message != null) Text(_message!),
          if (_revocationUnconfirmed) Text(t.syncDisconnectedLocallyButStravaRevocationIsUnconfirmed),
          if (_status?['configured'] == true && _status?['connected'] != true)
            FilledButton(onPressed: _busy ? null : _connect, child: Text(t.syncConnectStrava)),
          TextButton(onPressed: _busy ? null : _refresh, child: Text(t.syncRefreshStravaStatus)),
          if (_status?['connected'] == true) ...[
            if (widget.workoutId == null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _run(() async {
                          final result = await _request('POST', '/v1/strava/disconnect', body: {});
                          _revocationUnconfirmed = result['revocationStatus'] == 'unconfirmed';
                        });
                        await _refresh();
                      },
                child: Text(t.syncDisconnectStrava),
              ),
            if (widget.workoutId == null) Text(t.syncChooseASyncedGymManeWorkoutToExport),
            if (widget.workoutId != null && !_workouts.any((w) => w['entityId'] == widget.workoutId))
              Text(t.syncWaitingForCloudSync),
            for (final workout in _workouts.where(
              (w) => widget.workoutId == null || w['entityId'] == widget.workoutId,
            ))
              WorkoutDeliveryTile(
                title: workoutName(jsonObject(workout['payload'])),
                subtitle: workoutDate(context, jsonObject(workout['payload'])['d']),
                action: TextButton(
                  onPressed: _busy || jobs.any((job) => job['workoutId'] == workout['entityId'])
                      ? null
                      : () => _export(workout),
                  child: Text(t.syncExport),
                ),
              ),
          ],
          for (final job in jobs.where((j) => widget.workoutId == null || j['workoutId'] == widget.workoutId))
            WorkoutDeliveryTile(
              title: '${job['name'] ?? t.syncWorkout} · ${syncStatusLabel(job['status'])}',
              subtitle: [
                for (final workout in _workouts.where((w) => w['entityId'] == job['workoutId']))
                  workoutDate(context, jsonObject(workout['payload'])['d']),
                job['status'] == 'unknown'
                    ? t.syncCheckStravaManuallyDoNotRetryThis
                    : job['status'] == 'unsupported'
                    ? t.syncEditOrDeleteThisActivityManuallyIn
                    : '${job['message'] ?? t.syncRefreshToCheckDeliveryStatus}',
              ].join('\n'),
              action: job['canRetry'] == true && job['revision'] is int
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () => _export({
                              'entityId': job['workoutId'],
                              'revision': job['revision'],
                              'payload': {'n': job['name'] ?? t.syncWorkout},
                            }, retry: true),
                      child: Text(t.syncRetry),
                    )
                  : null,
            ),
        ],
      ],
    );
  }
}
