import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/screens/sync/completed_workout_delivery.dart';
import 'package:gymmane/screens/sync/delivery_updates.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/sync/healthkit_delivery.dart';
import 'package:gymmane/services/sync/store_health_delivery.dart';
import 'package:gymmane/services/sync/sync_runtime.dart';
import 'package:gymmane/state/fit_state.dart';
import 'healthkit_delivery_test.dart' show Native;
import 'sync_controller_test.dart' as c;

class AvailableHealth extends Native {
  @override
  Future<bool> availability() async => true;
}

const selectedId = '12345678-1234-4234-8234-123456789aaa';
const newerId = '12345678-1234-4234-8234-123456789bbb';

LoggedSession completed(String id, String name, int day) => LoggedSession(
  DateTime.utc(2026, 10, day, 14),
  60,
  [],
  id: id,
  name: name,
  startedAt: DateTime.utc(2026, 10, day, 13, 58),
);

void main() {
  testWidgets('missing selected ID never falls back and guest saves refresh the card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.sessions.add(completed(newerId, 'Other workout', 21));
    await fit.persistNow(rethrowErrors: true);
    SyncRuntime.health = null;
    SyncRuntime.controller = null;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CompletedWorkoutDelivery(workoutId: selectedId)),
      ),
    );
    expect(find.text('Other workout'), findsNothing);
    expect(find.text('Saved on this device'), findsNothing);
    fit.sessions.add(completed(selectedId, 'Selected saved workout', 20));
    await fit.persistNow(rethrowErrors: true);
    fit.reloadSyncedEntities();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Selected saved workout'), findsOneWidget);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('Other workout'), findsNothing);
    expect(find.text('Export'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final source in ['imported', 'conflicted']) {
    testWidgets('$source selected source rename and deletion refresh without exportable changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await Store.instance.init();
      fit.resetAllData();
      final repository = Store.instance.repository;
      if (source == 'conflicted') {
        await repository.selectNamespace('account-a');
        fit.reloadSyncedEntities();
      }
      fit.sessions.add(
        LoggedSession.fromJson({
          ...completed(selectedId, 'Original selected workout', 20).toJson(),
          'origin': source == 'imported' ? 'imported' : 'gymmane',
        }),
      );
      await fit.persistNow(rethrowErrors: true);
      if (source == 'conflicted') {
        await repository.applyPullPage(repository.namespace, [
          {
            'entityType': 'workout',
            'entityId': selectedId,
            'revision': 1,
            'cursor': '1',
            'deleted': false,
            'payload': completed(selectedId, 'Remote conflict', 20).toJson(),
          },
        ], '1');
        expect(repository.conflicts(repository.namespace), contains('workout:$selectedId'));
      }
      SyncRuntime.health = null;
      SyncRuntime.controller = null;
      expect(repository.exportableWorkouts(repository.namespace), isEmpty);
      var providerRefreshes = 0;
      final candidates = DeliveryUpdates(() => providerRefreshes++);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CompletedWorkoutDelivery(workoutId: selectedId)),
        ),
      );
      expect(find.text('Original selected workout'), findsOneWidget);
      // Unrelated FitState notifications do not refresh providers or the source.
      fit.reloadSyncedEntities();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(providerRefreshes, 0);
      fit.sessions.single.name = 'Renamed selected workout';
      await fit.persistNow(rethrowErrors: true);
      fit.reloadSyncedEntities();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(repository.exportableWorkouts(repository.namespace), isEmpty);
      expect(find.text('Renamed selected workout'), findsOneWidget);
      expect(find.text('Original selected workout'), findsNothing);
      expect(providerRefreshes, 0);
      fit.sessions.clear();
      await fit.persistNow(rethrowErrors: true);
      fit.reloadSyncedEntities();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(repository.exportableWorkouts(repository.namespace), isEmpty);
      expect(find.text('Renamed selected workout'), findsNothing);
      expect(find.text('Saved on this device'), findsNothing);
      expect(providerRefreshes, 0);
      candidates.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('selected ineligible conflict status refreshes without metadata or candidate changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    final repository = Store.instance.repository;
    await repository.selectNamespace(c.accountId);
    fit.reloadSyncedEntities();
    fit.sessions.add(
      LoggedSession.fromJson({
        ...completed(selectedId, 'Imported selected workout', 20).toJson(),
        'origin': 'imported',
      }),
    );
    await fit.persistNow(rethrowErrors: true);
    final sync = c.controller(c.TestRepository(), c.TestAuth(), (_) async => http.Response('{}', 200));
    SyncRuntime.controller = sync;
    SyncRuntime.health = null;
    final before = repository.entityMetadata(repository.namespace, 'workout', selectedId);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CompletedWorkoutDelivery(workoutId: selectedId)),
      ),
    );
    expect(find.textContaining('conflicts need review'), findsNothing);
    await repository.applyPullPage(repository.namespace, [
      {
        'entityType': 'workout',
        'entityId': selectedId,
        'revision': 1,
        'cursor': '1',
        'deleted': true,
        'payload': null,
      },
    ], '1');
    fit.reloadSyncedEntities();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(repository.entityMetadata(repository.namespace, 'workout', selectedId), before);
    expect(repository.exportableWorkouts(repository.namespace), isEmpty);
    expect(find.textContaining('conflicts need review'), findsOneWidget);
    expect(find.text('Imported selected workout'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    SyncRuntime.controller = null;
    sync.dispose();
  });
  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('delivery and consent fit $size at 200% text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Nunito')..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'));
      await font.load();
      SharedPreferences.setMockInitialValues({});
      await Store.instance.init();
      fit.resetAllData();
      fit.sessions.add(completed(selectedId, 'Evening strength and conditioning', 20));
      await fit.persistNow(rethrowErrors: true);
      final native = AvailableHealth();
      final health = HealthKitDelivery(
        StoreHealthDelivery(Store.instance),
        adapter: native,
        isPhone: () async => true,
      );
      SyncRuntime.health = health;
      SyncRuntime.controller = null;
      await health.designate(true);
      const capture = Key('capture');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Nunito'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: capture,
            child: const Scaffold(
              body: SingleChildScrollView(child: CompletedWorkoutDelivery(workoutId: selectedId)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 390) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/gymmane-E-iphone-200.png').writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('Export'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextButton, 'Cancel').hitTestable(), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(native.saves, isEmpty);
      await tester.pumpWidget(const SizedBox());
      SyncRuntime.health = null;
      health.dispose();
      await fit.persistNow();
    });
  }
  testWidgets('guest exports only the selected durable workout after confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.sessions.addAll([
      completed(selectedId, 'Selected strength', 20),
      completed(newerId, 'Unrelated newer workout', 21),
    ]);
    await fit.persistNow(rethrowErrors: true);
    final native = AvailableHealth();
    final health = HealthKitDelivery(
      StoreHealthDelivery(Store.instance),
      adapter: native,
      isPhone: () async => true,
    );
    SyncRuntime.health = health;
    SyncRuntime.controller = null;
    await health.designate(true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CompletedWorkoutDelivery(workoutId: selectedId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected strength'), findsWidgets);
    expect(find.textContaining('Unrelated newer workout'), findsNothing);
    expect(find.textContaining('Oct 20, 2026'), findsWidgets);
    expect(native.saves, isEmpty);
    await tester.ensureVisible(find.text('Export'));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(native.saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(native.saves.single.id, selectedId);
    expect(find.textContaining(selectedId), findsNothing);
    await tester.pumpWidget(const SizedBox());
    SyncRuntime.health = null;
    health.dispose();
    await fit.persistNow();
  });
}
