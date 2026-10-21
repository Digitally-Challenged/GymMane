import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gymmane/screens/sync/sync_screen.dart';
import 'package:gymmane/services/sync/sync_config.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'sync_controller_test.dart' show TestRepository, TestAuth;

void main() {
  testWidgets('missing config shows unavailable and never offers sign in', (tester) async {
    var requests = 0;
    final sync = SyncController(
      config: const SyncConfig.environment(),
      auth: TestAuth()..session = null,
      repository: TestRepository(),
      transport: SyncTransport(
        Uri.parse('https://unused.example'),
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      ),
    );
    addTearDown(sync.dispose);
    await sync.initialize();
    await tester.pumpWidget(MaterialApp(home: SyncScreen(controller: sync)));
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(requests, 0);
  });
  testWidgets('guest adoption requires preview confirmation and cancel is inert', (tester) async {
    final repository = TestRepository();
    final sync = SyncController(
      config: const SyncConfig.environment(),
      auth: TestAuth(),
      repository: repository,
      transport: SyncTransport(
        Uri.parse('https://unused.example'),
        MockClient((_) async => http.Response('{}', 500)),
      ),
    );
    addTearDown(sync.dispose);
    await tester.pumpWidget(MaterialApp(home: SyncScreen(controller: sync)));
    await tester.tap(find.text('Review guest history for upload'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 workouts'), findsOneWidget);
    expect(repository.adoptions, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.adoptions, 0);
  });
}
