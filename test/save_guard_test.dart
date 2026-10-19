import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/widgets/save_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save warning stays accessible until a successful retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    final platform = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _FailingStore();
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: SaveStatus(child: Scaffold(body: Text('Workout'))),
      ),
    );
    await Store.instance.save({'unsaved': true});
    await tester.pump();
    expect(find.bySemanticsLabel(t.localSaveFailed), findsOneWidget);
    SharedPreferencesStorePlatform.instance = platform;
    await Store.instance.save({'saved': true});
    await tester.pump();
    expect(find.text(t.localSaveFailed), findsNothing);
    semantics.dispose();
  });

  test('failed writes stay visible until a successful retry', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    final platform = SharedPreferencesStorePlatform.instance;
    final failing = _FailingStore();
    SharedPreferencesStorePlatform.instance = failing;
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);

    await Store.instance.save({'name': 'unsaved'});
    expect(Store.instance.saveFailed.value, isTrue);
    failing.throws = true;
    await Store.instance.save({'name': 'still unsaved'});
    expect(Store.instance.saveFailed.value, isTrue);

    SharedPreferencesStorePlatform.instance = platform;
    await Store.instance.save({'name': 'saved'});
    expect(Store.instance.saveFailed.value, isFalse);
    expect(await platform.getAll(), containsPair('flutter.gymmane_v1', '{"name":"saved"}'));
  });

  test('un número roto no impide guardar lo demás', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.profile.weightKg = double.nan;
    final id = fit.addCustomExercise(name: 'Mi press', primary: 'chest', equipment: 'Dumbbell');
    await Store.instance.save(fit.toJson());

    fit.customExercises.clear();
    fit.loadFromStore();
    expect(fit.customExercises.map((e) => e.id), [id]);
  });
}

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();

  bool throws = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throws) throw StateError('storage unavailable');
    return false;
  }
}
