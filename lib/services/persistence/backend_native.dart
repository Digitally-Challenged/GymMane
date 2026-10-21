import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'storage_backend.dart';

Future<StorageBackend> openStorageBackend(SharedPreferences prefs) async =>
    SqliteBackend.open('${await getDatabasesPath()}/gymmane.db');

class SqliteBackend implements StorageBackend {
  SqliteBackend(this.database);
  final Database database;
  static Future<SqliteBackend> open(String path, {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE repository (id INTEGER PRIMARY KEY CHECK(id = 1), snapshot TEXT NOT NULL)',
          );
        },
      ),
    );
    return SqliteBackend(db);
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final rows = await database.query('repository', where: 'id = 1');
    return rows.isEmpty ? null : jsonDecode(rows.single['snapshot'] as String) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    final encoded = jsonEncode(snapshot);
    // Entity revisions, outbox, conflicts, document and pull cursor share the
    // same SQLite transaction. No observer can see a partial commit.
    await database.transaction((txn) async {
      await txn.insert('repository', {
        'id': 1,
        'snapshot': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
