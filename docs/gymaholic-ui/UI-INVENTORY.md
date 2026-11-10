# Gymaholic — UI Inventory

Captured 2026-11-09 from the running app (`Gymaholic.app`, iOS/iPadOS build 16.7, bundle
`mportal.Gymaholic`) on Apple silicon. Window 1024×800 pt at (0,100); screenshots are 2×
(2048×1600) window-only captures.

> **About this copy.** Only the write-up and the capture tools are in this repo. The screenshots
> (`screens/`), accessibility dumps (`ui/`) and `ui-inventory.csv` it refers to contain personal
> body and training data and are kept locally in `~/workspace/gymaholic-ui/`. The tools expect
> to run from that folder (`~/workspace/gymaholic-ui/tools/`); build the driver with
> `swiftc -O ax.swift -o ax`.

**Contents**

- [Method](#method)
- [Global shell](#global-shell)
- [Screens](#screens)
- [Sheets and modals](#sheets-and-modals)
- [Second pass: everything behind the top-level screens](#second-pass)
- [Control inventory (machine-readable)](#control-inventory)
- [What the data state shows](#what-the-data-state-shows)
- [Limitations](#limitations)

---

## Method

1. Window identified via CGWindowList (id `41184`) and captured with `screencapture -l` so
   overlapping windows (Orca) never contaminate the image.
2. Element geometry comes from the macOS **Accessibility API** (walked with Swift), not from
   eyeballed pixels — positions below are exact screen points.
3. Navigation was coordinate-driven: SwiftUI exposes the sidebar as `AXStaticText`, which cannot be
   pressed, so each nav item was clicked at its AX-reported centre.
4. Sheets were driven with `AXPress` on identified buttons (`Settings`, `Downloads`,
   `ToggleSidebar`) and scrolled with synthesized wheel events.
5. Every screen has a screenshot in `screens/` and a full AX dump in `ui/`.

**Second pass (same day, captures `14`–`107`).** The first pass stopped at the five top-level
screens and three sheets. The second pass opened everything reachable behind them, using
`tools/ax` (a compiled Swift tool) instead of synthesized mouse events:

- `AXPress` is sent straight to the element, so the app is driven **in the background** with no
  cursor movement. The sidebar rows *do* accept `AXPress` even though they are `AXStaticText`.
- Popup menus are opened, captured and cancelled; sheets are paged with the `AXScrollDownByPage`
  action until the tree stops changing (files suffixed `-s1`, `-s2`, …).
- Coordinates in second-pass dumps are normalised as if the window sat at (0,100), so they are
  comparable with the first pass.
- The window must be on the active desktop: macOS exposes no accessibility tree for a window on
  another Space.
- Helpers: `tools/step` (press + capture), `tools/menucap`, `tools/scrollcap`, `tools/reveal`,
  `tools/build_csv.py`.

---

## Global shell

**Expanded sidebar**

| Element | Role | ID / label | Position | Size |
|---|---|---|---|---|
| Sidebar toggle | AXButton | `ToggleSidebar` / "Hide Sidebar" | 181,150 | 27×27 |
| Home | AXStaticText | "Home" | 10,195 | 200×31 |
| Workouts | AXStaticText | "Workouts" | 10,227 | 200×31 |
| History | AXStaticText | "History" | 10,259 | 200×31 |
| My Body | AXStaticText | "My Body" | 10,291 | 200×31 |
| Exercises | AXStaticText | "Exercises" (`magnifyingglass`) | 10,323 | 200×31 |

Sidebar width ≈ 215 pt; content area occupies the remainder.

**Collapsed sidebar** — the nav becomes a centred horizontal tab bar:
`[toggle] Home | Workouts | History | My Body | (search icon)`, with the current section in a
rounded pill. Identifier flips to `ToggleSideBar` / "Toggle sidebar". `screens/10`.

**Window chrome** — standard traffic lights; menu bar is the generic app menu (About, Services,
Hide, Quit) plus File/Edit/View/Window/Help. No app-specific menu items.

---

## Screens

### Home — `screens/02-home.png`

| Region | Controls |
|---|---|
| Toolbar | **Settings** (gear, 31×27 @231,150), **iCloud** (cloud, 34×27 @275,150), **Shop** (cart, 27×27 @985,150) |
| Heading | "Home" |
| Left card | "day since last workout" selector (chevron), "rested muscles" value, empty-state text "No workouts have been tracked yet", 3D body model, three stat buttons: **weight** (`- lbs`), **body fat** (`%`), **Muscles** |
| Bottom bar | flame icon + `0`, "Level 1", chevron |
| Right column | **Training overview** — "Workouts during the last few weeks", SUN–SAT columns × rows 1–6 grid |
| | **Personal records** — "Your peak results", state: "Not enough data." |
| | **Exercises by muscle groups** — "History", more menu (`…`), state: "Not enough data.", footer "Last month" |

### Workouts — `screens/03-workouts.png`

| Region | Controls |
|---|---|
| Toolbar | **Downloads** pill (85×27 @231,150), **Create workout** (`+`, 27×27 @985,150) |
| Heading | "Workouts" |
| Banner | **AI Buddy** button — "From a quick description to a complete training plan." + arrow |
| Section | **Shoulder-focused Program** — collapse chevron, more (`…`) |
| Rows | 4 day rows: *day 4/4* (Shoulder, Traps, Triceps, Abs), *day 2/4* (Shoulder, Biceps, Abs), *day 1/4* (Chest, Lats, Middle Back, Lower Back, Calves, Abs), *day 3/4* (Quads, Hamstrings, Adductors, Abductors, Calves, Abs) |
| Row affordances | green pill toggle, more (`…`), chevron |
| Section | **Nick** (user's own program) — collapse chevron, more (`…`) |
| Rows | Legs · Chest/Back · Shoulders \| High Volume · Biceps /Triceps High Volume · Back \| High Volume — each with a colour bar (red/yellow/blue/purple/green), muscle subtitle, green pill, more, chevron |

### History — `screens/04-history.png`

| Region | Controls |
|---|---|
| Toolbar | calendar icon, **+**, chart icon (right) |
| Content | **Blank** — no heading, no list, no empty-state text |

Worth noting: this is the only screen with no rendered content at all. Either there is no workout
history, or this view fails to draw its empty state.

### My Body — `screens/01-root.png`, `05-mybody.png`, `07-mybody-bottom.png`

| Region | Controls |
|---|---|
| Heading | date "Nov 9, 2026" |
| Week strip | S M T W T F S with day numbers 8–14; selected day is a green filled circle (AX `AXButton` per day, 14 day buttons total) |
| Actions | **Take a photo** (camera, `AXPopUpButton` 62×57 @333,344) · **Your photos** (58×57 @592,344) · **Statistics** (45×57 @857,344) |
| Body metrics | **Weight** (value + `lbs`), **Body fat** (value + `%`) |
| Section | **Measurements** (date shown right-aligned once scrolled) |
| Fields | Neck · Waist · Height, then helper text *"Fill the fields above if you want the app to calculate your body fat %, or directly type in your %."* |
| Fields (cont.) | Shoulders · Chest · Left biceps · Right biceps · Left forearm · Right forearm · Hip · Left thigh · Right thigh · Left calf · Right calf |
| Footer | **Delete measurements** — full-width red destructive button |

### Exercises — `screens/06-exercises.png`

| Region | Controls |
|---|---|
| Toolbar | **Create** pill (59×27 @231,150), **Filter** (hamburger, 27×27 @985,150) |
| Heading | "Exercises" |
| Search | `AXTextField` "Search" (773×27 @235,237) |
| Index rail | right-edge alphabet jump: `3 A B C D E F G H I J K L M N O P Q R S T U V W X` |
| Sections | "3" → *3/4 Sit-Up*; "A" → *Ab Crunch Machine*, *Ab Roller*, *Ab Rollout*, *Adductor stretch with a straight leg*, *Alternate Hammer Curl*, *Alternate Heel Touches*, *Alternate Incline Curl*, *Alternating Cable Shoulder Press* |
| Row anatomy | thumbnail circle, name, "Muscles, Equipment" subtitle, chevron (803×62 hit target) |

---

## Sheets and modals

All sheets share the same frame: dimmed backdrop, **Close** `X` at 299,272 (27×27), rounded panel.

### Statistics — `screens/08-statistics.png`, `09-statistics-scrolled.png`

- Close `X`; title "Statistics".
- Info card: *"Tap to select. Pinch to zoom and swipe to scroll in zoom mode on charts. Use the pin
  button to add the chart to your home screen dashboard."* + dismiss `x`.
- Scrollable list of per-metric charts. Each: metric name, "My Body" subtitle, info icon, **pin**
  icon, y-axis, x-axis Nov→Nov. Observed: **Weight** (112–260), **Neck** (12–20),
  **Shoulders** (118–124).

### Settings — `screens/11-settings.png`, `12-settings-scrolled.png`

- Close `X`; title "Settings".
- **Before you start** card: watch glyph, *"Set up your watch's tracker screen…"*, **Watch Face**
  button, dismiss `x`.
- **iPhone, Apple Watch and Apple TV app**: Shop › · **Units** → `lbs, in` · **My Gender** → `male` ·
  iCloud › · Tracking ›
- Watch: **Watch Face** · **Alarms** · **Heart Rate Zones**
- **iPhone app settings**: **Connect and share** › · **Appearance** → `dark` · **Display at sets** →
  `Last value` · **Color code** › · **Database** › · **Default rest times** ›
- **We need you to keep going** (section, below fold)

### Downloads — `screens/13-downloads.png`

- Close `X`; title "Downloads"; hero image.
- **Featured** carousel: *4-Day Program* (4d, 100m) · *Home Band Workout Beginner* (4d, 40m) ·
  *Home Boxing Workout* (2d, 30m) · *Change your level – Program* (3d, 50m) ·
  *Home Cardio Advanced* (2d, 40m)
- Category rows: Home Bodyweight Workouts › · Home Workouts with Equipments › · Gym Workouts:
  Full body › · …

---

## Second pass

Everything below was captured in the second pass. File names refer to `screens/<name>.png` and
`ui/<name>.txt`.

### Home

| Control | What it opens | Capture |
|---|---|---|
| **iCloud** | Sheet: *iCloud status*, **Sync from iCloud**, **Upload to iCloud**, **Delete all data**, **Log** (tap to copy). None of the action buttons were pressed. | `14`, `15` |
| **Shop** | Sheet titled with the subscription status, image, thank-you text. No purchase UI is shown on a subscribed account. | `16` |
| **day since last workout** | Not a selector: it collapses and expands the last-workout panel. | `18` |
| **weight** button | Navigates to My Body. | — |
| **body fat** button | Menu: *Show body fat* / *Hide body fat* (toggles), *Edit body fat*. | `19`, `20` |
| **Muscles** | Sheet **Muscle regeneration**: Cancel / Save, a tip card, 18 muscle rows each with a recovery time. Tapping a row opens an hours wheel picker. | `21`–`24` |
| **Level bar** | Sheet **Achievements**: level, XP bar, week streak, total XP, unlocked count, personal records, then nine collapsible badge groups — Workout (16), Streak (6), Volume (5), Strength (10), Endurance (13), Variety (6), Dedication (10), Record (12), Special (5). | `25`, `25-s1`…`s4` |
| **Exercises by muscle groups ⋯** | Menu: Week / Month / Year / Remove. | `26` |

### Workouts

The list holds **five** groups, not two: *Shoulder-focused Program*, *Nick*, *Chest-focused
Program*, *4-Day Program* and *Ungrouped* (`67-s1`…`s4`). Each group header has a collapse
chevron (`66`) and a **More** menu: Move to the top, Create workout, Share group, Export (PDF /
CSV), Rename group, Delete group (`39`, `40`).

| Control | What it opens | Capture |
|---|---|---|
| **AI Buddy** | Sheet with *Text* and *Form* tabs. Text: 500-character prompt box, Clear, four tap-to-copy examples. Form: workout-days stepper, Level, Training type, Split, Duration menus, Muscle Groups (20 chips + Clear), Available Equipments (18 chips + Clear), *Open AI Buddy powered by ChatGPT*. **Generate Workout** was not pressed. | `27`, `28`, `34`, `35` |
| AI Buddy menus | Level: Beginner / Intermediate / Advanced. Training type: Strength / Hypertrophy / Muscle endurance. Split: Custom Split / Full Body / Upper/Lower / Push/Pull/Legs / Strength/Powerlifting. Duration: 30m–180m. | `30`–`33` |
| AI Buddy **?** | Sheet **AI Guide**: search, topics *How to Use AI Buddy*, *Suggested Values*, *Privacy*. | `29` |
| **+ Create workout** | Menu: Workout / Workout group / AI Buddy. *Workout* → dialog "Create new workout" (name field, Add exercises, Cancel). *Workout group* → dialog "Create new workout group" (name field, Ok, Cancel). Both cancelled. | `36`–`38` |
| Workout row | Opens the workout screen (below). | `41`, `65` |

**Workout screen** (`41`, full scroll `41-…-full-s1`…`s5`): back button, timer `0:00:00`,
toolbar **Edit rest times** / list-edit / **More**; name field, notes, **Start** / **Statistics**
/ **Share**; a tip card with **Workout help**; then one block per exercise (thumbnail, name,
muscle + equipment, pin, More, SET / LAST / LBS / REPS / ✓ columns, *Add set*, superset link);
**Add exercises** at the bottom.

| Control | What it opens | Capture |
|---|---|---|
| **Edit rest times** | Inline edit mode: a rest-time field per exercise and per set; toolbar button becomes Done. | `43` |
| List-edit (AX label "Compact mode") | Reorder mode: every exercise becomes a row with **Remove** and **Reorder** handles; Done to exit. Nothing was removed or moved. | `44` |
| **More** | Workout help, Workout settings, Tracking settings, Share workout, Export (PDF / CSV), Edit workout name, Delete workout. | `45` |
| Workout help | Sheet with search and nine topics; each topic drills into sub-topics. | `47`, `48` |
| Workout settings | Popover: colour swatches ("Color code") and an activity-type wheel ("save to Health app as"). It renders partly outside the 1024-pt window. | `49`, `49b` |
| Tracking settings | Sheet **Tracking**: Auto-play, Audio Workout, Skip rest with a tap, Timer seconds +/- (15 / 30 / 45 / 60). | `50`, `51` |
| **Statistics** | Sheet with eight charts for this workout: Number of Workouts, Weight lifted, Sets by muscle groups, Repeats per workout, Exercises by muscle groups, Total workout duration, Workout kcal, Average heart rate. Each chart has a Week / Month / Year menu. | `52`, `52-s1`…`s5`, `53` |
| **Share** | The macOS share popover (AirDrop, Notes, Messages, Save, Copy…). Dismissed without sharing. | `54` |
| Set cell | Custom keypad docked at the bottom: digits, decimal, delete, four function keys, COPY, − / +, NEXT. Dismissed without entering a value. | `55` |
| Exercise **More** | Add Notes, Add time, Warm up / Drop / Pyramid set, Exercise sheet, Replace exercise (All exercises / Alternatives / Suggestions), Delete exercise. | `56` |

**Exercise sheet** (`58`; the same sheet opens from the Exercises list, `82`): Close, **Select
tags**, name, muscle and equipment icons, and four tabs.

| Tab / control | Content | Capture |
|---|---|---|
| About | Edit button, muscle, equipment, type, category, description. | `59-…-about` |
| History | One card per past session: date, numbered sets, weight × reps, estimated 1RM. | `59-…-history`, `-s1`…`s4` |
| Records | Personal records (1RM, Weight, Max. Volume, Time) and a ranked table. | `59-…-records`, `-s1`, `-s2` |
| Statistics | Per-exercise chart sheet (Completed exercises, Total volume, Best set, 1RM per workout, Repeats, Time…). | `59-…-statistics`, `-s1`…`s4` |
| Select tags | Small sheet; empty on this account apart from a filter toggle. | `60` |
| Edit | Form **Edit exercise**: name, Muscle, Secondary muscles, Equipment, Type (Reps / Time / Distance), Category (Strength / Cardio / Stretch / Balance), Camera (Delete media / Select from library / Take a photo or video). Cancelled. | `61`–`64` |

### History

The list view is still blank on this account (`68`), but the toolbar works:

| Control | What it opens | Capture |
|---|---|---|
| **Calendar** | Continuous month calendar with the year in the toolbar and today circled; the button flips to **List**. | `69` |
| **+** (Create new log) | Dialog "Create new log": name field, Create, Cancel. Cancelled. | `70` |
| **Statistics** | Chart sheet across all history (same chart set as the workout sheet, scoped to History). | `71`, `-s1`…`s4` |

### My Body

| Control | What it opens | Capture |
|---|---|---|
| **Take a photo** | Menu: Take a photo / Select from library. | `72` |
| **Your photos** | Sheet **My Body**: Close, Edit, lock toggle, More (Change active album, Create new album, Rename album, Delete album), Take a photo, Transformation video, tip card. No photos on this account. | `73`, `74` |
| Transformation video | Screen with **Create video**, Orientation (portrait / landscape) and an FPS slider. | `75`, `76` |
| **Statistics** | 16 charts: Weight, Body fat, Neck, Shoulders, Chest, both biceps, both forearms, Waist, Hip, both thighs, both calves, Height. | `77`, `-s1`…`s9` |

### Exercises

| Control | What it opens | Capture |
|---|---|---|
| **Create** | Form **Create exercise** — same fields as Edit exercise. Cancelled. | `78` |
| **Filter** | Panel with *Simple* / *Advanced* tabs, Clear, Done and a tag toggle. Simple: 8 muscle regions, 7 equipment types, 4 categories. Advanced: 18 muscles, 15 equipment types, 4 categories. | `79`, `80` |
| Exercise row | The exercise sheet described above. | `81`, `82` |

### Settings

Full row list, top to bottom (`83-top`, `83-s1`…`s3`): tip card with Watch Face; **Shop**,
**Units**, **My Gender**, **iCloud**, **Tracking**, **3D & AR**; *Apple Watch app settings*:
**Watch Face**, **Alarms**, **Heart Rate Zones**; *iPhone app settings*: **Connect and share**,
**Appearance**, **Display at sets**, **Color code**, **Database**, **Default rest times**; *We
need you to keep going*: **Rate this app**, **Tell a friend**, **Provide feedback**.

| Row | Content | Capture |
|---|---|---|
| Units | Menu: lbs, in / kg, cm. | `84` |
| My Gender | Menu: male / female. | `85` |
| Appearance | Menu: automatic / light / dark. | `86` |
| Display at sets | Menu: Last value / 1RM / Personal Record. | `87` |
| Watch Face | Watch image with three tap-area menus (each: Next set, Next set + edit previous, Next set + impulsive rest time, Undo set, Exercise details, Edit current set, Edit all sets), explanatory text, impulsive-rest interval field. | `88`, `96` |
| 3D & AR | 3D Model (male / female), Model's appearance (green / realistic 1 / realistic 2), Model's height (my height / medium / small), Apple TV Background (living room / fitness room). | `89`, `97`–`100` |
| Alarms | Alert checkboxes for heart-rate Zones 1–5; weak rest and weak heart-rate haptic toggles. | `90` |
| Heart Rate Zones | Automatic toggle, resting and maximum values, five zone ranges. | `91` |
| Connect and share | Strava and Fitbit toggles. | `92` |
| Color code | Menu muscles / workouts, with explanatory text. | `93`, `101` |
| Database | "Complete exercise database" language list: English, French, German, Spanish, Portuguese, Chinese (Simplified and Traditional), Japanese, Arabic, Turkish. | `94`, `-s1`…`s3` |
| Default rest times | Rest between sets and between exercises (seconds), long help text. | `95` |

### Downloads

Four category rows expand in place (`103`, `105`–`107`); a program opens a detail page
(`104`) with a download button, days, duration, level, info, muscles, equipment and a
disclaimer. Nothing was downloaded.

- **Featured:** 4-Day Program, Home Band Workout Beginner, Home Boxing Workout, Change your
  level – Program, Home Cardio Advanced.
- **Home Bodyweight Workouts:** Home Cardio Beginner, Home Cardio Intermediate, Home Warm up and
  Stretching, Woman Workout Beginner, Woman Workout Intermediate.
- **Home Workouts with Equipments:** Home Band Workout Intermediate / Advanced, Home 50+ Band
  Workout, Home Woman Band Workout, Home Dumbbell Beginner / Intermediate.
- **Gym Workouts: Full body** and **Gym Workouts: Area focused:** Basic Beginner / Intermediate
  / Advanced Program, Advanced Long Week Program, Advanced Program, 1h/Day Full Week Plan,
  Chest-focused Program, Shoulder-focused Program, two leg-and-glute programs for ladies.

---

## Control inventory

- `ui-inventory.csv` — 7,537 rows across 171 captured states (2,137 rows from the first pass,
  the rest appended by `tools/build_csv.py`):
  `screen, role, identifier, description, title, value, position, size`.
- `ui/*.txt` — raw AX dumps per screen (includes OS menu-bar items; filter `AXMenuItem` /
  `AXMenuBarItem` to isolate the app).
- `screens/*.png` — 172 screenshots plus two diagnostics.

App-level roles observed: `AXWindow`, `AXButton`, `AXPopUpButton`, `AXStaticText`, `AXHeading`,
`AXTextField`, `AXGroup`. Notably **no `AXTabGroup`, `AXTable` or `AXList`** — the app draws its own
layout, which is why only labels and a handful of buttons are exposed.

---

## What the data state shows

These are UI *states*, not conclusions about your account:

- Home: "No workouts have been tracked yet"; Personal records "Not enough data."; Exercises by
  muscle groups "Not enough data."
- History: completely blank.
- My Body: populated with measurements and a "Delete measurements" action.
- Exercises: full catalogue, alphabetized.
- Workouts: five groups — "Shoulder-focused Program", the user group "Nick", "Chest-focused
  Program", "4-Day Program" and "Ungrouped" (the first pass saw only the first two).
- Workout and exercise screens show past sets and records even though Home and the History list
  report no tracked workouts.

Personal health values (body measurements, heart-rate figures, lifting history) appear in the
screenshots, the AX dumps and the CSV; they are stored only under `~/workspace/gymaholic-ui/`
and are deliberately not transcribed into this document.

---

## Limitations

- **SwiftUI limits the AX tree.** Custom-drawn content (charts, the 3D body, colour swatches,
  wheel pickers, the keypad keys) has no accessible children, so those are documented from the
  screenshots only.
- **Not reachable in the background:** the per-row **⋯** and watch icons in the Workouts list
  (a click there falls through to the row), the **LAST** column selector (pressing it changed
  nothing visible), and the pin toggles (left alone because they change the Home dashboard).
- **Deliberately not exercised**, because they change or send data: Start workout, Add set, set
  completion, Generate Workout, Create / Ok / Done in the create and edit dialogs, any delete or
  remove action, Sync / Upload / Delete in iCloud, photo capture, Create video, program
  download, export and share targets, the Strava and Fitbit toggles, and the three Settings rows
  that leave the app (Rate this app, Tell a friend, Provide feedback).
- **Help content is sampled.** One Workout help topic was opened; the remaining topics and the
  AI Guide topics were listed but not read.
- **One workout and one exercise stand in for the rest.** The other workouts and the full
  exercise catalogue use the same screens with different data.
- **History list renders nothing** on this account, so only its toolbar screens are documented.
- The app is an **encrypted iOS binary**, so UI structure cannot be confirmed against code.
