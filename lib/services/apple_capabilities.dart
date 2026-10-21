import 'package:flutter/services.dart';

/// Extensions must be present in the signed host, not merely supported by iOS.
class AppleCapabilities {
  const AppleCapabilities({this.homeWidgets = false, this.liveActivities = false});

  final bool homeWidgets;
  final bool liveActivities;
  static const _channel = MethodChannel('gymmane/capabilities');
  static Future<AppleCapabilities>? _cached;

  static Future<AppleCapabilities> get current => _cached ??= query();

  static Future<AppleCapabilities> query() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('get');
      return AppleCapabilities(
        homeWidgets: result?['homeWidgets'] == true,
        liveActivities: result?['liveActivities'] == true,
      );
    } on MissingPluginException {
      return const AppleCapabilities();
    } on PlatformException {
      return const AppleCapabilities();
    }
  }
}
