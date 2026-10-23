import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../models/block_program.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class BlockExerciseContext extends StatelessWidget {
  const BlockExerciseContext({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final snapshot = fit.session?.program;
    if (snapshot == null) return const SizedBox.shrink();
    final gc = context.gc;
    final previous = fit.previousBlockSession(exerciseId);
    final response = previous?.program?.responses[exerciseId];
    final rule = snapshot.rules[exerciseId];
    final reserve = snapshot.deload ? 4 : (rule?.minimumRir ?? 2).clamp(snapshot.minimumRir, 4);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Week ${snapshot.week} / 12 · ${snapshot.deload ? 'Deload' : 'Build'} · $reserve+ reps in reserve',
            style: AppTheme.f(12, weight: FontWeight.w700, color: gc.text),
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.reasons[exerciseId] ?? 'Substitution: calibrate this movement separately.',
            style: AppTheme.f(12, color: gc.textSecondary, height: 1.4),
          ),
          if (previous != null) ...[
            const SizedBox(height: 8),
            Text(t.blockRecoveryQuestion, style: AppTheme.f(12, color: gc.textSecondary)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (value, label) in [
                  (BlockResponse.stable, t.blockResponseStable),
                  (BlockResponse.aggravated, t.blockResponseWorse),
                ])
                  TextButton(
                    onPressed: () => fit.reviewBlockResponse(exerciseId, value),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: Text('${response == value ? '✓ ' : ''}$label'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
