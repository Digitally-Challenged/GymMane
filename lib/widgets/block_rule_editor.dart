import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../state/fit_state.dart';

class BlockRuleEditor extends StatefulWidget {
  const BlockRuleEditor({super.key, required this.routine, required this.exerciseId});
  final Routine routine;
  final String exerciseId;
  @override
  State<BlockRuleEditor> createState() => _BlockRuleEditorState();
}

class _BlockRuleEditorState extends State<BlockRuleEditor> {
  final _form = GlobalKey<FormState>();
  late final _rule = widget.routine.program!.rules[widget.exerciseId]!;
  late final _load = TextEditingController(text: fmt(fit.toDisplayWeight(_rule.seedKg)));
  late final _increment = TextEditingController(text: fmt(fit.toDisplayWeight(_rule.incrementKg)));
  late final _rounding = TextEditingController(text: fmt(fit.toDisplayWeight(_rule.roundingKg)));
  late final _cap = TextEditingController(
    text: _rule.maxWeightKg == null ? '' : fmt(fit.toDisplayWeight(_rule.maxWeightKg!)),
  );
  double? _parse(String? text) => double.tryParse((text ?? '').trim().replaceAll(',', '.'));
  @override
  void dispose() {
    for (final controller in [_load, _increment, _rounding, _cap]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, {bool empty = false, bool zero = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '$label (${fit.units})', border: const OutlineInputBorder()),
          validator: (text) {
            if (empty && (text ?? '').trim().isEmpty) return null;
            final n = _parse(text);
            if (n == null || !n.isFinite || (zero ? n < 0 : n <= 0) || fit.fromDisplayWeight(n) > 1000) {
              return 'Enter a valid ${zero ? 'nonnegative' : 'positive'} load.';
            }
            if (controller == _increment || controller == _rounding) {
              if (fit.fromDisplayWeight(n) < .001 || fit.fromDisplayWeight(n) > 100) {
                return 'Choose a smaller load step.';
              }
            }
            return null;
          },
        ),
      );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.routine.exerciseDefinitions[widget.exerciseId]?.name ??
                fit.exerciseById(widget.exerciseId)?.name ??
                'Exercise',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(t.blockCalibrationHint),
          _field(_load, t.blockCalibrationLoad, zero: true),
          _field(_increment, t.blockIncreaseBy),
          _field(_rounding, t.blockLoadStep),
          _field(_cap, t.blockLoadCap, empty: true),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              final cap = _parse(_cap.text);
              fit.setBlockExerciseRule(
                widget.routine.id,
                widget.exerciseId,
                _rule.copyWith(
                  seedKg: fit.fromDisplayWeight(_parse(_load.text)!),
                  incrementKg: fit.fromDisplayWeight(_parse(_increment.text)!),
                  roundingKg: fit.fromDisplayWeight(_parse(_rounding.text)!),
                  clearCap: cap == null,
                  maxWeightKg: cap == null ? null : fit.fromDisplayWeight(cap),
                ),
              );
              Navigator.pop(context);
            },
            child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text(t.saveChanges)),
          ),
        ],
      ),
    ),
  );
}
