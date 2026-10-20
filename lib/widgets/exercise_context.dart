import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/l10n.dart';
import '../models/training_method.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ExerciseContext extends StatelessWidget {
  const ExerciseContext({super.key, required this.exerciseId, required this.onHistory});

  final String exerciseId;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final last = fit.lastEffortSummaryFor(exerciseId);
    if (last == null) return const SizedBox.shrink();
    final gc = context.gc;
    final method = fit.sessionTrainingMethod;
    final target = method == TrainingMethod.standard ? fit.nextTarget(exerciseId) : null;
    final why = target == null
        ? null
        : target.deload
        ? t.nextDeload(fit.stallStreak(exerciseId))
        : target.up
        ? t.nextIncrease
        : t.nextHold;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onHistory,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.last, style: AppTheme.f(11, color: gc.textTertiary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        last,
                        style: AppTheme.f(12, weight: FontWeight.w600, color: gc.textSecondary),
                      ),
                    ),
                    Icon(PhosphorIconsRegular.caretRight, size: 14, color: gc.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          if (method != TrainingMethod.standard)
            Text('${method.label}: ${method.description}', style: AppTheme.f(11.5, color: gc.textTertiary)),
          if (target != null) ...[
            Text(
              '${t.nextTime}  ${fit.nextTargetLabel(exerciseId)}',
              style: AppTheme.f(12, weight: FontWeight.w600, color: target.up ? gc.ember : gc.textSecondary),
            ),
            const SizedBox(height: 2),
            Text('$why · ${t.nextAdvice}', style: AppTheme.f(11.5, color: gc.textTertiary)),
          ],
        ],
      ),
    );
  }
}
