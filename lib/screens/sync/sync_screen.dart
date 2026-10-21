import '../../l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/sync/sync_controller.dart';
import '../../services/sync/sync_transport.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.controller, this.healthSection, this.stravaSection});
  final SyncController controller;
  final Widget? healthSection;
  final Widget? stravaSection;
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t.syncConnectionsSync)),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final sync = widget.controller;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(t.syncCloudSync, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(t.syncSyncCompletedWorkoutsAndRoutinesOfflineGuest),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_status(sync))),
            if (sync.message != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(sync.message!)),
            if (sync.busy) const LinearProgressIndicator(),
            if (sync.account == null && sync.phase != SyncPhase.unavailable) ...[
              TextField(
                controller: _email,
                enabled: !sync.busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: t.syncEmail),
              ),
              TextField(
                controller: _password,
                enabled: !sync.busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: t.syncPassword),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: sync.busy
                    ? null
                    : () async {
                        final password = _password.text;
                        _password.clear();
                        await sync.signIn(_email.text, password);
                      },
                child: Text(t.syncSignIn),
              ),
              Text(t.syncUseAnExistingAccountFromYourConfigured),
              if (kIsWeb) Text(t.syncWebSignInLastsForThisTab),
            ],
            if (sync.account != null) ...[
              const SizedBox(height: 12),
              Text('Account: ${sync.account}'),
              Text('${sync.pendingCount} pending changes · ${sync.conflicts.length} conflicts'),
              if (sync.lastSynced != null) Text('Last completed sync: ${sync.lastSynced!.toLocal()}'),
              FilledButton(onPressed: sync.busy ? null : sync.sync, child: Text(t.syncSyncNow)),
              OutlinedButton(
                onPressed: sync.busy ? null : _adoptGuest,
                child: Text(t.syncReviewGuestHistoryForUpload),
              ),
              TextButton(onPressed: sync.busy ? null : sync.signOut, child: Text(t.syncSignOutOnThisDevice)),
              Text(t.syncSigningOutRetainsLocalAccountDataAnd),
              for (final conflict in sync.conflicts) _conflict(sync, conflict),
            ],
            if (widget.stravaSection != null) ...[const Divider(height: 40), widget.stravaSection!],
            if (widget.healthSection != null) ...[const Divider(height: 40), widget.healthSection!],
          ],
        );
      },
    ),
  );

  String _status(SyncController sync) => switch (sync.phase) {
    SyncPhase.unavailable => t.syncUnavailable,
    SyncPhase.signedOut => t.syncGuestCloudSyncOff,
    SyncPhase.ready => sync.conflicts.isEmpty ? t.syncConnected : t.syncConnectedConflictsNeedReview,
    SyncPhase.syncing => t.syncSyncing,
    SyncPhase.offline => t.syncOfflineChangesWaiting,
    SyncPhase.needsAuthorization => t.syncSessionExpiredSignOutAndSignIn,
    SyncPhase.error => t.syncSyncNeedsAttention,
  };

  Future<void> _adoptGuest() async {
    final account = widget.controller.account;
    try {
      final preview = await widget.controller.guestPreview();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.syncUploadGuestHistory),
          content: Text(
            '${preview.entries.map((entry) => '${entry.value} ${entry.key}').join('\n')}\n\nThese records will be added to the signed-in account and uploaded. Existing remote edits are retained as conflicts for review.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncConfirmUpload)),
          ],
        ),
      );
      if (confirmed == true && mounted && account == widget.controller.account) {
        await widget.controller.adoptGuest();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.syncCouldNotReadGuestHistoryNothingWas)));
      }
    }
  }

  Widget _conflict(SyncController sync, SyncJson conflict) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conflict: ${conflict['entityType'] ?? 'record'} ${conflict['entityId'] ?? ''}'),
          Text('This device: ${_version(conflict['local'])}'),
          Text('Server: ${_version(conflict)}'),
          Text(t.syncBothVersionsAreRetainedUntilYouChoose),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: sync.busy ? null : () => _resolve(conflict, true),
                child: Text(t.syncKeepThisDevice),
              ),
              TextButton(
                onPressed: sync.busy ? null : () => _resolve(conflict, false),
                child: Text(t.syncUseServerVersion),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _version(Object? value) {
    if (value is! Map<String, dynamic>) return t.syncLocalVersionRetained;
    if (value['deleted'] == true) return t.syncDeleted;
    final payload = value['payload'];
    if (payload is! Map<String, dynamic>) return t.syncNoDetailsAvailable;
    return [
      payload['n'] ?? payload['name'] ?? t.syncUntitled,
      if (payload['d'] != null) payload['d'],
      if (payload['dur'] != null) '${payload['dur']} seconds',
      if (payload['ex'] is List) '${(payload['ex'] as List).length} exercises',
    ].join(' · ');
  }

  Future<void> _resolve(SyncJson conflict, bool keepLocal) async {
    final account = widget.controller.account;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepLocal ? t.syncKeepThisDeviceSVersion : t.syncUseServerVersionQuestion),
        content: Text(
          keepLocal
              ? t.syncThisWillSubmitYourLocalVersionAgainst
              : t.syncThisReplacesTheConflictingLocalVersionWith,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.syncCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.syncConfirm)),
        ],
      ),
    );
    if (confirmed == true && mounted && account == widget.controller.account) {
      await widget.controller.resolve(conflict, keepLocal: keepLocal);
    }
  }
}
