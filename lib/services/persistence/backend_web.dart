import 'package:shared_preferences/shared_preferences.dart';
import 'storage_backend.dart';

Future<StorageBackend> openStorageBackend(SharedPreferences prefs) async => PreferencesBackend(prefs);
