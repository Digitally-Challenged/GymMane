import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/block_program.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/block_program_card.dart';
import 'package:gymmane/widgets/block_exercise_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements StorageBackend {
  Map<String, dynamic>? snapshot;
  @override
  Future<Map<String, dynamic>?> read() async => snapshot;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    snapshot = value;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Store.backendFactory = (_) async => _MemoryStorage();
    await Store.instance.init();
    fit.resetAllData();
    fit.setLanguage('en');
    fit.applyHybridProgram();
    await fit.persistNow(rethrowErrors: true);
  });
  tearDown(() => fit.saveAndExit());

  Future<void> mount(WidgetTester tester, Widget child, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: fit,
            builder: (_, _) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('program card exposes phase and optional-day action at 200 percent text', (tester) async {
    final routine = fit.routines.first;
    await mount(tester, BlockProgramCard(routine: routine), scale: 2);
    expect(find.text('Week 1 / 12 · Calibration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(routine.program!.fifthOn(1), isTrue);
    expect(tester.takeException(), isNull);
    fit.saveAndExit();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('recovery control records feedback and refreshes only untouched workouts', (tester) async {
    final r = fit.routines.first;
    final id = r.exerciseIds.first;
    final today = DateTime.now();
    final prior = LoggedSession(
      today.subtract(const Duration(hours: 1)),
      1000,
      [
        LoggedExercise(id, 'Synthetic press', 'chest', [LoggedSet(6, 40, rpe: 7), LoggedSet(8, 35, rpe: 7)]),
      ],
      program: BlockSession(
        programId: r.program!.id,
        day: 0,
        week: 1,
        minimumRir: 3,
        targets: {
          id: [const BlockTarget(6, 40), const BlockTarget(8, 35)],
        },
      ),
    );
    fit.sessions.add(prior);
    fit.startRoutine(r);
    await mount(tester, BlockExerciseContext(exerciseId: id), scale: 2);
    final recovered = find.text('Recovered; symptoms stable');
    await tester.ensureVisible(recovered);
    await tester.tap(recovered);
    await tester.pump();
    expect(prior.program!.responses[id], BlockResponse.stable);
    final current = fit.session!.exercises.first.sets;
    current.first.done = true;
    final reduce = find.text('Not recovered / symptoms worse');
    await tester.ensureVisible(reduce);
    await tester.tap(reduce);
    await tester.pump();
    expect(identical(fit.session!.exercises.first.sets, current), isTrue);
    expect(prior.program!.responses[id], BlockResponse.aggravated);
    expect(tester.takeException(), isNull);
    fit.saveAndExit();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('load editor validates input and saves program-specific limits', (tester) async {
    final routine = fit.routines.first;
    final id = routine.exerciseIds.first;
    await mount(tester, BlockProgramCard(routine: routine));
    final expand = find.text('Exercise loads and limits');
    await tester.ensureVisible(expand);
    await tester.pump();
    await tester.tap(expand);
    await tester.pumpAndSettle();
    final press = find.text('Swiss Bar Bench Press');
    await tester.ensureVisible(press);
    await tester.pump();
    await tester.tap(press);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(1), '-5');
    final save = find.text('Save changes');
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Enter a valid positive load.'), findsOneWidget);
    await tester.enterText(fields.at(0), '50');
    await tester.enterText(fields.at(1), '5');
    await tester.enterText(fields.at(3), '100');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 500));
    expect(routine.program!.rules[id]!.incrementKg, fit.fromDisplayWeight(5));
    expect(routine.program!.rules[id]!.maxWeightKg, fit.fromDisplayWeight(100));
    fit.saveAndExit();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
