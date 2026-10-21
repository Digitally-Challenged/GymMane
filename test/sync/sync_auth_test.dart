import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'package:gymmane/services/sync/sync_config.dart';

class MemoryVault implements TokenVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('locked');
    value = next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

const firstAccount = '12345678-1234-1234-1234-123456789abc';
const secondAccount = '12345678-1234-1234-1234-123456789abd';
const config = SyncConfig(
  serverUrl: 'https://sync.example',
  authUrl: 'https://auth.example',
  publicKey: 'public',
  emailAuth: true,
);
void main() {
  test('sign out during refresh vault write cannot resurrect session or tokens', () async {
    final vault = DelayedVault()
      ..value = jsonEncode(AuthSession(firstAccount, 'old', 'refresh', DateTime(2000)).toJson());
    final auth = SupabaseSyncAuth(
      config,
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'user': {'id': firstAccount},
            'access_token': 'new',
            'refresh_token': 'rotated',
            'expires_in': 3600,
          }),
          200,
        ),
      ),
      vault,
    );
    await auth.restore();
    final refreshing = auth.accessToken();
    final rejection = expectLater(refreshing, throwsA(isA<Exception>()));
    await vault.entered.future;
    final signingOut = auth.signOut();
    vault.release.complete();
    await signingOut;
    await rejection;
    expect(auth.session, isNull);
    expect(vault.value, isNull);
  });
  test('new sign in during old vault commit retains only the newer account', () async {
    final vault = DelayedVault();
    final auth = SupabaseSyncAuth(
      config,
      MockClient((request) async {
        final email = jsonDecode(request.body)['email'];
        return http.Response(
          jsonEncode({
            'user': {'id': email == 'old@example.com' ? firstAccount : secondAccount},
            'access_token': email,
            'refresh_token': email,
            'expires_in': 3600,
          }),
          200,
        );
      }),
      vault,
    );
    final old = auth.signIn('old@example.com', 'password');
    final rejected = expectLater(old, throwsA(isA<Exception>()));
    await vault.entered.future;
    final newer = auth.signIn('new@example.com', 'password');
    vault.release.complete();
    await newer;
    await rejected;
    expect(auth.session!.account, secondAccount);
    expect(jsonDecode(vault.value!)['account'], secondAccount);
  });
  test('provider cannot authenticate into reserved guest namespace', () async {
    final auth = SupabaseSyncAuth(
      config,
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'user': {'id': 'guest'},
            'access_token': 'access',
            'refresh_token': 'refresh',
            'expires_in': 3600,
          }),
          200,
        ),
      ),
      MemoryVault(),
    );
    await expectLater(auth.signIn('a@example.com', 'password'), throwsFormatException);
    expect(auth.session, isNull);
  });
  test('native vault failure prevents publishing a session', () async {
    final vault = MemoryVault()..failWrite = true;
    final auth = SupabaseSyncAuth(
      config,
      MockClient((request) async {
        expect(request.url.path, '/auth/v1/token');
        expect(request.url.queryParameters['grant_type'], 'password');
        expect(request.followRedirects, false);
        expect(request.headers['apikey'], 'public');
        return http.Response(
          jsonEncode({
            'user': {'id': firstAccount},
            'access_token': 'access',
            'refresh_token': 'refresh',
            'expires_in': 3600,
          }),
          200,
        );
      }),
      vault,
    );
    await expectLater(auth.signIn('a@example.com', 'secret'), throwsStateError);
    expect(auth.session, isNull);
  });
  test('refresh token rotation is single flight and stored before use', () async {
    final vault = MemoryVault()
      ..value = jsonEncode(AuthSession(firstAccount, 'old', 'refresh', DateTime(2000)).toJson());
    final response = Completer<http.Response>();
    var requests = 0;
    final auth = SupabaseSyncAuth(
      config,
      MockClient((request) {
        requests++;
        expect(jsonDecode(request.body), {'refresh_token': 'refresh'});
        return response.future;
      }),
      vault,
    );
    await auth.restore();
    final first = auth.accessToken(), second = auth.accessToken();
    response.complete(
      http.Response(
        jsonEncode({
          'user': {'id': firstAccount},
          'access_token': 'new',
          'refresh_token': 'rotated',
          'expires_in': 3600,
        }),
        200,
      ),
    );
    expect(await Future.wait([first, second]), ['new', 'new']);
    expect(requests, 1);
    expect(jsonDecode(vault.value!)['refresh'], 'rotated');
    await auth.signOut();
    expect(vault.value, isNull);
    expect(auth.session, isNull);
  });
}

class DelayedVault extends MemoryVault {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String next) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    await super.write(next);
  }
}
