import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';

class StartupRecovery extends StatefulWidget {
  const StartupRecovery({super.key, required this.retry});
  final Future<void> Function() retry;
  @override
  State<StartupRecovery> createState() => _StartupRecoveryState();
}

class _StartupRecoveryState extends State<StartupRecovery> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 16),
                Text(t.syncLocalDataCouldNotBeOpened, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 12),
                Text(t.syncYourSavedDataHasNotBeenReset),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await widget.retry();
                          if (mounted) setState(() => _busy = false);
                        },
                  child: Text(t.syncRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
