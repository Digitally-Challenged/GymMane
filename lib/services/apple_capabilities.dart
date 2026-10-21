import 'package:flutter/services.dart';

/// Extensions must be present in the signed host, not merely supported by iOS.
class AppleCapabilities {
  const AppleCapabilities({
    this.homeWidgets = false,
    this.liveActivities = false,
    this.deviceClass = 'unknown',
  });

  final bool homeWidgets;
  final bool liveActivities;
  final String deviceClass;
  bool get isPhone => deviceClass == 'phone';
  static const _channel = MethodChannel('gymmane/capabilities');
  static Future<AppleCapabilities>? _cached;

  static Future<AppleCapabilities> get current => _cached ??= query();

  static Future<AppleCapabilities> query() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('get');
      return AppleCapabilities(
        homeWidgets: result?['homeWidgets'] == true,
        liveActivities: result?['liveActivities'] == true,
        deviceClass: switch (result?['deviceClass']) {
          'phone' => 'phone',
          'tablet' => 'tablet',
          _ => 'unknown',
        },
      );
    } on MissingPluginException {
      return const AppleCapabilities();
    } on PlatformException {
      return const AppleCapabilities();
    }
  }
}
