# Plate Calculator Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace GymMane's text-only plate calculator with a drawn-bar Load tab, a "What's on it?" reverse tab, a disc-based per-gym inventory with collars and plate colours, and a richer between-sets sheet.

**Architecture:** Pure plate maths and colour resolution live in small Dart files with no widget code. Collars, colours and reverse counts are added to the existing `ToolsState` / `PlacesState` mixins and to `GymPlace`. One shared widget set (`lib/widgets/plates/`) draws the bar, discs and chips for all three surfaces. The old plate UI is deleted, not kept alongside.

**Tech Stack:** Flutter / Dart, `flutter_test`, ARB l10n via `flutter gen-l10n` (`generate: true`, 17 locales).

**Spec:** `docs/superpowers/specs/2026-11-07-plate-calculator-design.md`. Read it before any task.

**Worktree:** `/Users/COLEMAN/orca/workspaces/GymMane/GymMane/feat-plate-calculator` on branch `feat-plate-calculator`. Baseline: `flutter analyze` clean and `flutter test` 990 passing.

## Global Constraints

- Use GymMane's theme only (`context.gc`, `AppTheme.f/s/d`). No Bar Is Loaded red, chrome or art.
- **No new icon-library icons or emoji.** Draw the bar and discs with CustomPainter or plain shapes. Existing Phosphor uses stay as they are.
- Every user-visible string is an ARB key present in **all 17** `lib/l10n/app_*.arb` files. Regenerate with `flutter gen-l10n` and commit the generated `app_localizations*.dart`. `test/i18n_test.dart` must pass.
- Weights are stored in kg; the UI shows display units (`fit.toDisplayWeight`, `fit.isLb`). Plate maps on `GymPlace` are keyed by kg and matched with a 0.05 tolerance (`_plateKey`).
- Old `GymPlace` JSON without the new keys must load unchanged: Coloured, no Custom, no overrides, collars 0.
- Delete the replaced code (`_barWeightCard`, `_perSideCard`, the old `showPlateSheet`, `_editPlates` and the plate `_plateRow` in `places_screen.dart`). No compatibility shims and no TODOs.
- Files stay under 400 lines; functions under 50.
- Stage files by explicit path only. Never `git add -A` or `git add .`. Conventional commit messages.
- Run `flutter analyze` and the task's tests before each commit; run the full `flutter test` before the last commit of each task.

## Review Focus

1. **lb user, kg-stored stock.** A 45 lb plate is stored as 20.412 kg. Its pair count, colour override and dimming must still resolve to "45" (Task 2 test `lb stock and colour overrides resolve through kg keys`).
2. **Target at or below bar + collars.** The result is "Just the bar" and never negative plates (Task 2 test `collars eat into the plates, never below zero`).
3. **Very heavy loads.** 700 lb puts 7 × 45 plus change plates on each side; the drawing must not overflow at phone width (Task 3 test `a 700 lb bar draws without overflow at 320 wide`).
4. **Switching units with reverse counts entered.** The counts are keyed by display size, so changing units clears them and never leaves a "45" in a kg grid (Task 2 test `changing units clears the reverse counts`).
5. **Plate-loaded machines.** A leg press with its own bar weight gets no collars in its hint, even when the gym has collars (Task 2 test `exercises with their own bar never get collars`).

---

### Task 1: Strings for every locale

**Files:**
- Modify: all 17 `lib/l10n/app_*.arb`, and the generated `lib/l10n/app_localizations*.dart` (via `flutter gen-l10n`)

**Interfaces:**
- Produces these `t.<key>` getters/methods. English values are exact; translate the other 16 yourself, matching each file's tone, as commit `ee51064` did:

| key | en | placeholders |
|---|---|---|
| `plateTabLoad` | `Load` | |
| `plateTabReverse` | `What's on it?` | |
| `plateSum` | `{bar} bar + 2 × ({plates}) = {total}` | bar, plates, total: String |
| `plateSumCollars` | `{bar} bar + {collars} collars + 2 × ({plates}) = {total}` | bar, collars, plates, total: String |
| `plateClear` | `Clear` | |
| `plateChangeAdd` | `Add {plates} each side` | plates: String |
| `plateChangeOff` | `Take off {plates} each side` | plates: String |
| `plateChangeSwap` | `Take off {off}, add {on} each side` | off, on: String |
| `plateCollars` | `Collars (each)` | |
| `plateColours` | `PLATE COLOURS` | |
| `plateColoursColoured` | `Coloured` | |
| `plateColoursIron` | `Iron` | |
| `plateColoursCustom` | `Custom` | |
| `plateColourOf` | `{w} colour` | w: String |
| `plateColourHint` | `Long-press a plate to change its colour` | |

Reuse the existing keys `perSide`, `justTheBar`, `barWeight`, `targetWeight`, `platePairs`, `platesAll`, `plateAchievable` and `done`. Don't duplicate them.

- [ ] **Step 1:** Add the 15 keys (with `@key` placeholder metadata in `app_en.arb`) to all 17 ARBs.
- [ ] **Step 2:** Run `flutter gen-l10n`. Expected: no errors.
- [ ] **Step 3:** Run `flutter test test/i18n_test.dart`. Expected: PASS.
- [ ] **Step 4:** Commit the ARBs and generated files by path: `feat: add plate calculator strings`.

---

### Task 2: Plate maths, collars, colours and reverse state

**Files:**
- Create: `lib/models/plate_math.dart` (pure Dart, no Flutter imports)
- Create: `lib/theme/plate_palette.dart`
- Modify: `lib/models/place.dart`, `lib/state/places_state.dart`, `lib/state/tools_state.dart`, `lib/state/fit_core.dart` (the default for any new override getter)
- Test: create `test/plates_test.dart`; update the `Plates` group in `test/calculators_test.dart`; extend `test/backup_complete_test.dart` (the place round trip near line 267)

**Interfaces:**
- `lib/models/plate_math.dart`
  - `typedef PlateCount = ({double weight, int count});` Use it in place of the anonymous record type everywhere it appears today.
  - `({List<PlateCount> off, List<PlateCount> on}) plateChange(List<PlateCount> from, List<PlateCount> to)`: the per-side multiset difference, each list sorted heaviest first.
  - `String plateList(List<PlateCount> plates)` gives `"45 ×2 · 25"` style. Use `fmt` from wherever `tools_state.dart` gets it, and keep the existing `plateHint` output format (`45×2 · 25`) for that call site.
- `lib/models/place.dart`: `GymPlace` gains
  - `final double collarKg` (default 0), JSON key `'cl'` (written only when > 0)
  - `final PlateColourBase colourBase` (default `coloured`), JSON `'cb'` (`'iron'` written only when iron)
  - `final bool customColours` (default false), JSON `'cc'` (written only when true)
  - `final Map<double, int> plateColours` (kg → ARGB int), JSON `'pc'` (same key style as `'p'`)
  - plus matching `copyWith` params. `enum PlateColourBase { coloured, iron }` lives in `plate_palette.dart`. `place.dart` may import it, or define the enum in `place.dart` and have the palette import that; choose one, there must be a single definition.
- `lib/theme/plate_palette.dart`
  - Colour constants (exact): blue `0xFF2F6FD6`, yellow `0xFFE8C547`, green `0xFF3BA55C`, white `0xFFEEEEEE`, red `0xFFD9473B`, grey `0xFF777777`, iron `0xFF3A3A3A`, chrome `0xFFC8CCD0`, brassFixed `0xFFB98F72`.
  - `const List<Color> kPlateSwatches` = red, blue, yellow, green, white, iron, grey, brassFixed (8).
  - Coloured lb: 45 blue, 35 yellow, 25 green, 10 white, 5 red, 2.5 grey. Coloured kg: 25 red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 red, 1.25 chrome. Iron: the largest standard size (45 lb / 25 kg) is iron and every other size is `brass` (the theme colour, passed in).
  - `Color plateColour({required double sizeKg, required bool isLb, required PlateColourBase base, required bool custom, required Map<double, int> overridesKg, required Color brass})`. Custom with an override within 0.05 kg wins; otherwise the base preset applies. Look up the display size (`sizeKg × 2.20462` rounded to 0.1 when lb) within 0.05; an unknown size gives grey.
  - `bool plateNeedsOutline(Color c)`: true for light plates (luminance > 0.8), so white shows on the light theme.
- `PlacesState` adds `setPlaceCollar(String placeId, double kg)` (clamp 0–10, `_round3`), `setPlaceColourBase(String placeId, PlateColourBase base)` (also sets `customColours = false` and keeps the overrides), `setPlaceCustom(String placeId)`, `setPlateColour(String placeId, double kg, Color c)` (stores the override and sets `customColours = true`), and `Color plateColourFor(double displaySize, Color brass, {GymPlace? place})` (uses `place ?? activePlace`; no place means Coloured). All persist and notify, like `setPlaceBar`.
- `FitCore` adds `double get placeCollarKg => 0;`, overridden in `PlacesState` as `activePlace?.collarKg ?? 0`.
- `ToolsState` changes:
  - `double? plateBar` (kg; null = gym default) replaces `double plateBar = 20`. `plateBarDisplay` returns the override, else `defaultBar`. `List<double> get plateBarOptions` is `barOptions` plus `defaultBar` when it isn't already one of them, sorted heaviest first.
  - `double get collarsDisplay`: both collars in display units, `2 × toDisplayWeight(placeCollarKg)`, rounded to 0.1.
  - `double collarsFor(String id, {String equipment = 'Barbell'})`: `collarsDisplay` when `equipment == 'Barbell' && !hasOwnBar(id)`, else 0.
  - `platesPerSide(double displayTarget, double displayBar, {double collars = 0})` and `loadableTotal(..., {double collars = 0})`. Per side = `(target − bar − collars) / 2`, floored at 0. `loadableTotal` adds `collars` back in.
  - `plateBreakdown` and `rmAtPct` pass `collarsDisplay`; `plateHint` passes `collarsFor(id, equipment: equipment)`.
  - Reverse: `Map<double, int> reverseCounts` (display size → per-side count), `void bumpReverse(double size, int d)` (floor 0, no max), `void clearReverse()`, `double get reverseTotal` = `plateBarDisplay + collarsDisplay + 2 × Σ size × count`. Changing `units` must clear `reverseCounts`: the setter is in `lib/state/fit_core.dart` (~line 185, `units = u;`). Clear through an overridable hook (e.g. `void onUnitsChanged() {}` in `FitCore`, overridden in `ToolsState`).

- [ ] **Step 1: Write the failing tests** in `test/plates_test.dart`:
  - `plateChange` cases: `225→235 lb` gives off `[]`, on `[5×1]`; `185→205` gives off `[25×1]`, on `[35×1]`; equal lists give both empty; `[]→[45×2]` gives on `[45×2]`.
  - `collars eat into the plates, never below zero`: kg, bar 20, gym collar 2.5 kg, target 100 → plates per side `[25×1, 10×1, 2.5×1]` (37.5); `loadableTotal` 100. Target 22 → `[]`.
  - `exercises with their own bar never get collars`: gym collar 2.5 kg; `setExerciseBar('legpress', 0)`; `collarsFor('legpress', equipment: 'Machine') == 0`; `collarsFor('squat') == 5`.
  - `reverse total adds bar, collars and both sides`: lb, bar 45, no collars; `bumpReverse(45, 1)`, `bumpReverse(35, 1)`, `bumpReverse(5, 1)` → `reverseTotal == 215`; `clearReverse()` → 45.
  - `changing units clears the reverse counts`.
  - `custom colours sit on top of the preset`: iron place; `setPlateColour(place, 20.412, red)` → custom true, and the 45 lb plate is red; `setPlaceColourBase(iron)` → 45 lb is iron and the override is still stored; `setPlaceCustom` → red again.
  - `lb stock and colour overrides resolve through kg keys`: lb units, stock `{20.412: 2}`, so `platePairs` for `fromDisplayWeight(45)` is 2 and `plateColourFor(45, …)` uses the override.
  - `old place JSON loads as coloured with no collars`: `GymPlace.fromJson({'id':'a','n':'Home','e':['Barbell']})`.
  - Round trip: a place with all the new fields set survives `toJson` → `fromJson`.
- [ ] **Step 2:** Update `test/calculators_test.dart` `Plates` for nullable `plateBar` (set `fit.plateBar = 20` stays valid). Extend the backup test so a place with collar, base, custom flag and an override survives backup/restore.
- [ ] **Step 3:** Run `flutter test test/plates_test.dart test/calculators_test.dart test/backup_complete_test.dart`. Expected: FAIL (missing symbols).
- [ ] **Step 4:** Implement the interfaces above.
- [ ] **Step 5:** Run the same tests (PASS), then the full `flutter analyze` and `flutter test` (PASS). Fix any existing call site of the changed signatures so the app still builds; the old plate UI may remain until Tasks 4–6 replace it.
- [ ] **Step 6:** Commit by path: `feat: add plate collars, per-gym colours and reverse maths`.

---

### Task 3: Shared plate widgets

**Files:**
- Create: `lib/widgets/plates/barbell_view.dart`, `lib/widgets/plates/plate_disc.dart`, `lib/widgets/plates/plate_chips.dart`
- Test: create `test/plate_widgets_test.dart`

**Interfaces:**
- Consumes: `PlateCount`, `plateList`, `plateNeedsOutline` (Task 2).
- Produces:
  - `BarbellView({required List<PlateCount> perSide, required Color Function(double size) colourOf, required double largest, double height = 120, bool collar = true})`. One side only: shaft, sleeve, a collar block when `collar`, and plates from the inside out. Plate height = `height × (0.45 + 0.55 × size / largest)`, clamped to `height`. Plate width starts at 16 and shrinks evenly so every plate fits the sleeve. Light plates get a 1 px `gc.border` outline.
  - `PlateDisc({required double size, required Color colour, required int? count, required VoidCallback? onDec, required VoidCallback? onInc, VoidCallback? onLongPress, bool dimmed = false})`. A circle showing the size label on top, a dark hub with the count (`count == null` shows `∞`, for unlimited stock), and − / + hit areas of at least 44 × 44 logical px each. Text colour is dark on light plates. `dimmed` gives 35% opacity. Include `Semantics` labels on − / +.
  - `PlateChips({required List<PlateCount> perSide, required Color Function(double) colourOf})`. A wrap of chips: a colour swatch bar plus `45 ×2` / `25`.
  - `String plateSumLine({required double bar, required double collars, required List<PlateCount> perSide, required double total})`. Returns `t.plateSum` or `t.plateSumCollars` (when collars > 0); the plates part is `45 + 45 + 25`, one term per plate.

- [ ] **Step 1: Write the failing widget tests:**
  - `a 700 lb bar draws without overflow at 320 wide`: pump `BarbellView` with per side `[45×7, 10×1, 2.5×1]` inside `SizedBox(width: 320)`; `tester.takeException()` is null.
  - `a disc's buttons fire and the hub shows ∞ for unlimited stock`.
  - `the sum line reads like the mockup`: bar 45, collars 0, `[45×2, 25×1]`, total 275 → `45 bar + 2 × (45 + 45 + 25) = 275`.
  - Wrap the pumps in `MaterialApp` with the app theme the same way `test/smoke_test.dart` does.
- [ ] **Step 2:** Run `flutter test test/plate_widgets_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the three widgets and `plateSumLine`.
- [ ] **Step 4:** Run it again (PASS) plus `flutter analyze`.
- [ ] **Step 5:** Commit: `feat: add barbell, plate disc and chip widgets`.

---

### Task 4: Plate tool screen (Load + What's on it?)

**Files:**
- Create: `lib/screens/plate_tool.dart`
- Modify: `lib/screens/tool_detail_screen.dart`. For `id == 'plate'`, render `ScreenHeader` + `PlateToolBody()` instead of the generic result card and inputs. Delete the `'plate'` cases in `_meta` and `_inputs`, `_barWeightCard` and `_perSideCard`.
- Test: add to `test/plate_widgets_test.dart`

**Interfaces:**
- Consumes: Task 2 state (`plateBarDisplay`, `plateBarOptions`, `setPlateBar`, `plateBreakdown`, `collarsDisplay`, `loadableTotal`, `reverseCounts`, `bumpReverse`, `clearReverse`, `reverseTotal`, `plateColourFor`, `plateSizes`) and the Task 3 widgets.
- Produces: `class PlateToolBody extends StatelessWidget`, rebuilt by the existing `fit` listener the way other tool screens are.

Layout (spec Goals 1–2): a `SegToggle` with `t.plateTabLoad` / `t.plateTabReverse` (tab index in local state; Load by default).
- **Load:** `BarbellView`; the big total (`fit.weightValue(plateTarget)` + units; tap → `askNumber`); beneath it, the other unit (`124.7 kg` when lb, or `275.6 lb` when kg, rounded to 0.1); a − / + row stepping `plateStep`; a bar choice from `plateBarOptions`; a card with `t.perSide`, `PlateChips` and `plateSumLine`, or `t.justTheBar`; `t.plateAchievable` in `gc.brass` when the stock can't reach the target.
- **What's on it?:** `BarbellView` of `reverseCounts`; `reverseTotal` big, with the other unit under it; the same bar choice; a `t.plateClear` action; a 3-column grid of `PlateDisc`, one per `plateSizes`, wired to `bumpReverse`.
- The page must fit with no horizontal scroll at 320 px width.

- [ ] **Step 1: Write the failing widget tests:** `the plate tool opens on Load and shows the drawn bar`, and `tapping + on a reverse disc raises the total`: lb, bar 45; tap the 45 disc's + → find the text `135`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement and wire it, deleting the old plate code.
- [ ] **Step 4:** Run `flutter analyze` and the full `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: rebuild plate tool with load and reverse tabs`.

---

### Task 5: Between-sets sheet with the change line

**Files:**
- Create: `lib/widgets/plates/plate_sheet.dart` (the new `showPlateSheet`)
- Modify: `lib/screens/tool_detail_screen.dart` (delete the old `showPlateSheet`; `_rmPctCard` imports the new one and passes `collars: fit.collarsDisplay`); `lib/screens/session_screen.dart` (`_plateRow` near line 1675)
- Test: add to `test/plate_widgets_test.dart`

**Interfaces:**
- Produces: `void showPlateSheet(BuildContext context, double displayTarget, {double? startBar, double collars = 0, double? previousDisplay})`.
- The sheet contains a `SheetHandle`, `BarbellView`, the big target, `PlateChips` and a one-row bar picker (`plateBarOptions` plus `startBar` if missing; picking a bar recomputes in local state). Under the chips goes the change line: when `previousDisplay != null`, compute `plateChange(platesPerSide(previousDisplay, bar, collars: c), platesPerSide(displayTarget, bar, collars: c))`. Only `on` → `t.plateChangeAdd(plateList(on))`; only `off` → `t.plateChangeOff(...)`; both → `t.plateChangeSwap(...)`; neither → no line. `t.plateAchievable` shows when needed. A `PrimaryButton(t.done)` closes it. On a 667 pt tall phone everything must be visible without scrolling.
- Session: the "previous set" is the row directly above `next` in `ex.sets` (index − 1), using its `weight`. There is none for the first row. Pass `previousDisplay: fit.toDisplayWeight(prev.weight)` and `collars: fit.collarsFor(ex.id, equipment: exercise.equipment)`.

- [ ] **Step 1: Write the failing widget tests:** `the sheet tells you what to add since the last set` (lb, bar 45, previous 225, target 235 → `Add 5 each side`); `no change line on the first set or an unchanged weight`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement and rewire both call sites.
- [ ] **Step 4:** Run `flutter analyze` and the full `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: show the loaded bar and plate change between sets`.

---

### Task 6: Disc inventory with collars and colours

**Files:**
- Create: `lib/widgets/plates/plate_inventory_sheet.dart`
- Modify: `lib/screens/places_screen.dart`. The "Plates and bar" row calls `showPlateInventory(context, place)`. Delete `_editPlates` and the plate `_plateRow`.
- Test: add to `test/plate_widgets_test.dart`

**Interfaces:**
- Produces: `void showPlateInventory(BuildContext context, GymPlace place)`, a scroll-controlled sheet that always re-reads the place by id from `fit.places`, as `_editPlates` does today.
- Contents, top to bottom:
  1. The title `t.placePlates` and the place name.
  2. The bar `ToolRow` + `StepperControl` (behaviour kept from today).
  3. A collars `ToolRow` (`t.plateCollars`) + `StepperControl`, step 0.5 lb / 0.25 kg in display units, calling `setPlaceCollar`.
  4. `t.plateColours` with a `SegToggle` (Coloured / Iron / Custom). Custom is selectable only once overrides exist; otherwise it's shown disabled.
  5. A `t.platePairs` header, with the `t.platesAll` reset when the stock isn't empty (calls `clearPlates`, unchanged: it never touches collars or colours).
  6. A 3-column grid of `PlateDisc`: count = `platePairs`, or `null` when the stock is empty (∞). `dimmed` when the stock isn't empty and the count is 0. − / + call `setPlatePairs`. `onLongPress` opens a small row of `kPlateSwatches` titled `t.plateColourOf('45 lb')`, which calls `setPlateColour`.
  7. `t.plateColourHint` in `gc.textTertiary`.
  8. `PrimaryButton(t.done)`.
- Colours come from `fit.plateColourFor(size, gc.brass, place: current)`.

- [ ] **Step 1: Write the failing widget tests:** `long-pressing a disc and picking red makes the gym custom` (assert on `fit.places.first.customColours` and the override); `the reset keeps collars and colours`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement it and rewire `places_screen.dart`.
- [ ] **Step 4:** Run `flutter analyze` and the full `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: rebuild plate inventory with discs, collars and colours`.

---

### Task 7: On-device check (controller, not a subagent)

- [ ] **Step 1:** Run the app on the iOS simulator and screenshot the Load tab, the What's on it? tab, the inventory (Iron and Custom) and the between-sets sheet, in dark and light themes and in lb and kg.
- [ ] **Step 2:** Compare against the spec's anti-goals: no overflow, no new icon-library icons, and the sheet fits without scrolling.
- [ ] **Step 3:** A final whole-branch review. Then push `feat-plate-calculator` to `fork` (the feature branch only; never `main`).
