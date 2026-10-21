import '../../l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'sync_config.dart';
import 'sync_transport.dart';

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Browser sessions intentionally last only for this tab's lifetime.
class SessionTokenVault implements TokenVault {
  SessionTokenVault(this.key);
  final String key;
  final _secure = const FlutterSecureStorage();
  String? _memory;
  @override
  Future<String?> read() async => kIsWeb ? _memory : _secure.read(key: key);
  @override
  Future<void> write(String value) async {
    if (kIsWeb) {
      _memory = value;
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  @override
  Future<void> clear() async {
    _memory = null;
    if (!kIsWeb) await _secure.delete(key: key);
  }
}

class AuthSession {
  const AuthSession(this.account, this.accessToken, this.refreshToken, this.expiresAt);
  final String account, accessToken, refreshToken;
  final DateTime expiresAt;
  SyncJson toJson() => {
    'account': account,
    'access': accessToken,
    'refresh': refreshToken,
    'expires': expiresAt.toIso8601String(),
  };
  static AuthSession stored(SyncJson value) {
    final account = value['account'];
    if (account is! String ||
        !validAuthAccount(account) ||
        value['access'] is! String ||
        (value['access'] as String).isEmpty ||
        value['refresh'] is! String ||
        (value['refresh'] as String).isEmpty) {
      throw const FormatException('Invalid stored session');
    }
    return AuthSession(
      account.toLowerCase(),
      value['access'] as String,
      value['refresh'] as String,
      DateTime.parse(value['expires'] as String),
    );
  }
}

abstract interface class SyncAuth {
  AuthSession? get session;
  Future<void> restore();
  Future<void> signIn(String email, String password);
  Future<String> accessToken();
  Future<void> signOut();
}

/// Provider-specific password and rotating refresh-token handling stays here.
class SupabaseSyncAuth implements SyncAuth {
  SupabaseSyncAuth(this.config, this.client, this.vault);
  final SyncConfig config;
  final http.Client client;
  final TokenVault vault;
  AuthSession? _session;
  Future<String>? _refresh;
  int _generation = 0;
  Future<void> _vaultTail = Future.value();

  Future<void> _withVault(Future<void> Function() action) {
    final operation = _vaultTail.then((_) => action());
    _vaultTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _commit(AuthSession next, int generation) => _withVault(() async {
    if (generation != _generation) throw SyncFailure(t.syncAccountChangedSignInAgain, status: 401);
    await vault.write(jsonEncode(next.toJson()));
    if (generation != _generation) {
      // The queue guarantees no newer account's write can have committed yet.
      await vault.clear();
      throw SyncFailure(t.syncAccountChangedSignInAgain, status: 401);
    }
    _session = next;
  });
  @override
  AuthSession? get session => _session;
  @override
  Future<void> restore() async {
    final generation = _generation;
    await _withVault(() async {
      final saved = await vault.read();
      if (generation == _generation && saved != null) {
        _session = AuthSession.stored(jsonObject(jsonDecode(saved)));
      }
    });
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (config.unavailableReason != null) throw SyncFailure(config.unavailableReason!);
    final generation = ++_generation;
    _session = null;
    _refresh = null;
    final next = await _exchange('password', {'email': email.trim(), 'password': password});
    await _commit(next, generation);
  }

  @override
  Future<String> accessToken() async {
    final current = _session;
    if (current == null) throw SyncFailure(t.syncSignInToSync, status: 401);
    if (current.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return current.accessToken;
    if (_refresh != null) return _refresh!;
    final future = _renew(current, _generation);
    _refresh = future;
    try {
      return await future;
    } finally {
      if (identical(_refresh, future)) _refresh = null;
    }
  }

  Future<String> _renew(AuthSession old, int generation) async {
    final next = await _exchange('refresh_token', {'refresh_token': old.refreshToken});
    if (generation != _generation || next.account != old.account) {
      throw SyncFailure(t.syncAccountChangedSignInAgain, status: 401);
    }
    await _commit(next, generation);
    return next.accessToken;
  }

  Future<AuthSession> _exchange(String grant, SyncJson body) async {
    final uri = Uri.parse(
      '${config.authUrl.replaceFirst(RegExp(r'/$'), '')}/auth/v1/token',
    ).replace(queryParameters: {'grant_type': grant});
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll({'apikey': config.publicKey, 'Content-Type': 'application/json'})
      ..body = jsonEncode(body);
    try {
      final streamed = await client.send(request).timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in streamed.stream.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > 65536) throw const FormatException('Auth response too large');
        bytes.addAll(chunk);
      }
      final response = http.Response.bytes(bytes, streamed.statusCode);
      if (response.statusCode != 200) {
        throw SyncFailure(t.syncSignInOrSessionRefreshFailedCheck, status: response.statusCode);
      }
      final data = jsonObject(jsonDecode(response.body));
      final account = jsonObject(data['user'])['id'];
      final access = data['access_token'];
      final refresh = data['refresh_token'];
      final seconds = data['expires_in'];
      if (account is! String ||
          !validAuthAccount(account) ||
          access is! String ||
          access.isEmpty ||
          refresh is! String ||
          refresh.isEmpty ||
          seconds is! int ||
          seconds <= 0) {
        throw const FormatException('Invalid auth session');
      }
      return AuthSession(
        account.toLowerCase(),
        access,
        refresh,
        DateTime.now().add(Duration(seconds: seconds)),
      );
    } on TimeoutException {
      throw SyncFailure(t.syncSignInServerTimedOutTryAgain);
    } on http.ClientException {
      throw SyncFailure(t.syncSignInServerUnreachableTryAgainWhen);
    }
  }

  @override
  Future<void> signOut() async {
    ++_generation;
    _session = null;
    _refresh = null;
    await _withVault(vault.clear);
  }
}

bool validAuthAccount(String account) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(account);
