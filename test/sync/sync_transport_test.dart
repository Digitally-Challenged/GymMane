import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'package:gymmane/services/sync/sync_config.dart';

const id = '12345678-1234-1234-1234-123456789abc';
SyncJson entity({String cursor = '1'}) => {
  'entityType': 'workout',
  'entityId': id,
  'revision': 1,
  'deleted': false,
  'payload': {'id': id, 'd': '2026-10-20T14:00:00.000Z', 'dur': 3600, 'ex': []},
  'cursor': cursor,
};
SyncJson operation() => {
  'operationId': id,
  'entityType': 'workout',
  'entityId': id,
  'baseRevision': 0,
  'deleted': false,
  'payload': {'id': id, 'd': '2026-10-20T14:00:00.000Z', 'dur': 3600, 'ex': []},
};
SyncTransport transport(Object body, {int status = 200, void Function(http.Request)? inspect}) =>
    SyncTransport(
      Uri.parse('https://sync.example'),
      MockClient((request) async {
        inspect?.call(request);
        return http.Response(jsonEncode(body), status);
      }),
    );

void main() {
  test('push matches protocol and bearer auth; conflicts are returned intact', () async {
    final result = await transport(
      {
        'results': [
          {'operationId': id, 'status': 'conflict', 'entity': entity()},
        ],
      },
      inspect: (request) {
        expect(request.url.path, '/v1/sync/push');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {
          'schemaVersion': 1,
          'operations': [operation()],
        });
        expect(request.followRedirects, false);
      },
    ).push('token', [operation()]);
    expect(result.single['status'], 'conflict');
  });
  test('missing and mismatched receipts cannot acknowledge local operations', () async {
    await expectLater(transport({'results': []}).push('token', [operation()]), throwsFormatException);
    await expectLater(
      transport({
        'results': [
          {
            'operationId': id,
            'status': 'accepted',
            'entity': {...entity(), 'entityType': 'routine'},
          },
        ],
      }).push('token', [operation()]),
      throwsFormatException,
    );
  });
  test('opaque cursors remain exact beyond JS integer precision', () async {
    final result = await transport(
      {
        'entities': [entity(cursor: '90071992547409930')],
        'nextCursor': '90071992547409930',
        'hasMore': false,
      },
      inspect: (request) {
        expect(request.url.queryParameters, {'cursor': '90071992547409929', 'limit': '100'});
      },
    ).pull('token', '90071992547409929');
    expect(result['nextCursor'], '90071992547409930');
  });
  test('nonadvancing and unordered pages fail before cursor commit', () async {
    await expectLater(
      transport({'entities': [], 'nextCursor': '0', 'hasMore': true}).pull('token', '0'),
      throwsFormatException,
    );
    await expectLater(
      transport({
        'entities': [entity(cursor: '2'), entity()],
        'nextCursor': '2',
        'hasMore': false,
      }).pull('token', '0'),
      throwsFormatException,
    );
  });
  test('invalid tombstones rejected', () async {
    await expectLater(
      transport({
        'entities': [
          {...entity(), 'deleted': true},
        ],
        'nextCursor': '1',
        'hasMore': false,
      }).pull('token', '0'),
      throwsFormatException,
    );
  });
  test('HTTP errors classify auth, quota and misuse without exposing server body', () async {
    for (final status in [401, 403, 409, 429, 500]) {
      await expectLater(
        transport({'secret': 'private'}, status: status).pull('token', '0'),
        throwsA(
          isA<SyncFailure>()
              .having((e) => e.status, 'status', status)
              .having((e) => e.toString().contains('private'), 'redacted', false),
        ),
      );
    }
  });
  test('workout ISO validation rejects calendar overflow and preserves legacy timestamps', () {
    for (final date in ['2026-10-20T14:00:00.123456', '2024-02-29T00:00:00Z']) {
      expect(() => validateWorkoutDate(date), returnsNormally);
    }
    for (final date in ['2026-02-30T00:00:00Z', '2026-01-01T25:00:00Z', 'October 20 2026']) {
      expect(() => validateWorkoutDate(date), throwsFormatException);
    }
  });
  test('configuration requires HTTPS and explicit email opt in', () {
    expect(const SyncConfig.environment().unavailableReason, isNotNull);
    expect(
      const SyncConfig(
        serverUrl: 'http://host',
        authUrl: 'https://auth.example',
        publicKey: 'public',
        emailAuth: true,
      ).unavailableReason,
      isNotNull,
    );
    expect(
      const SyncConfig(
        serverUrl: 'https://sync.example',
        authUrl: 'https://auth.example',
        publicKey: 'public',
        emailAuth: true,
      ).unavailableReason,
      isNull,
    );
  });
}
