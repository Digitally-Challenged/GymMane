import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/local_store.dart';

class SaveStatus extends StatelessWidget {
  const SaveStatus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Store.instance.saveFailed,
    builder: (context, failed, _) => Column(
      children: [
        if (failed)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(liveRegion: true, child: Text(t.localSaveFailed)),
              ),
            ),
          ),
        Expanded(child: Semantics(container: true, explicitChildNodes: true, child: child)),
      ],
    ),
  );
}
