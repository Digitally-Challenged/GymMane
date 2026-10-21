import 'dart:convert';

typedef HealthDeliveryJson = Map<String, dynamic>;
HealthDeliveryJson _copy(HealthDeliveryJson value) => jsonDecode(jsonEncode(value)) as HealthDeliveryJson;

/// HealthKit's sync identifier is device-global, so its ownership/version ledger
/// must outlive account namespaces. This metadata is never backed up or synced.
HealthDeliveryJson _registry(HealthDeliveryJson root) {
  if (root['healthExportRegistry'] case final Map<String, dynamic> saved) return saved;
  final migrated = <String, dynamic>{};
  for (final space in (root['namespaces'] as HealthDeliveryJson).entries) {
    final records = space.value['deliveries']?['healthkit']?['records'] as Map? ?? {};
    for (final entry in records.entries) {
      if (migrated.containsKey(entry.key)) throw StateError('Ambiguous HealthKit export ownership');
      migrated[entry.key as String] = {
        'owner': space.key,
        'record': {
          ..._copy(entry.value as HealthDeliveryJson),
          'operation': entry.value['operation'] ?? 'save',
        },
      };
    }
  }
  root['healthExportRegistry'] = migrated;
  return migrated;
}

HealthDeliveryJson readHealthDelivery(
  HealthDeliveryJson root,
  String account,
  HealthDeliveryJson preferences,
) => {
  ...preferences,
  'records': {
    for (final entry in _registry(root).entries)
      if (entry.value['owner'] == account) entry.key: _copy(entry.value['record'] as HealthDeliveryJson),
  },
};

void writeHealthDelivery(HealthDeliveryJson root, String account, HealthDeliveryJson ledger) {
  final registry = _registry(root);
  final entries = ledger['records'] as HealthDeliveryJson? ?? {};
  for (final entry in entries.entries) {
    final record = entry.value as HealthDeliveryJson;
    final previous = registry[entry.key] as HealthDeliveryJson?;
    final old = previous?['record'] as HealthDeliveryJson?;
    final revision = record['revision'];
    if (revision is! int ||
        revision < 1 ||
        revision > 9007199254740991 ||
        !['sending', 'unknown', 'confirmed', 'deleted'].contains(record['status']) ||
        !['save', 'delete'].contains(record['operation']) ||
        record['payload']?['id'] != entry.key) {
      throw const FormatException('Invalid HealthKit delivery intent');
    }
    if (previous != null && previous['owner'] != account) {
      throw StateError('This HealthKit workout belongs to another local account');
    }
    if (old == null) {
      final entity = root['namespaces'][account]['entities']['workout:${entry.key}'];
      if (entity?['payload']?['origin'] != 'gymmane' ||
          entity?['deleted'] == true ||
          revision != 1 ||
          record['operation'] != 'save' ||
          record['status'] != 'sending') {
        throw StateError('A new HealthKit export requires a local durable workout and intent');
      }
    } else {
      final oldRevision = old['revision'] as int;
      if (revision < oldRevision || revision > oldRevision + 1) throw StateError('Stale HealthKit version');
      if (revision == oldRevision &&
          (record['operation'] != (old['operation'] ?? 'save') ||
              record['fingerprint'] != old['fingerprint'] ||
              jsonEncode(record['payload']) != jsonEncode(old['payload']))) {
        throw StateError('A HealthKit version cannot change its immutable intent');
      }
      if (revision > oldRevision && ['sending', 'unknown'].contains(old['status'])) {
        throw StateError('Reconcile the prior HealthKit intent first');
      }
    }
    registry[entry.key] = {'owner': account, 'record': _copy(record)};
  }
  final preferences = _copy(ledger)..remove('records');
  final space = root['namespaces'][account] as HealthDeliveryJson;
  (space['deliveries'] ??= <String, dynamic>{})['healthkit'] = preferences;
}

void transferGuestHealthDelivery(HealthDeliveryJson root, String account, Set<String> adoptedIds) {
  for (final entry in _registry(root).entries) {
    if (entry.value['owner'] == 'guest' && adoptedIds.contains(entry.key)) {
      entry.value['owner'] = account;
    }
  }
}
