import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gymmane/screens/sync/strava_section.dart';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'sync_controller_test.dart' as c;

void main() {
  testWidgets('delayed A workout lookup cannot publish A jobs under B and B refresh follows', (tester) async {
    final local = Completer<List<SyncJson>>();
    final auth = c.TestAuth();
    var statusRequests = 0, lookups = 0;
    final sync = c.controller(c.TestRepository(), auth, (request) async {
      if (request.url.path == '/v1/sync/pull') {
        return http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200);
      }
      statusRequests++;
      return http.Response(
        jsonEncode({
          'configured': true,
          'connected': true,
          'jobs': statusRequests == 1
              ? [
                  {
                    'workoutId': 'ACCOUNT_A_PRIVATE_ID',
                    'name': 'Account A private workout',
                    'status': 'confirmed',
                    'canRetry': false,
                  },
                ]
              : [],
        }),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StravaSection(sync: sync, workouts: () => ++lookups == 1 ? local.future : Future.value([])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(statusRequests, 1);
    await tester.runAsync(() async {
      await sync.signOut();
      auth.session = AuthSession('12345678-1234-1234-1234-123456789abd', 'b', 'rb', DateTime(2100));
      await sync.signIn('b', 'unused');
    });
    await tester.pump();
    local.complete([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('ACCOUNT_A_PRIVATE_ID'), findsNothing);
    expect(find.textContaining('Account A private workout'), findsNothing);
    expect(statusRequests, 2);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
