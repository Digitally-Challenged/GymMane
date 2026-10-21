import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:gymmane/services/media_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:gymmane/services/persistence/sync_repository.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryBackend implements StorageBackend {
  Map<String, dynamic>? value;
  bool reject = false;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> data) async {
    if (reject) throw StateError('disk full');
    value = jsonDecode(jsonEncode(data));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an unrelated stale save must not acknowledge unseen remote revisions', () async {
    final repo = SyncRepository(MemoryBackend());
    await repo.initialize({});
    await repo.selectNamespace('alice');
    final row = LoggedSession(DateTime.utc(2026), 120, [], name: 'Original').toJson();
    Map<String, dynamic> remote(String name, int rev) => {
      'entityType': 'workout',
      'entityId': row['id'],
      'revision': rev,
      'deleted': false,
      'payload': {...row, 'n': name},
      'cursor': '$rev',
    };
    await repo.applyPullPage('alice', [remote('Original', 1)], '1');
    final shown = repo.load();
    await repo.applyPullPage('alice', [remote('Remote', 2)], '2');
    await repo.save({...shown, 'units': 'lb'});
    await repo.save({
      ...shown,
      'sessions': [
        {...row, 'n': 'Local edit'},
      ],
    });
    expect(repo.conflicts('alice'), isNotEmpty, reason: 'unseen revision 2 must remain an explicit conflict');
  });
  test('JSON import must not report success when commit fails', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = MemoryBackend();
    Store.backendFactory = (_) async => backend;
    await Store.instance.init();
    fit.loadFromStore();
    await fit.persistNow(rethrowErrors: true);
    final before = Store.instance.load();
    backend.reject = true;
    final success = await fit.importJson(
      jsonEncode({
        ...fit.toJson(),
        'profile': {'name': 'Replacement'},
      }),
    );
    await fit.persistNow();
    expect(Store.instance.load(), before);
    expect(success, isFalse, reason: 'UI currently displays backupImported on true');
  });
  test('resetting Bob must retain media referenced by Alice', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = MemoryBackend();
    Store.backendFactory = (_) async => backend;
    await Store.instance.init();
    final dir = await Directory.systemTemp.createTemp('gymmane_account_review');
    MediaStore.directory = dir.path;
    try {
      final repo = Store.instance.repository;
      await repo.selectNamespace('alice');
      fit.loadFromStore();
      final image = await MediaStore.saveBytes('alice', 'png', Uint8List.fromList([1, 2, 3]));
      fit.exerciseMedia['private-exercise'] = image!;
      await fit.persistNow(rethrowErrors: true);
      await repo.selectNamespace('bob');
      fit.loadFromStore();
      fit.resetAllData();
      await fit.persistNow(rethrowErrors: true);
      await repo.selectNamespace('alice');
      fit.loadFromStore();
      expect(fit.exerciseMedia['private-exercise'], image);
      expect(await MediaStore.readBytes(image), isNotNull, reason: 'Bob reset erased Alice media');
    } finally {
      MediaStore.directory = null;
      await dir.delete(recursive: true);
    }
  });
}
