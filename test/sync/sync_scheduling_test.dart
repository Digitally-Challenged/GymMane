import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'package:gymmane/services/sync/sync_config.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/services/sync/sync_transport.dart';

import 'sync_controller_test.dart' show TestAuth, TestRepository, accountId, configuration;

SyncJson operation() => {
  'operationId': accountId,
  'entityType': 'workout',
  'entityId': accountId,
  'deleted': true,
  'payload': null,
};

class SchedulingTransport extends SyncTransport {
  SchedulingTransport()
    : super(Uri.parse(configuration.serverUrl), MockClient((_) async => http.Response('', 500)));
  int pulls = 0, pushes = 0;
  Future<SyncJson> Function()? onPull;
  Future<void> Function()? beforePush;
  @override
  Future<SyncJson> pull(String token, String cursor) async {
    pulls++;
    return onPull == null ? {'entities': [], 'nextCursor': cursor, 'hasMore': false} : await onPull!();
  }

  @override
  Future<List<SyncJson>> push(String token, List<SyncJson> operations) async {
    pushes++;
    await beforePush?.call();
    return [
      for (final operation in operations)
        {
          'operationId': operation['operationId'],
          'status': 'accepted',
          'entity': {
            'entityType': operation['entityType'],
            'entityId': operation['entityId'],
            'revision': ((operation['baseRevision'] as int?) ?? 0) + 1,
            'deleted': operation['deleted'],
            'payload': operation['payload'],
            'cursor': '1',
          },
        },
    ];
  }
}

SyncController schedulingController(
  TestRepository repository,
  SyncAuth auth,
  SchedulingTransport transport,
) => SyncController(config: configuration, auth: auth, repository: repository, transport: transport);

class BatchRepository extends TestRepository {
  @override
  Future<List<SyncJson>> pendingOperations(String namespace) async => pending.take(100).toList();
  @override
  Future<void> applyPushResults(String namespace, List<SyncJson> results) async {
    receipts++;
    final accepted = results.map((result) => result['operationId']).toSet();
    pending = pending.where((operation) => !accepted.contains(operation['operationId'])).toList();
  }
}

class ConflictedRepository extends TestRepository {
  void Function()? afterPull;
  @override
  Future<List<SyncJson>> pendingOperations(String namespace) async => [];
  @override
  Future<List<SyncJson>> conflicts(String namespace) async => [
    {'entityId': accountId, 'revision': 2},
  ];
  @override
  Future<void> applyPullPage(String namespace, List<SyncJson> entities, String nextCursor) async {
    await super.applyPullPage(namespace, entities, nextCursor);
    afterPull?.call();
  }
}

void main() {
  testWidgets('signout fences an in-flight pull and cancels scheduled account work', (tester) async {
    final response = Completer<SyncJson>();
    final repository = TestRepository();
    final transport = SchedulingTransport()..onPull = () => response.future;
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pulls, 1);
    sync.requestSync();
    sync.localChanged();
    final signingOut = sync.signOut();
    await tester.pump();
    response.complete({'entities': [], 'nextCursor': '1', 'hasMore': false});
    await tester.pump();
    await signingOut;
    await tester.pump(const Duration(minutes: 2));
    expect(sync.account, isNull);
    expect(sync.phase, SyncPhase.signedOut);
    expect(sync.lastSynced, isNull);
    expect(repository.applications, 0);
    expect(repository.namespaces.last, 'guest');
    expect(transport.pulls, 1);
  });

  testWidgets('a queued request for A never runs under a replacement account B', (tester) async {
    final auth = TestAuth();
    final transport = SchedulingTransport();
    final sync = schedulingController(TestRepository(), auth, transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    auth.session = AuthSession('other-account', 'other-token', 'other-refresh', DateTime(2100));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pulls, 0);
  });

  testWidgets('guest and unconfigured builds remain zero-network for every trigger', (tester) async {
    final transport = SchedulingTransport();
    final guest = schedulingController(TestRepository(), TestAuth()..session = null, transport);
    final unavailable = SyncController(
      config: const SyncConfig(serverUrl: '', authUrl: '', publicKey: '', emailAuth: false),
      auth: TestAuth(),
      repository: TestRepository(),
      transport: transport,
    );
    for (final sync in [guest, unavailable]) {
      unawaited(sync.initialize());
      await tester.pump();
      sync.requestSync();
      sync.localChanged();
      unawaited(sync.sync());
    }
    await tester.pump(const Duration(minutes: 2));
    expect(transport.pulls, 0);
    expect(transport.pushes, 0);
    guest.dispose();
    unavailable.dispose();
  });

  testWidgets('offline work remains durable and the bounded fallback detects reconnect', (tester) async {
    var online = false;
    final repository = TestRepository()..pending = [operation()];
    final transport = SchedulingTransport();
    transport.beforePush = () async {
      if (!online) throw SyncFailure('offline');
    };
    final sync = schedulingController(repository, TestAuth(), transport);
    unawaited(sync.initialize());
    await tester.pump();
    expect(sync.phase, SyncPhase.offline);
    expect(sync.pendingCount, 1);
    expect(repository.pending, hasLength(1));
    expect(transport.pushes, 1);
    await tester.pump(const Duration(seconds: 59));
    expect(transport.pushes, 1);
    online = true;
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pushes, 2);
    expect(transport.pulls, 1);
    expect(sync.pendingCount, 0);
    expect(sync.phase, SyncPhase.ready);
    sync.dispose();
  });

  testWidgets('authorization failure stops automatic requests until explicit sign-in recovery', (
    tester,
  ) async {
    var authorized = false;
    final transport = SchedulingTransport();
    transport.onPull = () async {
      if (!authorized) throw SyncFailure('expired token', status: 401);
      return {'entities': [], 'nextCursor': '1', 'hasMore': false};
    };
    final sync = schedulingController(TestRepository(), TestAuth(), transport);
    unawaited(sync.initialize());
    await tester.pump();
    expect(sync.phase, SyncPhase.needsAuthorization);
    sync.requestSync();
    await tester.pump(const Duration(minutes: 2));
    expect(transport.pulls, 1);
    authorized = true;
    final signingIn = sync.signIn('person@example.com', 'password');
    await tester.pump();
    await signingIn;
    expect(transport.pulls, 2);
    expect(sync.phase, SyncPhase.ready);
    sync.dispose();
  });

  testWidgets('persistence notifications from pulls with retained conflicts never echo', (tester) async {
    final repository = ConflictedRepository()..pending = [operation()];
    final transport = SchedulingTransport();
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    repository.afterPull = sync.localChanged;
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(transport.pulls, 1);
    expect(transport.pushes, 0);
    expect(sync.pendingCount, 1);
    expect(sync.conflicts.single['revision'], 2);
    expect(sync.lastSynced, isNotNull);
  });

  testWidgets('a backlog larger than one bounded cycle continues promptly', (tester) async {
    final repository = BatchRepository()
      ..pending = [
        for (var i = 0; i < 1005; i++) {...operation(), 'operationId': 'operation-$i'},
      ];
    final transport = SchedulingTransport();
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(sync.pendingCount, 0);
    expect(transport.pushes, 11);
  });

  testWidgets('bounded repository batches drain promptly rather than one batch per minute', (tester) async {
    final repository = BatchRepository()
      ..pending = [
        for (var i = 0; i < 205; i++) {...operation(), 'operationId': 'operation-$i'},
      ];
    final transport = SchedulingTransport();
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pushes, 3);
    expect(sync.pendingCount, 0);
  });

  testWidgets('a durable save during a pull schedules one follow-up without overlapping cycles', (
    tester,
  ) async {
    final response = Completer<SyncJson>();
    final repository = TestRepository();
    final transport = SchedulingTransport();
    transport.onPull = () async =>
        transport.pulls == 1 ? response.future : {'entities': [], 'nextCursor': '1', 'hasMore': false};
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    repository.pending = [operation()];
    sync.localChanged();
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pushes, 0);
    response.complete({'entities': [], 'nextCursor': '1', 'hasMore': false});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pushes, 1);
    expect(transport.pulls, 2);
    expect(sync.pendingCount, 0);
  });

  testWidgets('foreground requests coalesce and an in-flight request gets one follow-up pull', (
    tester,
  ) async {
    final response = Completer<SyncJson>();
    final transport = SchedulingTransport();
    transport.onPull = () async =>
        transport.pulls == 1 ? response.future : {'entities': [], 'nextCursor': '1', 'hasMore': false};
    final sync = schedulingController(TestRepository(), TestAuth(), transport);
    addTearDown(sync.dispose);
    sync.requestSync();
    sync.requestSync();
    sync.requestSync();
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pulls, 1);
    sync.requestSync();
    sync.requestSync();
    response.complete({'entities': [], 'nextCursor': '1', 'hasMore': false});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pulls, 2);
    expect(sync.lastSynced, isNotNull);
  });

  testWidgets('acknowledged local changes push promptly and coalesce', (tester) async {
    final repository = TestRepository();
    final transport = SchedulingTransport();
    final sync = schedulingController(repository, TestAuth(), transport);
    addTearDown(sync.dispose);
    unawaited(sync.sync());
    await tester.pump();
    repository.pending = [operation()];
    sync.localChanged();
    sync.localChanged();
    sync.localChanged();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.pushes, 1);
    expect(sync.pendingCount, 0);
    expect(sync.phase, SyncPhase.ready);
  });
}
