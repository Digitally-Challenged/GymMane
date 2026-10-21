import 'dart:convert';
import '../../models/identity.dart';
import '../migration/identity_migration.dart';
import 'storage_backend.dart';
import 'health_delivery_registry.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Single writer for local documents and the account-scoped synchronization ledger.
/// Returned values are copies; failed transactions never publish memory changes.
class SyncRepository {
  SyncRepository(this.backend);
  final StorageBackend backend;
  Map<String, dynamic> _root = {'version': 1, 'active': 'guest', 'namespaces': <String, dynamic>{}};
  Future<void> _tail = Future.value();
  final Map<String, Map<String, dynamic>> _presented = {};
  final Map<String, Map<String, int>> _presentedRevisions = {};
  String get namespace => _root['active'] as String;
  Future<void> get flushed => _tail;

  Future<void> initialize(Map<String, dynamic> legacy) async {
    final saved = await backend.read();
    if (saved != null) {
      if (saved['version'] != 1 || saved['namespaces'] is! Map || saved['active'] is! String) {
        throw const FormatException('Unsupported or corrupt local repository');
      }
      _root = _copy(saved);
      // Eagerly validate documents; never replace a corrupt repository with empty data.
      for (final value in (_root['namespaces'] as Map).values) {
        migrateIdentities(Map<String, dynamic>.from(value['document'] as Map));
      }
      return;
    }
    final migrated = migrateIdentities(legacy);
    await _transaction((root) {
      final ns = _space(root, 'guest');
      ns['document'] = migrated;
      _recordChanges(ns, <String, dynamic>{}, migrated, enqueue: false);
    });
    final verified = await backend.read();
    if (jsonEncode(verified) != jsonEncode(_root)) throw StateError('Migration verification failed');
  }

  static Map<String, dynamic> _space(Map<String, dynamic> root, String name) {
    if (name.isEmpty) throw ArgumentError.value(name, 'namespace');
    final spaces = root['namespaces'] as Map<String, dynamic>;
    return (spaces[name] ??= <String, dynamic>{
          'document': <String, dynamic>{},
          'entities': <String, dynamic>{},
          'outbox': <dynamic>[],
          'conflicts': <String, dynamic>{},
          'cursor': '0',
        })
        as Map<String, dynamic>;
  }

  Map<String, dynamic> load() {
    final document = _copy(_space(_root, namespace)['document'] as Map<String, dynamic>);
    _presented[namespace] = _copy(document);
    _presentedRevisions[namespace] = _revisions(namespace);
    return document;
  }

  Map<String, int> _revisions(String account) => {
    for (final e in (_space(_root, account)['entities'] as Map<String, dynamic>).entries)
      e.key: (e.value['revision'] as int?) ?? 0,
  };
  String cursor(String account) => _space(_root, account)['cursor'] as String;
  Map<String, dynamic> conflicts(String account) =>
      _copy(_space(_root, account)['conflicts'] as Map<String, dynamic>);

  List<Map<String, dynamic>> exportableWorkouts(String account) {
    final ns = _space(_root, account);
    return [
      for (final entry in (ns['entities'] as Map<String, dynamic>).entries)
        if (entry.value['entityType'] == 'workout' &&
            entry.value['deleted'] != true &&
            entry.value['payload']?['origin'] == 'gymmane' &&
            !(ns['conflicts'] as Map).containsKey(entry.key))
          {
            ..._copy(entry.value as Map<String, dynamic>),
            'pending': (ns['outbox'] as List).any((op) => _key(op) == entry.key),
          },
    ];
  }

  /// File stores are shared on disk. Never reclaim names still referenced by
  /// another account document (including legacy JSON imports with shared names).
  Set<String> fileNamesOutsideActiveNamespace() {
    final names = <String>{};
    void collect(Object? value) {
      if (value is String) names.add(value);
      if (value is Map) value.values.forEach(collect);
      if (value is List) value.forEach(collect);
    }

    for (final entry in (_root['namespaces'] as Map<String, dynamic>).entries) {
      if (entry.key != namespace) collect(entry.value['document']);
    }
    return names;
  }

  Map<String, dynamic> deliveryLedger(String account, String destination) {
    final ledger = _copy(((_space(_root, account)['deliveries'] as Map?)?[destination] as Map<String, dynamic>?) ?? {});
    return destination == 'healthkit' ? readHealthDelivery(_root, account, ledger) : ledger;
  }

  Future<void> saveDeliveryLedger(String account, String destination, Map<String, dynamic> ledger) {
    final snapshot = _copy(ledger);
    return _transaction((root) {
      final ns = _space(root, account);
      if (destination == 'healthkit') {
        writeHealthDelivery(root, account, snapshot);
      } else {
        (ns['deliveries'] ??= <String, dynamic>{})[destination] = snapshot;
      }
    });
  }

  /// Device-local metadata is neither exported in backups nor sent in payloads.
  Map<String, dynamic>? entityMetadata(String account, String entityType, String entityId) {
    final row = (_space(_root, account)['entities'] as Map)['$entityType:$entityId'];
    return row == null ? null : _copy(row as Map<String, dynamic>);
  }

  Future<void> _transaction(void Function(Map<String, dynamic>) change) {
    final operation = _tail.then((_) async {
      final next = _copy(_root);
      change(next);
      await backend.write(next);
      _root = next;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(Map<String, dynamic> document, {bool replace = false}) {
    final snapshot = migrateIdentities(document);
    final account = namespace;
    return _transaction((root) {
      final ns = _space(root, account);
      final baseline = _copy(_presented[account] ?? ns['document'] as Map<String, dynamic>);
      final revisions = Map<String, int>.from(_presentedRevisions[account] ?? _revisions(account));
      final current = ns['document'] as Map<String, dynamic>;
      final merged = _copy(snapshot);
      if (!replace) {
        final before = _entities(baseline), after = _entities(snapshot);
        for (final pair in [('workout', 'sessions'), ('routine', 'routines')]) {
          final rows = <String, dynamic>{
            for (final row in (current[pair.$2] as List?) ?? []) row['id'] as String: row,
          };
          for (final key in {...before.keys, ...after.keys}.where((k) => k.startsWith('${pair.$1}:'))) {
            if (jsonEncode(before[key]) == jsonEncode(after[key])) continue;
            final entity = after[key] ?? before[key]!;
            if (after.containsKey(key)) {
              rows[entity['entityId'] as String] = entity['payload'];
            } else {
              rows.remove(entity['entityId']);
            }
          }
          if (snapshot.containsKey(pair.$2) || rows.isNotEmpty) merged[pair.$2] = rows.values.toList();
        }
      }
      final oldEntities = _entities(baseline), localEntities = _entities(snapshot);
      for (final key in {...oldEntities.keys, ...localEntities.keys}) {
        if (jsonEncode(oldEntities[key]) == jsonEncode(localEntities[key])) continue;
        final remote = (ns['entities'] as Map)[key] as Map<String, dynamic>?;
        if (!replace &&
            remote != null &&
            (remote['revision'] as int) > (revisions[key] ?? 0) &&
            jsonEncode(_entities(current)[key]) != jsonEncode(localEntities[key])) {
          (ns['conflicts'] as Map)[key] = _copy(remote);
        }
      }
      _recordChanges(ns, current, merged, enqueue: account != 'guest');
      ns['document'] = merged;
    }).then((_) {
      _presented[account] = snapshot;
      final shown = _entities(snapshot);
      final committed = _entities(_space(_root, account)['document'] as Map<String, dynamic>);
      final revisions = _revisions(account);
      final previous = _presentedRevisions[account] ?? {};
      _presentedRevisions[account] = {
        for (final key in shown.keys)
          key: jsonEncode(shown[key]) == jsonEncode(committed[key])
              ? (revisions[key] ?? 0)
              : (previous[key] ?? 0),
      };
    });
  }

  Future<void> selectNamespace(String account) => _transaction((root) {
    final fresh = !(root['namespaces'] as Map).containsKey(account);
    final ns = _space(root, account);
    if (fresh && account != 'guest') {
      final guest = _space(root, 'guest')['document'] as Map;
      final preferences = <String, dynamic>{
        for (final key in [
          'theme',
          'units',
          'language',
          'rest',
          'bg',
          'heatTone',
          'layout',
          'weekStart',
          'stepKg',
          'stepLb',
          'demo',
          'demoLoop',
          'bgDim',
        ])
          if (guest.containsKey(key)) key: guest[key],
      };
      ns['document'] = preferences;
    }
    root['active'] = account;
  });

  /// Explicit consent boundary: switching accounts alone never adopts guest history.
  Future<void> adoptGuest(String account) => _transaction((root) {
    if (account == 'guest') throw ArgumentError('An account namespace is required');
    final ns = _space(root, account);
    final document = _copy(ns['document'] as Map<String, dynamic>);
    final guest = _space(root, 'guest')['document'] as Map<String, dynamic>;
    for (final field in ['sessions', 'routines']) {
      final rows = (document[field] as List?) ?? <dynamic>[];
      final ids = rows.map((r) => r['id']).toSet();
      document[field] = [
        ...rows,
        for (final row in (guest[field] as List?) ?? [])
          if (ids.add(row['id'])) row,
      ];
    }
    _recordChanges(ns, ns['document'] as Map<String, dynamic>, document, enqueue: true);
    ns['document'] = document;
    transferGuestHealthDelivery(root, account, {
      for (final row in (guest['sessions'] as List?) ?? []) row['id'] as String,
    });
  });

  /// Includes queued operations blocked by an unresolved conflict.
  int pendingCount(String account) => (_space(_root, account)['outbox'] as List).length;

  Map<String, int> guestCounts() {
    final guest = _space(_root, 'guest')['document'] as Map;
    return {
      'workouts': (guest['sessions'] as List?)?.length ?? 0,
      'routines': (guest['routines'] as List?)?.length ?? 0,
    };
  }

  Future<void> resolveConflict(
    String account,
    String entityType,
    String entityId, {
    required bool keepLocal,
  }) => _transaction((root) {
    final ns = _space(root, account);
    final key = '$entityType:$entityId';
    final remote = (ns['conflicts'] as Map).remove(key) as Map<String, dynamic>?;
    if (remote == null) return;
    final outbox = ns['outbox'] as List;
    outbox.removeWhere((op) => _key(op) == key);
    if (keepLocal) {
      final local = (ns['entities'] as Map)[key] as Map<String, dynamic>;
      local['revision'] = remote['revision'];
      outbox.add({
        'operationId': newEntityId(),
        'entityType': entityType,
        'entityId': entityId,
        'baseRevision': remote['revision'],
        'deleted': local['deleted'],
        'payload': local['payload'],
      });
    } else {
      final previous = (ns['entities'] as Map)[key] as Map?;
      (ns['entities'] as Map)[key] = {
        ...remote,
        'origin': previous?['origin'] ?? 'remote',
        'localRevision': ((previous?['localRevision'] as int?) ?? 0) + 1,
      };
      final document = ns['document'] as Map;
      final field = entityType == 'workout' ? 'sessions' : 'routines';
      final rows = (document[field] ??= <dynamic>[]) as List;
      rows.removeWhere((row) => row['id'] == entityId);
      if (remote['deleted'] != true) rows.add(remote['payload']);
    }
  });

  static Map<String, Map<String, dynamic>> _entities(Map<String, dynamic> document) => {
    for (final pair in [('workout', 'sessions'), ('routine', 'routines')])
      for (final row in (document[pair.$2] as List?) ?? [])
        '${pair.$1}:${row['id']}': {
          'entityType': pair.$1,
          'entityId': row['id'],
          'payload': row,
          'deleted': false,
        },
  };

  static void _recordChanges(
    Map<String, dynamic> ns,
    Map<String, dynamic> before,
    Map<String, dynamic> after, {
    required bool enqueue,
  }) {
    final old = _entities(before), next = _entities(after);
    final ledger = ns['entities'] as Map<String, dynamic>;
    final outbox = ns['outbox'] as List;
    for (final key in {...old.keys, ...next.keys}) {
      if (jsonEncode(old[key]) == jsonEncode(next[key])) continue;
      final entity = next[key] ?? {...old[key]!, 'payload': null, 'deleted': true};
      final revision = (ledger[key] as Map?)?['revision'] ?? 0;
      final previous = ledger[key] as Map?;
      ledger[key] = {
        ...entity,
        'revision': revision,
        'origin': previous?['origin'] ?? 'local',
        'localRevision': ((previous?['localRevision'] as int?) ?? 0) + 1,
      };
      if (enqueue) outbox.add({...entity, 'baseRevision': revision, 'operationId': newEntityId()});
    }
  }

  /// At most one operation per entity is in flight; later edits wait for its receipt.
  Future<List<Map<String, dynamic>>> pendingOperations(String account) async {
    await flushed;
    final ns = _space(_root, account);
    final seen = <String>{};
    final conflicts = ns['conflicts'] as Map;
    return [
      for (final op in ns['outbox'] as List)
        if (!conflicts.containsKey(_key(op)) && seen.add(_key(op))) _copy(op as Map<String, dynamic>),
    ].take(100).toList();
  }

  static String _key(Map value) => '${value['entityType']}:${value['entityId']}';

  static void _validateEntity(Map<String, dynamic> entity) {
    final type = entity['entityType'];
    if (!['workout', 'routine'].contains(type) ||
        !isEntityId(entity['entityId']) ||
        entity['revision'] is! int ||
        (entity['revision'] as int) <= 0 ||
        entity['deleted'] is! bool ||
        entity['cursor'] is! String ||
        !RegExp(r'^\d+$').hasMatch(entity['cursor'] as String)) {
      throw const FormatException('Invalid remote entity');
    }
    if (entity['deleted'] == true) {
      if (entity['payload'] != null) throw const FormatException('Invalid tombstone');
    } else {
      final payload = entity['payload'];
      if (payload is! Map<String, dynamic> || payload['id'] != entity['entityId']) {
        throw const FormatException('Invalid remote identity');
      }
      migrateIdentities({
        type == 'workout' ? 'sessions' : 'routines': [payload],
      });
    }
  }

  Future<void> applyPushResults(String account, List<Map<String, dynamic>> results) {
    final snapshot = results.map(_copy).toList();
    return _transaction((root) {
      final ns = _space(root, account);
      final outbox = ns['outbox'] as List;
      for (final result in snapshot) {
        final index = outbox.indexWhere((op) => op['operationId'] == result['operationId']);
        if (index < 0) continue; // Already committed receipt.
        final op = outbox[index] as Map;
        final entity = Map<String, dynamic>.from(result['entity'] as Map);
        _validateEntity(entity);
        final key = _key(entity);
        if (key != _key(op)) throw const FormatException('Receipt identity mismatch');
        if (result['status'] == 'conflict') {
          (ns['conflicts'] as Map)[key] = entity;
        } else if (result['status'] == 'accepted') {
          outbox.removeAt(index);
          (ns['entities'] as Map)[key]['revision'] = entity['revision'];
          for (final queued in outbox.where((row) => _key(row) == key)) {
            queued['baseRevision'] = entity['revision'];
          }
        } else {
          throw const FormatException('Invalid push result');
        }
      }
    });
  }

  Future<void> applyPullPage(String account, List<Map<String, dynamic>> entities, String nextCursor) {
    if (!RegExp(r'^\d+$').hasMatch(nextCursor)) throw const FormatException('Invalid cursor');
    final snapshot = entities.map(_copy).toList();
    return _transaction((root) {
      final ns = _space(root, account);
      if (BigInt.parse(nextCursor) < BigInt.parse(ns['cursor'] as String)) {
        throw const FormatException('Cursor regression');
      }
      for (final entity in snapshot) {
        _validateEntity(entity);
        final key = _key(entity);
        final previous = (ns['entities'] as Map)[key] as Map?;
        if (previous != null && (previous['revision'] as int) >= (entity['revision'] as int)) continue;
        if ((ns['outbox'] as List).any((op) => _key(op) == key)) {
          (ns['conflicts'] as Map)[key] = entity;
          continue;
        }
        (ns['entities'] as Map)[key] = {
          ...entity,
          'origin': previous?['origin'] ?? 'remote',
          'localRevision': ((previous?['localRevision'] as int?) ?? 0) + 1,
        };
        final document = ns['document'] as Map;
        final field = entity['entityType'] == 'workout' ? 'sessions' : 'routines';
        final rows = (document[field] ??= <dynamic>[]) as List;
        rows.removeWhere((row) => row['id'] == entity['entityId']);
        if (entity['deleted'] != true) rows.add(entity['payload']);
      }
      ns['cursor'] = nextCursor;
    });
  }
}
