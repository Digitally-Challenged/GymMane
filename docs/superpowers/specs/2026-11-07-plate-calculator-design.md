# Plate calculator rebuild — design

Date: 2026-11-07 · Branch: `feat-plate-calculator` · Status: draft for Nick's approval

## Why

Nick stopped using GymMane's plate calculator. Today it is a target-weight stepper, a
bar-weight row and a plain-text "per side" list (`lib/screens/tool_detail_screen.dart:160`,
`showPlateSheet` at `:446`). He uses *Bar Is Loaded* instead, and relies equally on its
three parts: a picture of the loaded bar, a reverse calculator ("what's on this bar?"),
and a plate inventory. Success = he stops opening the other app.

We borrow Bar Is Loaded's **functions and layout ideas**, not its look: no red header, no
copied branding or art. Everything renders in GymMane's own theme (`lib/theme/`).

## Goals

1. **Load tab** (calculate). Target weight → a drawn barbell with plates in the active
   gym's colours, plate chips for one side ("45 ×2", "25"), a one-line sum
   (`45 bar + 2 × (45 + 45 + 25) = 275`), and the total in the other unit beneath the main
   number (lb main → kg below, and vice versa). Keep: ± stepper by `plateStep`, tap the
   number to type it, bar choice from `barOptions`, the existing "Closest you can load"
   warning when stock can't reach the target.
2. **What's on it? tab** (reverse). A grid of round plate discs, one per size, with − / +
   and a per-side count in the hub. Shows the drawn bar and the total
   (bar + collars + 2 × plates). A Clear action resets counts. No upper limit.
3. **Inventory, per gym.** Rebuild the plate editor in `places_screen.dart` (`_editPlates`,
   `_plateRow`) as the same disc grid: bar weight, **collars** (new), pairs owned per size.
4. **Plate colours, per gym.** In the inventory: a three-way choice **Coloured / Iron /
   Custom**. Long-press a disc → a short fixed row of swatches (no colour wheel). Changing
   any plate's colour sets the gym to Custom. Coloured and Iron are presets.
5. **Two entry points, one look.** The tool screen (Tools → Plates) holds both tabs. The
   between-sets shortcut (`session_screen.dart:1675` `_plateRow` → `showPlateSheet`) opens
   a sheet with the drawn bar, chips and total for that set, plus a **change line** against
   the previous set of the same exercise: "Add a 25 each side", or
   "Take off 25, add 35 each side". Hidden on the first set or when the weight is unchanged.
   The 1RM tool's `_rmPctCard` keeps opening the same sheet (no change line there).

## Non-goals

Sharing, meet-prep tools (attempts, sticking points), Wilks/DOTS changes, app themes,
barbell skins, Apple Watch / Wear OS plate views, new plate sizes beyond today's
`_plateSteps` lists, syncing places to the backend (places stay local, as today).

## Anti-goals (fail even if it "works")

- It looks like Bar Is Loaded (their red, their layout chrome, their art).
- New generic icon-library icons or emoji. Draw the bar and discs ourselves
  (CustomPainter / shapes). Existing Phosphor icons elsewhere stay untouched.
- Between sets it's slower than glancing at today's hint row: the sheet must answer
  "what do I put on?" without scrolling on a phone.
- Existing users' saved gyms, plate stock or backups break or change meaning.

## Decided

- **Colours live on `GymPlace`** (`lib/models/place.dart`): a preset
  (`coloured` | `iron` | `custom`) plus per-size overrides keyed by kg, like `plates`.
  New JSON keys are optional; old JSON loads as Coloured with no collars. Must round-trip
  through backup/restore (`test/backup_complete_test.dart`).
- **No active gym** → Coloured preset, no collars, unlimited plates (today's behaviour).
- **Custom = base preset + overrides** *(Claude's call)*. `GymPlace` stores the base
  preset (`coloured` | `iron`), the overrides map, and whether Custom is selected. Custom
  shows the base preset with the overrides on top. Tapping Coloured or Iron sets the base
  and turns Custom off, but keeps the overrides, so tapping Custom brings them back. Nothing
  is deleted without the user asking.
- **Collars** are stored on `GymPlace` as weight per collar in kg (default 0), always
  counted twice. They apply only when the lift uses the gym's barbell: equipment `Barbell`
  and no per-exercise bar (`hasOwnBar` false) *(Claude's call)*. Plate-loaded machines and
  specialty bars never get collars. Within that rule they count in `platesPerSide`,
  `loadableTotal`, `plateHint`, `rmAtPct` and the reverse total. Default 0 means no change
  for existing users.
- **Bar source** *(Claude's call)*. The Load and What's on it? tabs share one bar
  setting. It defaults to the active gym's bar (`defaultBar`), and that bar is added to
  `barOptions` when it isn't already one of them. The between-sets sheet keeps a one-row bar
  picker that starts at `barFor(exercise)`, as it does today.
- **Empty stock still means "everything available"** (`plateStockKg` returns null). Keep the
  existing "Everything available" reset. It clears the plate stock and the bar, as today,
  and never touches collars or colours *(Claude's call)*. A size with 0 pairs in a non-empty
  stock is dimmed in the inventory and never used.
- **Preset colours.** Coloured, lb: 45 blue, 35 yellow, 25 green, 10 white, 5 red,
  2.5 grey. Coloured, kg (IWF): 25 red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 red
  (small), 1.25 chrome. Iron (the version Nick saw in the mockup): the largest standard
  size (45 lb / 25 kg) is solid dark grey, and every smaller size is solid `brass` in the
  current theme. Each plate is one colour; there is no separate accent. White plates get a
  thin outline so they show on the light theme. Overrides are stored as fixed colour values.
- **Plate drawing:** plate height scales with weight; one side shown, sleeve and collar
  drawn; it must fit 8+ plates without overflowing (shrink widths).
- **Change line** = the per-side multiset difference between the previous set's loading
  and this one, on the same bar. "Previous set" means the row just above it in this
  session, using its logged weight. If the plates are the same, the line is hidden.
- Replace the old plate UI completely: delete `_barWeightCard`, `_perSideCard` and the old
  `showPlateSheet` body. No parallel version.
- Every new string goes into **all 17 ARBs** in `lib/l10n/`. `test/i18n_test.dart`
  fails otherwise.

## Left to the builder

- Widget structure and file split (a `lib/widgets/plates/` folder is a reasonable home;
  keep files < 400 lines). Whether the plate tool keeps `ToolDetailScreen`'s header frame
  or gets its own body.
- Exact swatch list (about 8, including the preset colours and `brass`), disc sizing, and
  animation.
- Whether reverse-tab counts persist between visits (in-memory is fine).
- Translation method for the new strings: follow whatever the repo's recent l10n commits
  did.

## Verification

- Unit tests (write these first): collars in `platesPerSide`/`loadableTotal`; the reverse
  total; the change-line diff (225→235, 185→205, unchanged, first set); colour preset
  and override resolution; old-JSON load and round trip for `GymPlace`.
- Widget smoke tests: the plate tool renders both tabs, and the session sheet renders.
- `flutter analyze` and `flutter test` green. A screenshot of each surface on the iOS
  simulator, light and dark, lb and kg.
