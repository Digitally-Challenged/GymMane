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

const config = SyncConfig(
  serverUrl: 'https://sync.example',
  authUrl: 'https://auth.example',
  publicKey: 'public',
  emailAuth: true,
);
void main() {
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
            'user': {'id': 'account'},
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
      ..value = jsonEncode(AuthSession('account', 'old', 'refresh', DateTime(2000)).toJson());
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
          'user': {'id': 'account'},
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
