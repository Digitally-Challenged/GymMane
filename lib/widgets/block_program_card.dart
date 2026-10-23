import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../models/block_program.dart';
import '../models/workout.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'block_rule_editor.dart';

class BlockProgramCard extends StatelessWidget {
  const BlockProgramCard({super.key, required this.routine});
  final Routine routine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fit,
      builder: (context, _) {
        final p = routine.program;
        if (p == null) return const SizedBox.shrink();
        final gc = context.gc;
        final now = DateTime.now(), week = p.weekOn(DateTime.now());
        final started = fit.sessions.any((s) => s.program?.programId == p.id);
        final locked =
            fit.sessions.any((s) => s.program?.programId == p.id && s.program?.week == week) ||
            (fit.session?.program?.programId == p.id && fit.session?.complete == false);
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fit.blockStatus(routine),
                style: AppTheme.f(15, weight: FontWeight.w700, color: gc.text),
              ),
              const SizedBox(height: 8),
              Text(t.blockWorkoutGuide, style: AppTheme.f(12, color: gc.textSecondary, height: 1.4)),
              if (p.activeOn(now) &&
                  week % 4 != 0 &&
                  fit.routines.any((r) => r.program?.id == p.id && r.program?.day == 4))
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.blockOptionalArms),
                  subtitle: Text(locked ? t.blockOptionalLocked : t.blockOptionalHint),
                  value: p.fifthOn(week),
                  onChanged: locked ? null : (value) => fit.setBlockFifthDay(p.id, value),
                ),
              if (!started && !locked)
                TextButton(
                  onPressed: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: p.start.isBefore(DateTime(2020))
                          ? DateTime(2020)
                          : p.start.isAfter(DateTime(now.year + 5))
                          ? DateTime(now.year + 5)
                          : p.start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (chosen != null) fit.setBlockStart(p.id, chosen);
                  },
                  child: Text('Start date: ${p.toJson()['start']}'),
                ),
              if (fit.programStartError case final error?)
                Text(error, style: AppTheme.f(13, color: gc.textSecondary)),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(t.blockSettingsTitle),
                children: [
                  for (final id in routine.exerciseIds)
                    if (p.rules[id] case final rule?)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(fit.exerciseById(id)?.name ?? id),
                        subtitle: Text(
                          '${rule.method == BlockMethod.reversePyramid ? 'Reverse pyramid 6/8/10' : '${rule.minReps}–${rule.maxReps} reps'} · ${rule.minimumRir}+ reps in reserve${rule.maxWeightKg == null ? '' : ' · cap ${fit.weightLabel(rule.maxWeightKg!)}'}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => BlockRuleEditor(routine: routine, exerciseId: id),
                        ),
                      ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
