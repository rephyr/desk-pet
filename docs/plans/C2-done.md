# C2: past the edge + the little school: done notes (lane edge)

Built from docs/plans/C2.md, picks.md (C2/F3 in "Brainstorm 2 picks", "Look picks, round 2") and the
mockup past-the-edge.html look A (the tucked page, the classroom). On top of C1's herd.

**Status: VERIFIED 2026-09-29** (tests, balance and all flows pass; edge + school flows checked with
`expect fits`). Save v24 on this lane, renumber at the merge.

## What was built

- **The edge (adventures tab, beyond-the-fence page).** Hidden until earned: unlock `edge` opens
  `feature:edge` once every place on the beyond page is open (new earn key `all_places: "beyond"`),
  or earlier by saying yes to a new rumour `edge` ("where the map stops", needs `page:beyond` +
  `location:orchard`; drawn as a rumour cloud where the signpost will be). Popup "new: the edge!".
  - The map paper stops `peek` (30%) short with a torn right edge (drop shadow). The next page is
    tucked under the tear (tilted 2.2 degrees) and peeks out with the number to go ("500" + "to
    go", outlined in paper colour) and a crayon scribble per pet sent, in their palette colours (up
    to `marks_max`, then spread). No outline of what's coming. A crayon signpost "the edge" sits on
    the tear; it glows (like a new place) until the first pet goes.
  - The torn page is redrawn narrower with its own layout (data/edge.json `layout`, the mockup's
    arrangement); the edge's spot stays in the fit once it's gone, so nothing jumps.
  - Tapping the signpost circles it and shows `EdgeCard` at the top of the right column (above
    "away"): the shelves of resting herd pets (a row per rarity with a face and the count, tap to
    pick), 1 / 10 / 100 / all. Only counts, never cards; plainest finish first. "all" stops at the
    number to go. A few faces fly off to the signpost. Your pet always says "they'll draw the rest of
    the map!".
  - Each pet is gone for good: off the herd (`Collection.take_plain`, stand-in numbers skip past
    their looks), a night-sky star each (`Collection.add_stars`, 64 colours kept per send, the rest
    counted). When the page is full, `Edge.add` moves to the next page and `check_unlocks` opens the
    unlock `next_door` (`opens: ["page:next_door"]`, `earn: { "edge": "next_door" }`) with **no
    popup** (an entry without `popup` opens quietly now: UnlockPopup skips it). After the last page
    in data: sheet and signpost gone, the tear stays (nothing teased).
- **The little school (automation tab).** Unlock `school` opens `feature:school` at
  `earn: { "edge_sent": 100, "open": "tab:automation" }`; popup "new: the little school!" (show me
  goes to automation).
  - The switch is `your pet | workers | school` (each page only when it's there; the school button
    has a little house icon). `AutomationTab` pages are strings now (`pet`, `workers`, `school`),
    the switch rebuilds when a page turns up; `AutomationTab.show_page(id)`.
  - `SchoolView` (look A): the classroom (paper panel): chalkboard with the newest teacher (your
    active pet before any), "class N" and the chalk "+2.9%" (the step this class would give, blank
    when empty); 24 desks (6 x 4) filling in proportion (every kind in the class gets a desk,
    rarest first; the desk top is drawn over the pet); the teachers row (newest first, up to
    `teachers_shown`, only as many as fit the width; hidden before the first class). Side card:
    "the little school", "every worker x1.10", "class 5 / 60 of 900" + meter, the same shelf rows +
    1/10/100/all (capped at the seats left), and "ring the bell" at the bottom: disabled until the
    class is full, then pink with a glow and a wiggle. You ring it: confetti, jackpot sound, the
    class becomes a teachers group, its pets become stars, the next class starts, the x number bumps.
    Lines never change: `school_cheer` "class is in! everybody sit nicely.", `school_full`
    "everyone's here! ring the bell!", `school_bell` "ding ding! the new teachers are so proud.".
  - Seated pets are off the herd already (at school); the bell makes them stars.
  - **The boost** `GameState.school_boost()` = product over classes of (1 + step / 100). It
    multiplies `workers_speed(id)` (machine workers and box workers) and `job_rate(job)` (errand
    crews). Not your pet's own crank, not worker parties.
- **Pets a minute** (dev-plan C2): a pill at the top of the automation tab once box workers exist
  (`GameState.pets_a_minute()`: box workers' boxes a minute, a box is one pet; 0, so the pill hides, with
  a full room or no box on the pile they may open); on the school page it
  takes the "your pet is ..." pill's place.

## Files

New: `data/edge.json`, `data/school.json`, `scripts/adventure/edge.gd` (Edge), `scripts/idle/school.gd`
(School), `scripts/ui/herd_picker.gd` (HerdPicker: shelf rows + 1/10/100/all, used by both),
`scripts/ui/edge_card.gd` (EdgeCard), `scripts/ui/school_view.gd` (SchoolView, Desk),
`tests/flows/edge.flow`, `tests/flows/school.flow` (+ their .uid files).
Changed: `scripts/game_state.gd`, `scripts/pets/collection.gd` (take_plain, add_stars,
stars_added), `scripts/core/catalog.gd` (loads edge.json, school.json), `scripts/ui/map_view.gd`,
`scripts/ui/adventures_tab.gd`, `scripts/ui/automation_tab.gd`, `scripts/ui/night_sky.gd` (redraws
on stars_added), `scripts/ui/ui_theme.gd` (doodles sign, school, bell), `scripts/ui/unlock_popup.gd`
(no popup for entries without one), `scripts/dev/dev_driver.gd`, `data/unlocks.json` (entries edge,
school, next_door; note), `data/adventures.json` (rumour edge), `data/voice.json` (edge_cheer,
school_cheer, school_full, school_bell), `tests/test_core.gd`, `docs/design.md`, `docs/architecture.md`.

## Data shape

- `data/edge.json`: `{ pages: [{ id: "next_door", need: 500 }], page: "beyond", map: { x, y }
  (the signpost / rumour spot on the normal page), peek: 0.3, layout: { place id or "edge": [x, y] }
  (the torn page), marks_max: 520, stars_kept_per_send: 64 }`
- `data/school.json`: `{ sizes: [40, 100, 220, 450, 900], grow: 2.0, round: 10, desks: 24,
  points: { common 1, uncommon 2, rare 5, epic 12, legendary 20, mythic 40 },
  step: { base: 1.0, per_point: 1.4 }, teachers_shown: 4, stars_kept: 64 }` (stars_kept: star colours
  kept one by one when the bell rings; the edge has its own stars_kept_per_send)
- New unlock earn keys (GameState._earned): `all_places` (page id), `edge` (page id full),
  `edge_sent` (pets ever sent). New features: `feature:edge`, `feature:school`.

## Save

**SAVE BUMP: 23 -> 24 (exactly one; the merge step renumbers it).**
- top level `edge`: `{ page: pages filled, sent: pets on the page being filled, ever: every pet
  sent, marks: [palette ids, one per scribble] }`
- top level `school`: `{ seated: { "common:normal": n }, classes: [{ size, step, faces: [3
  stand-in uids "h:<key>:<negative n>"] }] }` (`GameState.school_face(key, n)` = number
  `-1 - n`: live stand-ins count up from 0, so no clash at any herd size)
- Migration: nothing at dict level; older saves load `Edge.clean` / `School.clean` of nothing =
  fresh. Loading cleans odd values (unknown palettes become "", sizes/steps clamped, bad keys
  dropped); a class with more pets than seats gives the extra back to the herd (`School.trim`); a
  saved `sent` at or past the page's `need` (a later build lowered it) opens the page, the rest
  carry on. After every load `check_unlocks` runs deferred (existing saves that already earned the
  edge or the school get them, with the popup, right away).

## GameState API (new)

`edge_open()`, `edge_torn()`, `edge_to_go()`, `edge_done(page_id)`, `all_places_open(page_id)`,
`resting_shelves()` (rarity -> resting herd pets), `send_past_edge(rarity, n)` (-1 = all),
`school_open()`, `seat_in_school(rarity, n)` (-1 = every seat left), `class_full()`, `ring_bell()`,
`school_boost()`, `pets_a_minute()`, signals `edge_changed`, `school_changed`. `follow_lead` and
`follow_rumour` now call `check_unlocks`; `check_unlocks` drops waiting rumours whose unlocks are
all open (the edge's rumour once the edge opened by itself).

## Dev steps (DevDriver)

`map-page <id>`, `edge` (taps the signpost), `edge-send <rarity> <n | all>`, `rumour <id>`,
`lead <place>` (spotted + followed), `seat <rarity> <n | all>`, `bell`, `classes <n>` (finished
classes of commons, free).

## Review fixes (same step)

- `pets_a_minute()` is 0 (pill hidden) with a full room or no openable box on the pile; the school
  flow checks the pill is gone first, then gives room + boxes.
- SchoolView rebuilds only on `school_changed`, `active_changed` or a resize; the picker's counts
  update every frame. HerdPicker rebuilds its rows only when a rarity comes or goes, otherwise sets
  the count labels in place (no flicker, hover kept).
- `check_unlocks.call_deferred()` after a load (in `_init`).
- School faces use negative stand-in numbers (`school_face`); `SCHOOL_FACES` / `DESK_FACES` gone
  (`GameState.STAR_FACES`, `GameState.DESK_FACES` are offsets inside the negative range).
- The school reads `stars_kept` from data/school.json.
- `school_boost()` returns a cached value (`school_changed_boost()`).
- EdgeCard's flying faces hang off the adventures tab (`fly_host`), centred by their minimum size.
- `Edge.clean` opens a page whose need dropped below the saved `sent`.

## Flows and tests

- `tests/flows/edge.flow`: rumour cloud, the popup when the last place opens, the torn map with
  "500 to go", the card after tapping the signpost, after 100, after a mix, all (page full: sheet,
  signpost and card gone). `expect fits` everywhere.
- `tests/flows/school.flow`: the popup after 100 past the edge, the empty class, 40 seated in a mix
  (bell glowing, "everyone's here!"), the bell (confetti), rang ("x1.03", teachers row, "0 of
  100"), class 2, a million herd pets with 4 classes done, then box workers and the pets a minute
  pill (workers page and school page). `expect fits` everywhere.
- Every flow in tests/flows passes (26), no script errors.
- `tests/test_core.gd`: `_test_edge` (pure), `_test_school` (pure), `_test_edge_school_game`
  (v23 save loads fresh; hidden until earned; the rumour path opens it quietly; the last place
  opens it with a popup and drops the waiting rumour; only resting herd pets go, never cards or
  errand pets; stars and herd; to go; the school waits for the automation tab; "all" never
  overfills; next door opens once; seats cap; bell only when full; boost x1.024 on workers_speed and
  job_rate; save round trip; a million pets: 12 classes in ~100 ms). ALL PASSED (3364 checks).
  Also allowed in existing checks: rumours may point at `page:` / `feature:` ids, unlocks may open
  `feature:edge`, `feature:school` and pages past the edge.
- `tools/balance.gd` runs unchanged.

## Merge notes

- **Next door lane:** its unlock should use `earn: { "edge": "next_door" }` (replace my quiet
  `next_door` entry, add its popup) and add the `next_door` page to data/unlocks.json "pages". The
  core test lets `page:<id>` of a page in data/edge.json count as real; once the page exists that's
  moot. After next door exists, a full edge page shows its bookmark tab; the edge's sheet then goes.
- **C3 (new homes + sorting rule):** the sorting rule gets "go to: school": call
  `GameState.seat_in_school(rarity, n)` style logic per new plain pet while there are seats left
  (School.seat on counts). `HerdPicker` (shelf rows + 1/10/100/all over `resting_shelves()`) can be
  reused by the new homes stand.
- **B2 boosts:** `school_boost()` should become a source of `boost("workers")` and show on the
  receipt ("the little school x1.10"); today it multiplies `workers_speed()` and `job_rate()`
  directly (search "school_boost()").
- **Save:** v24 here; renumber at the merge (only the comment in `_migrate` and the docs mention 24).
- ui_theme.gd DOODLES gained `sign`, `school`, `bell` (other lanes may add icons at the same spot).
- AutomationTab `_page` is a string now (`"pet"`, `"workers"`, `"school"`); a lane adding the whistle
  page adds `"whistle"` to `PAGE_NAMES` and `_refresh_pages`.

## Text to add

### docs/dev-plan.md

- C2: **Built 2026-09-29 (lane edge):** past the edge (look A, the tucked page: the torn beyond
  map, the signpost "the edge", the next page tucked under it filling with scribbles, "N to go",
  the edge card with the shelves and 1/10/100/all; pets never come back, a star each; 500 opens
  next door via the quiet `next_door` unlock hook) and the little school (look A, the classroom:
  `your pet | workers | school`, classes 40/100/220/450/900/x2 fill 24 desks, you ring the bell,
  every worker x(1 + step) per class, step from the class's stand points). Pets a minute pill once
  box workers exist. Save v24 (renumber). Open: the questions below.
- F3: the first pet sinks are built (the edge, the school); the sacrifice machine (F1) is next.

### CLAUDE.md "where we left off"

- C2 past the edge + the little school (lane edge, save v24, renumber at merge): `feature:edge`
  opens when every beyond place is open (earn `all_places`) or via rumour `edge`; MapView tears the
  paper (data/edge.json peek, layout), draws the tucked page's scribbles (`GameState.edge.marks`) and
  the signpost (`MapView.EDGE_ID`, `edge_picked`); `EdgeCard` + `HerdPicker` send resting herd pets
  (`GameState.send_past_edge`, `Collection.take_plain` / `add_stars`); a full page opens the quiet
  `next_door` unlock (earn `edge`; entries without popup open quietly). The school
  (`feature:school`, earn `edge_sent` 100 + tab:automation): `SchoolView` on the automation tab's
  school page (pages are strings now), `School` rules, data/school.json, `seat_in_school`,
  `ring_bell`, `school_boost()` multiplies workers_speed and job_rate (B2 takes it over). Pets a
  minute pill (`pets_a_minute`). Dev steps map-page, edge, edge-send, rumour, lead, seat, bell,
  classes; flows edge, school.

## Questions for Emilia (smallest safe pick used for now)

1. Does the school speed up errand crews too, or only automation workers? (Picked: machine workers,
   box workers and errand crews; not your pet's own crank, not worker parties.)
2. When does the school open? (Picked: after 100 pets past the edge, once the automation tab is there.)
3. Stand points: mythic 40 (placeholder), and the finish doesn't count (a shiny common is 1).
4. Worker parties on adventures don't get quicker from the school for now. Should they?
5. Only the next-door page is in the data; later pages (x50-100) come with their own content.
6. The torn page redraws the beyond map in the mockup's layout (places move a little when the edge
   opens). OK, or keep the old positions and squeeze?
7. The edge card shows when you tap the signpost (like a place's card), not all the time on the
   beyond page. The signpost glows until the first pet goes.
8. The popup for the edge says pets "don't come back" (the one place that says it out loud, since
   it's a big choice). Keep or cut?
