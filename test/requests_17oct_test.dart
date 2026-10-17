import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.onboarded = true;
  });

  Routine routineOf(List<String> ids) {
    final id = fit.createRoutine('Core');
    for (final ex in ids) {
      fit.toggleRoutineExercise(id, ex);
    }
    return fit.routines.firstWhere((r) => r.id == id);
  }

  Future<void> endSide() async {
    final past = DateTime.now().subtract(const Duration(milliseconds: 50));
    fit.holdStartsAt = past.subtract(Duration(seconds: fit.holdTotal));
    fit.holdEndsAt = past;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  group('#213 cada lado', () {
    test('la plancha lateral viene por lados y se puede quitar y volver a poner', () async {
      expect(fit.isEachSide('side-plank-hold'), isTrue);
      expect(fit.isEachSide('plank-hold'), isFalse);
      fit.toggleEachSide('side-plank-hold');
      fit.toggleEachSide('plank-hold');
      expect(fit.isEachSide('side-plank-hold'), isFalse);
      expect(fit.isEachSide('plank-hold'), isTrue);

      fit.persistNow();
      fit.eachSide.clear();
      fit.eachSideOff.clear();
      fit.loadFromStore();
      expect(fit.isEachSide('side-plank-hold'), isFalse);
      expect(fit.isEachSide('plank-hold'), isTrue);

      fit.toggleEachSide('side-plank-hold');
      expect(fit.eachSideOff, isNot(contains('side-plank-hold')));
      expect(fit.eachSide, isNot(contains('side-plank-hold')));
    });

    test('solo cuenta en ejercicios por tiempo', () {
      fit.setExerciseMode('side-plank-hold', 'weight');
      expect(fit.isEachSide('side-plank-hold'), isFalse);
      fit.setExerciseMode('side-plank-hold', 'time');
      expect(fit.isEachSide('side-plank-hold'), isTrue);
    });

    test('corre un lado, avisa de cambiar y descansa solo tras el segundo', () async {
      fit.startRoutine(routineOf(['side-plank-hold']));
      fit.endCountdown();
      final set = fit.session!.exercises.first.sets.first;
      fit.startHold(0, 0);
      expect(fit.holdSides, 2);
      expect(fit.holdLength('side-plank-hold', 30), '0:30 × 2');

      await endSide();
      expect(fit.holding, isTrue);
      expect(fit.holdSide, 1);
      expect(fit.switchingSides, isTrue);
      expect(set.done, isFalse);
      expect(fit.session!.restRemaining, isNull);

      await endSide();
      expect(fit.holding, isFalse);
      expect(set.done, isTrue);
      expect(fit.session!.restRemaining, isNotNull);
      fit.skipRest();
    });

    test('un aguante normal sigue siendo de una vez', () async {
      fit.startRoutine(routineOf(['plank-hold']));
      fit.endCountdown();
      fit.startHold(0, 0);
      expect(fit.holdSides, 1);
      await endSide();
      expect(fit.holding, isFalse);
      expect(fit.session!.exercises.first.sets.first.done, isTrue);
      fit.skipRest();
    });

    test('pararlo deja todo como al principio', () {
      fit.startRoutine(routineOf(['side-plank-hold']));
      fit.endCountdown();
      fit.startHold(0, 0);
      fit.stopHold();
      expect(fit.holdSide, 0);
      expect(fit.holdSides, 1);
      expect(fit.session!.exercises.first.sets.first.done, isFalse);
    });
  });

  group('#204 descanso a mano', () {
    void rest() {
      final bench = fit.matchExerciseByName('Bench Press')!.id;
      fit.startRoutine(routineOf([bench]));
      fit.endCountdown();
      fit.toggleSet(0, 0);
      expect(fit.session!.restRemaining, isNotNull);
    }

    test('fija el descanso al tiempo elegido', () {
      rest();
      fit.setRest(200);
      expect(fit.restTotal, 200);
      expect(fit.session!.restRemaining, inInclusiveRange(199, 200));
      fit.skipRest();
    });

    test('cero lo salta y el tope es de diez minutos', () {
      rest();
      fit.setRest(5000);
      expect(fit.session!.restRemaining, inInclusiveRange(599, 600));
      fit.setRest(0);
      expect(fit.session!.restRemaining, isNull);
    });

    test('con la sesión en pausa se queda congelado en el tiempo nuevo', () {
      rest();
      fit.toggleSessionPause();
      fit.setRest(90);
      expect(fit.session!.restFrozen, 90);
      expect(fit.session!.restRemaining, 90);
      fit.toggleSessionPause();
      expect(fit.session!.restRemaining, inInclusiveRange(89, 90));
      fit.skipRest();
    });
  });

  group('#206 fotos tapadas en Progreso', () {
    test('se recuerda al reiniciar', () {
      expect(fit.hideShots, isFalse);
      fit.toggleHideShots();
      fit.persistNow();
      fit.hideShots = false;
      fit.loadFromStore();
      expect(fit.hideShots, isTrue);
      fit.resetAllData();
      expect(fit.hideShots, isFalse);
    });
  });
}
