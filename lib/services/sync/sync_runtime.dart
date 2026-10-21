import 'dart:async';
import 'package:http/http.dart' as http;
import '../local_store.dart';
import 'store_sync_repository.dart';
import 'sync_auth.dart';
import 'sync_config.dart';
import 'sync_controller.dart';
import 'sync_transport.dart';
import 'healthkit_delivery.dart';
import 'store_health_delivery.dart';

/// Initialized once after local state has loaded. No network configuration is
/// fetched and no account is created automatically.
class SyncRuntime {
  SyncRuntime._();
  static SyncController? controller;
  static HealthKitDelivery? health;
  static http.Client? _client;
  static Future<void> initialize() async {
    controller?.dispose();
    _client?.close();
    health?.dispose();
    health = HealthKitDelivery(StoreHealthDelivery(Store.instance));
    const config = SyncConfig.environment();
    final client = http.Client();
    _client = client;
    final auth = SupabaseSyncAuth(
      config,
      client,
      SessionTokenVault(
        'gymmane.sync.session.${Uri.encodeComponent(config.authUrl)}.${Uri.encodeComponent(config.serverUrl)}',
      ),
    );
    controller = SyncController(
      config: config,
      auth: auth,
      repository: StoreSyncRepository(Store.instance),
      transport: SyncTransport(Uri.tryParse(config.serverUrl) ?? Uri(), client),
      acknowledgedSaves: Store.instance.acknowledgedSaves,
    );
    String? account;
    controller!.addListener(() {
      if (account == controller!.account) return;
      account = controller!.account;
      health!.invalidate();
      unawaited(health!.refresh());
    });
    await controller!.initialize();
  }
}
