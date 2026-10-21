import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gymmane/screens/sync/healthkit_section.dart';
import 'package:gymmane/services/integrations/healthkit/healthkit_adapter.dart';
import 'package:gymmane/services/sync/healthkit_delivery.dart';
import 'package:gymmane/services/sync/sync_runtime.dart';
import 'healthkit_delivery_test.dart' show Ledger, Native, OperationLedger, OperationGate, workout;
import 'sync_controller_test.dart' as c;

class PermissionHealth extends Native {
  HealthKitAuthorization permission = HealthKitAuthorization.denied;
  int permissionReads = 0;
  @override
  Future<bool> availability() async => true;
  @override
  Future<HealthKitAuthorization> authorization() async {
    permissionReads++;
    return permission;
  }
}

void main() {
  testWidgets('an account transition cancels Health consent even when returning to the same account', (
    tester,
  ) async {
    final auth = c.TestAuth();
    final original = auth.session;
    final sync = c.controller(
      c.TestRepository(),
      auth,
      (_) async => http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200),
    );
    SyncRuntime.controller = sync;
    final native = PermissionHealth()..permission = HealthKitAuthorization.authorized;
    final ledger = Ledger()..data = {'enabled': true};
    final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthKitSection(delivery: delivery, adapter: native),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export'));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await sync.signOut();
      auth.session = original;
      await sync.signIn('a', 'unused');
    });
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(native.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    SyncRuntime.controller = null;
    delivery.dispose();
    sync.dispose();
  });
  for (final boundary in ['phone', 'candidates', 'intent']) {
    testWidgets('confirmed Health export stops after account return during $boundary', (tester) async {
      final auth = c.TestAuth();
      final original = auth.session;
      final sync = c.controller(
        c.TestRepository(),
        auth,
        (_) async => http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200),
      );
      SyncRuntime.controller = sync;
      final native = PermissionHealth()..permission = HealthKitAuthorization.authorized;
      final ledger = OperationLedger()
        ..namespace = 'account-a'
        ..data = {'enabled': true};
      OperationGate? phoneGate;
      final delivery = HealthKitDelivery(
        ledger,
        adapter: native,
        isPhone: () async {
          await phoneGate?.pause('phone');
          return true;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthKitSection(delivery: delivery, adapter: native),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      final gate = OperationGate(boundary);
      phoneGate = gate;
      ledger.gate = gate;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(gate.entered.isCompleted, true);
      expect(native.saves, isEmpty);
      await tester.runAsync(() async {
        ledger.namespace = 'guest';
        await sync.signOut();
        ledger.namespace = 'account-a';
        auth.session = original;
        await sync.signIn('a', 'unused');
      });
      gate.released.complete();
      await tester.pumpAndSettle();
      expect(native.saves, isEmpty);
      expect(native.deletions, isEmpty);
      expect(ledger.writes, boundary == 'intent' ? 1 : 0);
      if (boundary == 'intent') expect(ledger.data['records'][workout['id']]['status'], 'sending');
      await tester.pumpWidget(const SizedBox());
      SyncRuntime.controller = null;
      delivery.dispose();
      sync.dispose();
    });
  }
  testWidgets('resume refreshes Health permission without prompting or exporting', (tester) async {
    final native = PermissionHealth();
    final delivery = HealthKitDelivery(Ledger(), adapter: native, isPhone: () async => true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthKitSection(delivery: delivery, adapter: native),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('permission denied'), findsOneWidget);
    final reads = native.permissionReads;
    native.permission = HealthKitAuthorization.authorized;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(native.permissionReads, greaterThan(reads));
    expect(find.text('Workout write permission granted.'), findsOneWidget);
    expect(native.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    delivery.dispose();
  });

  testWidgets('completed sync refreshes Health candidates without a permission prompt', (tester) async {
    final sync = c.controller(
      c.TestRepository(),
      c.TestAuth(),
      (_) async => http.Response(jsonEncode({'entities': [], 'nextCursor': '0', 'hasMore': false}), 200),
    );
    SyncRuntime.controller = sync;
    final native = PermissionHealth()..permission = HealthKitAuthorization.authorized;
    final ledger = Ledger()
      ..data = {'enabled': true}
      ..eligible = [];
    final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthKitSection(delivery: delivery, adapter: native),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsNothing);
    ledger.eligible = [workout];
    await tester.runAsync(sync.sync);
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsOneWidget);
    expect(native.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    SyncRuntime.controller = null;
    delivery.dispose();
    sync.dispose();
  });
}
