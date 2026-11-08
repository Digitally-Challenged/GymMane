# Handoff: plate calculator rebuild — 2026-11-08

**Status:** Built and reviewed on `feat-plate-calculator` (head `a17b1f5`, pushed to `fork`). The final reviewer's verdict was "Ready to merge: Yes". One small layout regression on the Places screen is still open. Not merged.

### What exists right now (branch / commit)
- Branch `feat-plate-calculator`, worktree `~/orca/workspaces/GymMane/GymMane/feat-plate-calculator`, based on `main` @ `3ddf540`. 16 commits, 64 files, +5767 / −605 (most of it generated l10n).
- **Plates tool** (`lib/screens/plate_tool.dart`, `lib/widgets/plates/plate_tool_cards.dart`):
  - **Load tab:** drawn bar, kg/lb readout, ± stepper snapped to the plate grid, bar choice, plate chips, sum line.
  - **What's on it? tab:** disc grid for counting what's loaded.
- **Between-sets sheet** (`lib/widgets/plates/plate_sheet.dart`): opened from the hint row under a set and from the 1RM card. Shows the change line ("Take off 10 ×2, add 25 · 5 each side").
- **Per-gym inventory** (`lib/widgets/plates/plate_inventory_sheet.dart`): disc grid, collars, and Coloured / Iron / Custom plate colours. Long-press a disc for swatches.
- **State and maths:** `lib/state/plate_tool_state.dart` (new mixin), `lib/models/plate_math.dart`, `lib/theme/plate_palette.dart`, new `GymPlace` fields (`cl` / `cb` / `cc` / `pc` JSON keys, written only when non-default).
- **Strings:** all 17 locales.
- **Tests:** about 150 new across `test/plates_test.dart`, `plate_colours_test.dart`, `plate_widgets_test.dart`, `plate_tool_test.dart`, `plate_sheet_test.dart` and `plate_inventory_test.dart`. Plate-related files pass 187/187 and `flutter analyze` is clean.

### Where the real state lives
- Spec: `docs/superpowers/specs/2026-11-07-plate-calculator-design.md`. Plan: `docs/superpowers/plans/2026-11-07-plate-calculator.md`.
- The build ledger, with every review, ruling and deferred minor, is at `.superpowers/sdd/2026-11-07-plate-calculator/progress.md` in the worktree. It is git-ignored: the rulings are copied below; the deferred minors are not, so read them in the ledger.
- The simulator screenshots (iPhone 17, dark kg / light lb) are in the session scratchpad and are not durable.

### Key decisions (and why)
Settled with Nick:
- Borrow Bar Is Loaded's functions and layout, keep GymMane's own theme.
- All three surfaces matter equally (Load, What's on it?, inventory).
- Entry points are the Tools screen and the between-sets shortcut.
- Plate colours are set per gym, with presets plus per-plate overrides.

Calls made during the build (cost if wrong in brackets):
1. Custom colours sit on top of a preset. Switching preset hides overrides but keeps them. [none]
2. Collars count only for Barbell lifts with no per-exercise bar. [none]
3. 1.25 kg stock keys are kept to 0.01. This fixed an older bug where 1.25 became 1.3 and never loaded. [a stored 1.25 now loads]
4. A unit switch clears the tool's manual bar choice and the reverse counts, and snaps the target to the new grid. [a manual bar pick resets; repeated toggling can drift by up to half a step]
5. Disc label ink is picked by WCAG contrast. [a few labels flip colour]
6. The collar block is drawn inboard, as in the mockup. [it differs from a real outboard clamp]
7. `plate_math.dart` imports `fmt` from `fit_state.dart`. [not reusable outside the app]
8. The session hint keeps the compact "45×2 · 25"; sheets and chips use "45 ×2 · 25". [cosmetic]

### Gotchas / hard rules
- **Time-dependent tests fail on `main` too.** Some tests (requests_*, audit, nutrition heatmap and "today" tests) fail on untouched `main` depending on the time of day. Only failures in plate files count.
- **Regenerating l10n:** after `flutter gen-l10n`, run `dart format` on the generated `lib/l10n/app_localizations*.dart`, or about 3,400 lines churn.
- **Don't format `places_screen.dart`:** it isn't format-clean, so `dart format` on it rewrites about 170 unrelated lines.
- **File sizes are tight:** `plate_inventory_sheet.dart` is 395 lines and the cap is 400.
- **The primary checkout** (`~/Documents/GitHub/GymMane`) is still on `feat-watch-companion` with untracked `data/`. That predates this work and was left untouched.

### ⏭️ NEXT
Fix the regression on the "Plates and bar" row in `lib/screens/places_screen.dart` (~250).
- **The bug:** a `Flexible` value next to the `Expanded` label pulls the value and caret about 57 px left of the trailing edge for short values like "3 sizes".
- **The fix:** keep the label `Expanded` and wrap the value `Text` (ellipsis, maxLines 1) in `ConstrainedBox(maxWidth: ~110)`. Add a widget test that the caret's right edge equals the row's right edge for a short value, and keep the existing 320/360 px no-overflow test passing.
- **Then:** open a PR from `feat-plate-calculator` into `main` on the fork.

### Open status
- Not merged and no PR yet. The branch is pushed to `fork` (Digitally-Challenged/GymMane).
- Deferred minors worth a later sweep: translation wording in ar, it, es, fa, ja and ko needs a native-speaker check; swatches have no screen-reader names; −/+ buttons can't be reached by keyboard on web; there is no RTL test of the sum line.
