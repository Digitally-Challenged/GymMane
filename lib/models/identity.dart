import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newEntityId() => _uuid.v4();
bool isEntityId(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
String legacyEntityId(String kind, Object value) =>
    _uuid.v5(Namespace.url.value, 'gymmane:v1:$kind:${jsonEncode(_canonical(value))}');
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
