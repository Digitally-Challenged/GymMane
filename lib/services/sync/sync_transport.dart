import '../../l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

typedef SyncJson = Map<String, dynamic>;

class SyncFailure implements Exception {
  SyncFailure(this.message, {this.status});
  final String message;
  final int? status;
  bool get retryable => status == null || status == 429 || status! >= 500;
  bool get needsAuthorization => status == 401 || status == 403;
  @override
  String toString() => message;
}

class SyncTransport {
  SyncTransport(this.base, this.client);
  final Uri base;
  final http.Client client;

  Future<List<SyncJson>> push(String token, List<SyncJson> operations) async {
    if (operations.isEmpty || operations.length > 100) {
      throw SyncFailure('Push requires 1–100 operations.', status: 400);
    }
    final data = await request(
      'POST',
      '/v1/sync/push',
      token,
      body: {'schemaVersion': 1, 'operations': operations},
    );
    final results = jsonList(data['results']);
    final expected = {for (final op in operations) op['operationId']: op};
    if (results.length != expected.length) throw const FormatException('Incomplete push receipts');
    final seen = <String>{};
    for (final result in results) {
      final id = result['operationId'];
      final op = expected[id];
      if (id is! String ||
          op == null ||
          !seen.add(id) ||
          !['accepted', 'conflict'].contains(result['status'])) {
        throw const FormatException('Invalid push receipt');
      }
      final entity = jsonObject(result['entity']);
      validateEntity(entity);
      if (entity['entityId'] != op['entityId'] || entity['entityType'] != op['entityType']) {
        throw const FormatException('Mismatched push entity');
      }
    }
    return results;
  }

  Future<SyncJson> pull(String token, String cursor) async {
    validateCursor(cursor);
    final data = await request('GET', '/v1/sync/pull', token, query: {'cursor': cursor, 'limit': '100'});
    final entities = jsonList(data['entities']);
    final next = validateCursor(data['nextCursor']);
    if (entities.length > 100 || data['hasMore'] is! bool || next < BigInt.parse(cursor)) {
      throw const FormatException('Invalid pull page');
    }
    var previous = BigInt.parse(cursor);
    for (final entity in entities) {
      validateEntity(entity);
      final current = validateCursor(entity['cursor']);
      if (current <= previous || current > next) throw const FormatException('Unordered pull page');
      previous = current;
    }
    if (data['hasMore'] == true && (entities.isEmpty || next <= BigInt.parse(cursor))) {
      throw const FormatException('Pull cursor did not advance');
    }
    return data;
  }

  Future<SyncJson> request(
    String method,
    String path,
    String token, {
    SyncJson? body,
    Map<String, String>? query,
  }) async {
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
    final req = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await client.send(req).timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > 8 * 1024 * 1024) throw const FormatException('Response too large');
        bytes.addAll(chunk);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncFailure(
          '${t.syncSyncRequestFailed} (${response.statusCode}).',
          status: response.statusCode,
        );
      }
      return jsonObject(jsonDecode(utf8.decode(bytes)));
    } on TimeoutException {
      throw SyncFailure(t.syncConnectionTimedOutYourChangesRemainOn);
    } on http.ClientException {
      throw SyncFailure(t.syncOfflineOrServerUnreachableYourChangesRemain);
    }
  }
}

SyncJson jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('Expected JSON object');
  return value;
}

List<SyncJson> jsonList(Object? value) {
  if (value is! List) throw const FormatException('Expected JSON list');
  return value.map(jsonObject).toList();
}

BigInt validateCursor(Object? value) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('Invalid cursor');
  }
  return BigInt.parse(value);
}

void validateEntity(SyncJson entity) {
  final revision = entity['revision'];
  if (!['workout', 'routine'].contains(entity['entityType']) ||
      entity['entityId'] is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(entity['entityId'] as String) ||
      revision is! int ||
      revision < 1 ||
      revision > 9007199254740991 ||
      entity['deleted'] is! bool ||
      (entity['deleted'] == true ? entity['payload'] != null : entity['payload'] is! Map<String, dynamic>)) {
    throw const FormatException('Invalid remote entity');
  }
  validateCursor(entity['cursor']);
  if (entity['deleted'] == false) {
    final payload = jsonObject(entity['payload']);
    if (payload['id'] != entity['entityId']) throw const FormatException('Remote payload identity mismatch');
    if (entity['entityType'] == 'workout') validateWorkoutDate(payload['d']);
  }
}

void validateWorkoutDate(Object? value) {
  if (value is! String) throw const FormatException('Invalid workout timestamp');
  final match = RegExp(
    r'^([0-9]{4}|-[0-9]{4}|[+-][0-9]{6})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,6}))?(Z)?$',
  ).firstMatch(value);
  if (match == null || match.group(0) != value) throw const FormatException('Invalid workout timestamp');
  final parsed = DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z');
  if (parsed == null ||
      [
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
      ].asMap().entries.any((entry) => entry.value != int.parse(match.group(entry.key + 1)!))) {
    throw const FormatException('Invalid workout calendar date');
  }
}
