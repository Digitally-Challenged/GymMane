import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/backup_zip.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/media_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup round-trips history, effort and a live workout without filesystem storage', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    MediaStore.directory = null;
    fit.resetAllData();
    fit.setLanguage('en');
    final ex = fit.matchExerciseByName('Barbell Bench Press')!;
    fit.sessions.add(
      LoggedSession(DateTime(2026, 10, 18), 1800, [
        LoggedExercise(ex.id, ex.name, ex.primary, [LoggedSet(8, 60, rpe: 7)]),
      ]),
    );
    final routineId = fit.createRoutine('Browser trial');
    fit.toggleRoutineExercise(routineId, ex.id);
    fit.startRoutine(fit.routines.firstWhere((r) => r.id == routineId));
    fit.setSessionWeight(0, 0, 62.5);
    final bytes = await buildBackupZip();
    fit.resetAllData();
    expect(await restoreBackupZip(bytes), isTrue);
    expect(fit.sessions.single.exercises.single.sets.single.rpe, 7);
    expect(fit.session!.exercises.single.sets.first.weight, 62.5);
    await Store.instance.save(fit.toJson());
    fit.sessions.clear();
    fit.loadFromStore();
    expect(fit.sessions.single.exercises.single.sets.single.weight, 60);
    expect(fit.session!.exercises.single.sets.first.weight, 62.5);
  });
}
