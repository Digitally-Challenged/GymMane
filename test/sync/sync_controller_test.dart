import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'package:gymmane/services/sync/sync_config.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/services/sync/sync_repository_port.dart';
import 'package:gymmane/services/sync/sync_transport.dart';

const accountId = '12345678-1234-1234-1234-123456789abc';
const configuration = SyncConfig(
  serverUrl: 'https://sync.example',
  authUrl: 'https://auth.example',
  publicKey: 'public',
  emailAuth: true,
);

class TestAuth implements SyncAuth {
  @override
  AuthSession? session = AuthSession(accountId, 'token', 'refresh', DateTime(2100));
  @override
  Future<String> accessToken() async => session!.accessToken;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {
    session = null;
  }
}

class TestRepository implements SyncRepositoryPort {
  String savedCursor = '0';
  int applications = 0, adoptions = 0, receipts = 0;
  bool failCommit = false;
  List<SyncJson> pending = [];
  final namespaces = <String>[];
  @override
  Future<void> selectNamespace(String namespace) async {
    namespaces.add(namespace);
  }

  @override
  Future<List<SyncJson>> pendingOperations(String namespace) async => pending;
  @override
  Future<void> applyPushResults(String namespace, List<SyncJson> results) async {
    receipts++;
    pending = [];
  }

  @override
  Future<void> applyPullPage(String namespace, List<SyncJson> entities, String nextCursor) async {
    if (failCommit) throw StateError('disk full');
    applications++;
    savedCursor = nextCursor;
  }

  @override
  Future<int> pendingCount(String namespace) async => pending.length;
  @override
  Future<String> cursor(String namespace) async => savedCursor;
  @override
  Future<Map<String, int>> guestPreview() async => {'workouts': 3};
  @override
  Future<void> adoptGuest(String namespace) async {
    adoptions++;
  }

  @override
  Future<List<SyncJson>> conflicts(String namespace) async => [];
  @override
  Future<void> resolveConflict(String namespace, SyncJson conflict, {required bool keepLocal}) async {}
}

SyncController controller(
  TestRepository repository,
  TestAuth auth,
  Future<http.Response> Function(http.Request) send,
) => SyncController(
  config: configuration,
  auth: auth,
  repository: repository,
  transport: SyncTransport(Uri.parse(configuration.serverUrl), MockClient(send)),
);
void main() {
  test('pull continues pagination and commits each page, never adopts guest automatically', () async {
    final repository = TestRepository();
    final sync = controller(repository, TestAuth(), (request) async {
      final first = request.url.queryParameters['cursor'] == '0';
      return http.Response(
        jsonEncode({
          'entities': first
              ? [
                  {
                    'entityType': 'workout',
                    'entityId': accountId,
                    'revision': 1,
                    'deleted': true,
                    'payload': null,
                    'cursor': '1',
                  },
                ]
              : [],
          'nextCursor': '1',
          'hasMore': first,
        }),
        200,
      );
    });
    addTearDown(sync.dispose);
    await sync.sync();
    expect(repository.applications, 2);
    expect(repository.savedCursor, '1');
    expect(repository.adoptions, 0);
    expect(sync.phase, SyncPhase.ready);
  });
  test('failed atomic apply leaves cursor restartable and displays error', () async {
    final repository = TestRepository()..failCommit = true;
    final sync = controller(
      repository,
      TestAuth(),
      (_) async => http.Response(jsonEncode({'entities': [], 'nextCursor': '1', 'hasMore': false}), 200),
    );
    addTearDown(sync.dispose);
    await sync.sync();
    expect(repository.savedCursor, '0');
    expect(sync.phase, SyncPhase.error);
    expect(sync.lastSynced, isNull);
  });
  test('response loss leaves original outbox operation and visible offline state', () async {
    final repository = TestRepository()
      ..pending = [
        {'operationId': accountId},
      ];
    final sync = controller(repository, TestAuth(), (_) async => throw http.ClientException('offline'));
    addTearDown(sync.dispose);
    await sync.sync();
    expect(repository.pending.single['operationId'], accountId);
    expect(repository.receipts, 0);
    expect(sync.pendingCount, 1);
    expect(sync.phase, SyncPhase.offline);
  });
  test('late response cannot apply after account changes', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final repository = TestRepository();
    final auth = TestAuth();
    final sync = controller(repository, auth, (_) {
      started.complete();
      return response.future;
    });
    addTearDown(sync.dispose);
    final running = sync.sync();
    await started.future;
    auth.session = null;
    response.complete(http.Response(jsonEncode({'entities': [], 'nextCursor': '1', 'hasMore': false}), 200));
    await running;
    expect(repository.applications, 0);
  });
  test('revoked token shows authorization required and retains outbox', () async {
    final repository = TestRepository()
      ..pending = [
        {'operationId': accountId},
      ];
    final sync = controller(repository, TestAuth(), (_) async => http.Response('{}', 401));
    addTearDown(sync.dispose);
    await sync.sync();
    expect(sync.phase, SyncPhase.needsAuthorization);
    expect(repository.pending.length, 1);
  });
}
