import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/app/gymmane_app.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/models/exercise.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/screens/session_screen.dart';
import 'package:gymmane/screens/sync/completed_workout_delivery.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/timer_panel.dart';
import 'package:gymmane/widgets/ui_kit.dart';

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
    fit.saveAndExit();
    fit.sessions.clear();
    fit.routines.clear();
    fit.onboarded = true;
    fit.logRpe = true;
    fit.demoSize = 'off';
    fit.gamification = false;
    fit.autoAdvance = false;
    await fit.persistNow();
  });
  tearDown(() => fit.saveAndExit());

  Future<void> screen(WidgetTester tester, Size size, double scale, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 44, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: fit,
            builder: (_, _) => child is SessionScreen ? SessionScreen() : child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('app respects the system 200 percent text setting', (tester) async {
    fit.onboarded = false;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const GymManeApp());
    expect(MediaQuery.textScalerOf(tester.element(find.text('GymMane').first)).scale(16), 32);
  });

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    for (final scale in [1.0, 2.0]) {
      for (final layout in ['cards', 'list']) {
        testWidgets('$size ${scale}x $layout logging, rest, keyboard and completion', (tester) async {
          await tester.runAsync(() async {
            fit.sessionLayout = layout;
            fit.sessions.add(
              LoggedSession(DateTime(2026, 10, 20), 120, [
                LoggedExercise('EIeI8Vf', 'Barbell Bench Press', 'chest', [LoggedSet(10, 60)]),
              ]),
            );
            final id = fit.createRoutine('iPhone');
            fit.toggleRoutineExercise(id, 'EIeI8Vf');
            fit.startRoutine(fit.routines.first);
            fit.endCountdown();
            await screen(tester, size, scale, const SessionScreen());
            expect(tester.takeException(), isNull);

            for (final label in [
              t.setType,
              'RPE',
              if (layout == 'cards') ...[t.increase, t.decrease],
            ]) {
              final controls = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
              expect(controls, findsWidgets);
              for (final element in controls.evaluate()) {
                final target = tester.getSize(find.byWidget(element.widget));
                expect(target.width, greaterThanOrEqualTo(44), reason: label);
                expect(target.height, greaterThanOrEqualTo(44), reason: label);
              }
            }

            // Check actual rendered hit regions, including the compact list layout.
            final mark = find.bySemanticsLabel('Mark set 1');
            final done = mark.evaluate().isNotEmpty
                ? mark
                : find.byWidgetPredicate((w) => w is Semantics && w.properties.checked != null).first;
            await tester.ensureVisible(done);
            final hit = tester.getSize(done);
            expect(hit.width, greaterThanOrEqualTo(44));
            expect(hit.height, greaterThanOrEqualTo(44));
            await tester.tap(done);
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
            expect(fit.session!.exercises.first.sets.first.done, isTrue);

            // Model the software keyboard while the workout and rest timer are on screen.
            tester.view.viewInsets = FakeViewPadding(bottom: 220);
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            tester.view.resetViewInsets();
            addTearDown(tester.view.resetViewInsets);
            // A later unrelated workout must never select the export destination.
            final unrelated = LoggedSession(DateTime.now().add(const Duration(days: 1)), 60, [
              LoggedExercise('EIeI8Vf', 'Barbell Bench Press', 'chest', [LoggedSet(5, 40)]),
            ]);
            fit.sessions.add(unrelated);
            final finishing = fit.finishSession();
            expect(await finishing, isTrue);
            await tester.pump(const Duration(milliseconds: 500));
            expect(fit.isSessionFinishing, isFalse);
            expect(tester.takeException(), isNull);
            expect(find.byType(CompletedWorkoutDelivery), findsOneWidget);
            expect(find.byKey(ValueKey('delivery-${fit.session!.workoutId}')), findsOneWidget);
            expect(fit.sessions.last.id, unrelated.id);
            await tester.pumpWidget(const SizedBox.shrink());
          });
        });
      }
    }
  }

  testWidgets('rest adjustment targets remain 44 points at 200 percent', (tester) async {
    var remaining = 90;
    await screen(
      tester,
      const Size(320, 568),
      2,
      SingleChildScrollView(
        child: TimerPanel(
          label: 'Resting',
          remaining: remaining,
          total: 90,
          elapsed: '10:30',
          elapsedLabel: 'Elapsed',
          sets: '1/3',
          setsLabel: 'Sets',
          hint: 'Tap to change',
          onTap: () {},
          onMinus: () => remaining -= 15,
          onPlus: () => remaining += 15,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final label in ['−15', '+15']) {
      final target = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
      expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    }
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '+15'));
    expect(remaining, 105);
  });

  for (final mode in ['time', 'cardio']) {
    testWidgets('inline list $mode timer can pause, resume, cancel and finish early', (tester) async {
      await tester.runAsync(() async {
        fit.sessionLayout = 'list';
        final movement = fit.addCustomExercise(
          name: 'Inline $mode',
          primary: 'quads',
          equipment: 'Bodyweight',
          mode: mode,
        );
        final id = fit.createRoutine('Inline timer');
        fit.toggleRoutineExercise(id, 'EIeI8Vf');
        fit.toggleRoutineExercise(id, movement);
        fit.setRoutineSetCount(id, movement, 2);
        fit.startRoutine(fit.routines.first);
        fit.endCountdown();
        fit.setSessionSeconds(1, 0, 1200);
        await screen(tester, const Size(320, 568), 2, const SessionScreen());

        Finder control(String label) =>
            find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
        await tester.ensureVisible(control(t.holdLabel).first);
        await tester.tap(control(t.holdLabel).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(control(t.stopLabel));
        await tester.tap(control(t.stopLabel));
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holding, isFalse);
        expect(fit.session!.exercises[1].sets.first.done, isFalse);

        await tester.ensureVisible(control(t.holdLabel).last);
        await tester.tap(control(t.holdLabel).last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holdEx, 1);
        expect(fit.holdSet, 1);
        await tester.ensureVisible(find.byType(TimerPanel));
        await tester.tap(find.byType(TimerPanel));
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holdPaused, isTrue);
        await tester.tap(find.byType(TimerPanel));
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holdPaused, isFalse);

        // Advance the production clock's timestamps without a real five-minute wait.
        final started = DateTime.now().subtract(const Duration(seconds: 300));
        fit.holdStartsAt = started;
        fit.holdEndsAt = started.add(const Duration(seconds: 1200));
        await tester.tap(find.byType(TimerPanel));
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holdPaused, isTrue);
        final finish = find.widgetWithText(PrimaryButton, t.finishHoldNow);
        expect(finish, findsOneWidget);
        await tester.ensureVisible(finish);
        expect(tester.getSize(finish).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(finish).height, greaterThanOrEqualTo(44));
        await tester.tap(finish);
        await tester.pump(const Duration(milliseconds: 300));
        expect(fit.holding, isFalse);
        expect(fit.session!.exercises.first.sets.every((s) => !s.done), isTrue);
        expect(fit.session!.exercises[1].sets.first.done, isFalse);
        final completed = fit.session!.exercises[1].sets[1];
        expect(completed.done, isTrue);
        expect(completed.sec, mode == 'cardio' ? inInclusiveRange(299, 301) : 1200);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  }

  testWidgets('logging opens numeric entry with the keyboard at 200 percent', (tester) async {
    await tester.runAsync(() async {
      fit.sessionLayout = 'cards';
      final id = fit.createRoutine('Numeric entry');
      fit.toggleRoutineExercise(id, 'EIeI8Vf');
      fit.startRoutine(fit.routines.first);
      fit.endCountdown();
      await screen(tester, const Size(320, 568), 2, const SessionScreen());
      final value = find.text('${fit.session!.exercises.first.sets.first.reps}').first;
      await tester.ensureVisible(value);
      await tester.tap(value);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(PhosphorIconsRegular.keyboard));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.widgetWithText(TextButton, titleCase(t.set)));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text(titleCase(t.set)));
      await tester.pumpAndSettle();
      expect(fit.session!.exercises.first.sets.first.reps, 12);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('missing routine warning keeps the current workout and offers repair', (tester) async {
    await tester.runAsync(() async {
      final id = fit.createRoutine('Current');
      fit.toggleRoutineExercise(id, 'EIeI8Vf');
      fit.startRoutine(fit.routines.first);
      fit.endCountdown();
      final current = fit.session;
      const portable = Exercise(
        id: 'custom:repair-known',
        name: 'Portable known movement',
        primary: 'quads',
        secondary: [],
        equipment: 'Bodyweight',
        difficulty: 'Beginner',
        art: '',
        steps: [],
      );
      final broken = Routine(
        'missing-routine',
        'Needs repair',
        ['EIeI8Vf', 'missing-exercise', portable.id],
        exerciseDefinitions: {portable.id: portable},
      );
      broken.sets['EIeI8Vf'] = 2;
      broken.plan['EIeI8Vf'] = [const PlannedSet(reps: 8, weightKg: 40)];
      broken.rest['EIeI8Vf'] = 75;
      fit.routines.add(broken);
      expect(fit.routineExercises(broken), isEmpty);
      final currentSnapshot = current!.toJson();
      await tester.pumpWidget(const GymManeApp());
      await tester.pump(const Duration(milliseconds: 500));
      fit.startRoutine(broken);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(identical(fit.session, current), isTrue);
      expect(find.text(t.routineMissingExercisesTitle), findsOneWidget);
      expect(find.text(t.routineMissingExercisesMessage(1)), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, t.editEntry));
      await tester.pumpAndSettle();
      expect(fit.route, 'routine-edit');
      expect(fit.activeRoutineId, broken.id);
      expect(identical(fit.session, current), isTrue);
      expect(fit.session!.toJson(), currentSnapshot);
      expect(broken.exerciseIds, ['EIeI8Vf', 'missing-exercise', portable.id]);
      final remove = find.byKey(const ValueKey('remove-missing-missing-exercise'));
      expect(remove, findsOneWidget);
      await tester.ensureVisible(remove);
      expect(tester.getSize(remove).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(broken.exerciseIds, ['EIeI8Vf', portable.id]);
      expect(broken.exerciseDefinitions, {portable.id: portable});
      expect(broken.sets['EIeI8Vf'], 2);
      expect(broken.plan['EIeI8Vf']!.single.reps, 8);
      expect(broken.plan['EIeI8Vf']!.single.weightKg, 40);
      expect(broken.rest['EIeI8Vf'], 75);
      expect(fit.missingRoutineExerciseIds(broken), isEmpty);
      expect(find.text('Portable known movement'), findsWidgets);
      expect(identical(fit.session, current), isTrue);
      expect(fit.session!.toJson(), currentSnapshot);
      await tester.tap(find.byWidgetPredicate((w) => w is PrimaryButton && w.label == t.startWorkout));
      await tester.pump(const Duration(milliseconds: 500));
      // Start keeps the existing parked-workout protection and resumes it.
      expect(fit.route, 'session');
      expect(identical(fit.session, current), isTrue);
      expect(fit.session!.toJson(), currentSnapshot);
      // Intentionally finish and leave that workout before choosing a new start.
      fit.toggleSet(0, 0);
      expect(await fit.finishSession(), isTrue);
      final savedCurrentId = fit.session!.workoutId;
      fit.saveAndExit();
      fit.openRoutine(broken.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is PrimaryButton && w.label == t.startWorkout));
      await tester.pump(const Duration(milliseconds: 500));
      expect(identical(fit.session, current), isFalse);
      expect(fit.session!.routineId, broken.id);
      expect(fit.session!.exercises.map((e) => e.id), ['EIeI8Vf', portable.id]);
      expect(fit.sessions.single.id, savedCurrentId);
      expect(find.text(t.routineMissingExercisesTitle), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('rest editor remains scrollable on the small iPhone at 200 percent', (tester) async {
    await tester.runAsync(() async {
      fit.sessionLayout = 'cards';
      final id = fit.createRoutine('Rest edit');
      fit.toggleRoutineExercise(id, 'EIeI8Vf');
      fit.startRoutine(fit.routines.first);
      fit.endCountdown();
      fit.toggleSet(0, 0);
      await screen(tester, const Size(320, 568), 2, const SessionScreen());
      expect(find.byType(TimerPanel), findsOneWidget);
      await tester.ensureVisible(find.byType(TimerPanel));
      await tester.tap(find.byType(TimerPanel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(t.liveSkipRest));
      await tester.tap(find.text(t.liveSkipRest));
      await tester.pumpAndSettle();
      expect(fit.session!.restRemaining, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
