import '../../l10n/l10n.dart';

class SyncConfig {
  const SyncConfig({
    required this.serverUrl,
    required this.authUrl,
    required this.publicKey,
    required this.emailAuth,
  });
  const SyncConfig.environment()
    : serverUrl = const String.fromEnvironment('GYMMANE_SYNC_URL'),
      authUrl = const String.fromEnvironment('GYMMANE_AUTH_URL'),
      publicKey = const String.fromEnvironment('GYMMANE_AUTH_PUBLIC_KEY'),
      emailAuth = const bool.fromEnvironment('GYMMANE_EMAIL_AUTH');
  final String serverUrl, authUrl, publicKey;
  final bool emailAuth;
  String? get unavailableReason {
    if (!_https(serverUrl) || !_https(authUrl) || publicKey.trim().isEmpty) {
      return t.syncCloudSyncUnavailableThisBuildNeedsAn;
    }
    if (!emailAuth) return t.syncCloudSyncUnavailableEmailSignInIs;
    return null;
  }

  static bool _https(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}
