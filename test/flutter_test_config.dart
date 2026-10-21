import 'dart:async';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Store.backendFactory = (prefs) async => PreferencesBackend(prefs);
  await testMain();
}
