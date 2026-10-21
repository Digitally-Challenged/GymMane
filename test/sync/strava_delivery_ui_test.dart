import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gymmane/screens/sync/strava_section.dart';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'sync_controller_test.dart' as c;

void main() {
  testWidgets('sync reveals the selected synced source and export remains explicit', (tester) async {
    var synced = false;
    final posts = <http.Request>[];
    final sync = c.controller(c.TestRepository(), c.TestAuth(), (request) async {
      if (request.url.path == '/v1/sync/pull') {
        return http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200);
      }
      if (request.method == 'POST') posts.add(request);
      return http.Response(jsonEncode({'configured': true, 'connected': true, 'jobs': []}), 200);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StravaSection(
              sync: sync,
              workoutId: 'selected',
              workouts: () async {
                return synced
                    ? [
                        {
                          'entityId': 'newer',
                          'revision': 9,
                          'payload': {'n': 'Unrelated newer workout'},
                        },
                        {
                          'entityId': 'selected',
                          'revision': 2,
                          'payload': {'n': 'Selected workout', 'd': '2026-10-20T14:00:00Z'},
                        },
                      ]
                    : [];
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('Waiting for cloud sync'), findsOneWidget);
    expect(find.text('Export'), findsNothing);
    synced = true;
    await tester.runAsync(() async {
      await sync.sync();
      await Future<void>(() {});
    });
    await tester.pumpAndSettle();
    expect(find.text('Selected workout'), findsOneWidget);
    expect(find.text('Unrelated newer workout'), findsNothing);
    expect(find.textContaining('Oct 20, 2026'), findsOneWidget);
    await tester.ensureVisible(find.text('Export'));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(posts.single.url.path, '/v1/strava/export');
    expect(jsonDecode(posts.single.body), {'workoutId': 'selected', 'revision': 2});
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('account switch while retry consent is open suppresses the old request', (tester) async {
    final auth = c.TestAuth();
    final original = auth.session;
    var creates = 0;
    final sync = c.controller(c.TestRepository(), auth, (request) async {
      if (request.url.path == '/v1/sync/pull') {
        return http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200);
      }
      if (request.method == 'POST') creates++;
      return http.Response(
        jsonEncode({
          'configured': true,
          'connected': true,
          'jobs': [
            {
              'workoutId': 'private-a',
              'revision': 1,
              'name': 'Account A workout',
              'status': 'failed',
              'canRetry': true,
            },
          ],
        }),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StravaSection(sync: sync, workouts: () async => []),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await sync.signOut();
      auth.session = AuthSession('account-b', 'b', 'rb', DateTime(2100));
      await sync.signIn('b', 'unused');
      await sync.signOut();
      auth.session = original;
      await sync.signIn('a', 'unused');
    });
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(creates, 0);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('only server-approved retry is offered and uses retry endpoint after consent', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = <http.Request>[];
    final sync = c.controller(c.TestRepository(), c.TestAuth(), (request) async {
      if (request.method == 'POST') {
        posts.add(request);
        return http.Response('{}', 200);
      }
      return http.Response(
        jsonEncode({
          'configured': true,
          'connected': true,
          'jobs': [
            {
              'workoutId': 'safe-id',
              'revision': 3,
              'name': 'Safe strength',
              'status': 'failed',
              'canRetry': true,
            },
            {
              'workoutId': 'unknown-id',
              'revision': 1,
              'name': 'Uncertain strength',
              'status': 'unknown',
              'canRetry': false,
            },
          ],
        }),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StravaSection(sync: sync, workouts: () async => []),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.textContaining('Safe strength'), findsOneWidget);
    expect(find.textContaining('safe-id'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Check Strava manually. Do not retry this upload.'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(posts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(posts.single.url.path, '/v1/strava/retry');
    expect(jsonDecode(posts.single.body), {'workoutId': 'safe-id', 'revision': 3});
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
