# C3: busy paws + the new homes stall + the sorting rule: done notes (lane c1-c3)

**Status: VERIFIED 2026-09-29** (after the review fixes below; save v24, one bump from C1's 23,
renumber at merge).

Built from docs/plans/C3.md, dev-plan C3 steps 1-2 + the room irritant, picks.md (C3 look A the
stall; C1/C3 points toward a sunny box, any rarity by hand and by rule, keeps; stars only for pets
that leave) and design/mockups/screens/new-homes.html look A. Builds on C1 + the herd (save v23).

## What was built

- **Busy paws.** The one global `jobs_auto` switch ("<pet> shares out new pets", errands shoebox and
  settings) is gone. Each errand and each workers' job (machines, box tables; never adventures,
  whose parties keep their slots and "fill up") has a **"new pets join here"** switch, off by
  default, shown once you have more than 12 spare pets (like the old one):
  - errands: in the shoebox under a "new pets join" heading, one switch per open errand, named
    after it (the notes are already full height: a switch on each note pushed its + / − buttons
    out of view, see question 1);
  - workers: on the job's side card, under "fill up", text "new pets join here".
  New pets (box openings, gifts, pets home from adventures, your old active pet) go to switched-on
  machines with empty spots first (best workers first, `_pick` by `Automation.worker_speed`), the
  rest spread over switched-on errands (smallest crew first). Nothing on: they rest. "Share them
  out" stays as it was (every resting pet over every errand).
- **The new homes stall (look A).** Opens the first time the room is full (unlock `new_homes` ->
  `feature:new_homes`, earn `room: "full"` from a saved `room_was_full`, set by `_room_hit()` when
  the room stops an opening by hand, your pet, box workers or the machine's pet box, or when an
  opening fills it). No popup (`"quiet": true`), your pet mentions it on the home tab.
  - The pets page splits: bookcase (fills) + a 252 px side column with the stall and, later, the
    sorting card. Before it opens the bookcase has the full width. With the column there the
    cushion shows 6 pets, planks stand 3 and the mound is narrower.
  - Tap a plank: picks it for the stall (dashed pink stitched border). Tap the picked plank again:
    opens the shelf. An opened shelf takes the whole width (the side column hides while it's open,
    its sticker needs the room; see question 2). The cushion's pets still open shelves directly.
  - `NewHomesStall`: striped awning (pink seam / pale stripes, odd count so both ends follow the
    rounded corners, scallops), house + "new homes", the from-row (a face, the rarity in its colour,
    how many may go), 1 / 10 / 100 / all ("all" with the pink seam), the box jar (box doodle, lilac
    meter, "14/25") and the pile (three box doodles, `bag[box]`, "starter boxes"). A box dropping
    hops the jar's box and floats "+N".
  - Who can go by hand (`GameState.homes_pick`): plain pets of the shelf's rarity, a plain finish
    at a time (normal before shiny); inside one, resting before working; counts before the oldest
    cards. Never favourites, the active pet, new-part pets, holo and better, pets away, pinned pulls,
    party leaders. Working ones come off their errands / machines first (`_herd_off_places`).
  - Pays points (`NewHomes.pay`): common 1, uncommon 2, rare 5, epic 12, legendary 20, mythic 40;
    25 = one box (data/new_homes.json `box`, starter until B1's sunny box). The jar keeps the rest.
    A starter box's pet is worth ~2.2 points on average (~11 boxes to earn one back).
  - Every take: your pet says "they'll have a big garden!" (voice `homes_cheer`, one line).
- **Stars.** `Collection.leave(counts, uids)` takes pets off for good, a star each (cards their own
  palette; a count's stars take the looks of its next stand-ins, cycled from 16, and `stand_next`
  moves past them), emits `pets_left(n)`; the night skies redraw on it. Sorted pets that never
  join add their star in `Collection.add`. Past `fallen_keep` stars are only counted. Never explained.
- **The sorting rule card (`SortingCard`).** Unlock `sorting` -> `feature:sorting`, earn
  `homes_by_hand: 300` (+ open feature:new_homes). A tilted (-1.2°) index card with a thick lilac
  top edge under the stall: "sorting" + off | on; "new pets" / "below ‹rare›" / "go to ‹new homes›"
  (steppers, never dropdowns); keeps "✦ ‹holo› and up" (finish stepper), "new parts",
  "♥ favourites"; a dashed "sorted today N" tag. Off dims the lines. Off by default.
  - "below" offers uncommon up to the rarest rarity you have; "keep" offers shiny and up, the
    finishes the book has seen (plus whatever it's set to).
  - `Collection.add(pets, sorter)`: after the book counts a pet (so `new_part` is known), before
    `pets_added` / refold. Only box openings pass the sorter (`open_boxes`: by hand, your pet, box
    workers; the machine's pet box). Gifts and debug pets never sort. So only pets pulled after it's
    on are touched. Sorts when rank < below, finish < keep, not new_part, not fav.
  - New homes: the pet never joins (points, a star; it never takes room). The reveal still shows
    everything you pulled ("make it your active pet" hides for a pet that left).
  - Work: the pet joins, then `_place_new` puts it where "new pets join here" is on; if nothing
    took it, it goes over every open errand.
  - "sorted today N": on the card and on each plank under the line, local day
    (`Time.get_date_string_from_system`), saved with the day.
  - `open_boxes` still clamps to the room before rolling (sorted pets just never take room).

## Files

New: `data/new_homes.json`, `scripts/pets/new_homes.gd` (NewHomes), `scripts/ui/new_homes_stall.gd`
(NewHomesStall), `scripts/ui/sorting_card.gd` (SortingCard), `tests/flows/new_homes.flow`.
Changed: `scripts/game_state.gd` (join switches, `_place_new`, `_auto_place(only)`, `_add_workers`,
new homes section, `_room_hit`, save v24 + migration, `homes_paid` signal), `scripts/pets/collection.gd`
(`add(pets, sorter) -> left`, `leave`, `pets_left`, `seen_keys`), `scripts/idle/automation.gd`
(`wjoin`), `scripts/core/catalog.gd` (loads new_homes.json), `data/unlocks.json` (new_homes, sorting,
`quiet`, earn `room` / `homes_by_hand`), `data/voice.json` (homes_cheer, sorting_on/off, join_on/off;
errands_auto_on/off gone), `scripts/ui/unlock_popup.gd` (skips quiet), `scripts/ui/collection_tab.gd`
(side column), `scripts/ui/bookcase.gd` (stall_on, picked, CUSHION_NARROW), `scripts/ui/shelf_plank.gd`
(picked border, narrow, sorted tag), `scripts/ui/errands_tab.gd` (switches in the shoebox,
`ErrandsTab.join_switch`), `scripts/ui/automation_tab.gd` (switch on the worker side card),
`scripts/ui/settings_tab.gd` (share switch gone; the "your pet at work" section hides while empty),
`scripts/ui/night_sky.gd`, `scripts/ui/reveal/reveal_result.gd`, `scripts/ui/ui_theme.gd` (`new_part`
doodle), `scripts/dev/dev_driver.gd`, `tests/test_core.gd`, `docs/design.md`, `docs/architecture.md`.

## Data shape

`data/new_homes.json`: `{ box, box_at, worth: { rarity: points }, takes: [1, 10, 100, -1],
rule_default: { below, to, keep } }`.
Save: top-level `new_homes: { points, by_hand, sorted, room_was_full, rule: { on, below, to, keep },
today: { day, n } }`; `jobs[id].join: bool`; `automation.wjoin: { job id: true }`. `jobs_auto` gone.

**SAVE BUMP: 23 -> 24 (exactly one; renumber at merge).** Migration (in `load_game`, keyed on
`from_version < 24`): `jobs_auto` true -> every open errand's `join` on; a room that's full on load
-> `room_was_full` (+ check_unlocks, so the stall is there). New homes starts fresh otherwise.

## Dev steps (DevDriver)

`homes <rarity> <n|all>`, `rule on|off [below] [to] [keep]`, `join <job> on|off` (errand or workers'
job), `homes-points <n>`, `others <job>` (the other pets know a job: the workers page).

## Flows and tests

New flow `new_homes` (from rich): no stall yet -> fill the room, a box waits -> stall_open -> picked
(uncommon plank) -> 10 then 100 commons (jar "10/25", pile 3 -> 7) box_pop, taken -> all commons ->
300 more by hand: rule_card -> on + a stepper: rule_on -> sorted_reveal / sorted (10 boxes, below
rare, new homes) -> to work + coin hunt joins: join_errands -> workers switch: join_workers ->
shelf_open (stall steps aside, back after) -> a million commons: million, million_gone (1M leave at
once, 40k boxes) -> sky (home), corner_sky (stars). `expect fits` at every view.
Tests: `_test_new_homes` (pay maths, never a box engine, rule line and keeps, today reset, broken
save falls back, leave counts + cards + stars, active never leaves, sorter inside add, the book
still counts) and `_test_new_homes_game` (v23 save: jobs_auto -> joins, full room -> stall; order
resting then working; protected pets; 60 commons = 2 boxes + 10; stars; room freed; all = resting +
working, 4 always-cards stay; sorting card at 300; rule sorts box openings only, keeps new parts /
holo, stars, sorted today, day reset; work -> errands; machines first then errands; no switch ->
rest; adventures never join; round trip; a million leave < 500 ms).
All 25 flows pass (new_homes + every flow in tests/flows). Core tests: ALL PASSED (3348 checks); balance runs clean.

## Text to add

### docs/dev-plan.md (C3)

- C3: **Built 2026-09-29 (lane c1-c3):** busy paws ("new pets join here" per errand, in the shoebox,
  and per workers' job on its side card; replaces jobs_auto), the new homes stall (look A: side
  column, tap a plank to pick, 1/10/100/all, points toward a box 1/2/5/12/20/40 per 25, jar + pile,
  "they'll have a big garden!"), stars for every pet that leaves, the sorting rule card (after 300
  by hand; below / go to new homes or work / keep a finish and up, new parts and favourites always;
  off by default; box openings only; "sorted today"). Save v24. Still to do: feed the machine (F1),
  the sunny box as the pay (B1), room upgrades with the darker currency.

### CLAUDE.md "where we left off"

- C3 new homes (lane c1-c3, save v24, renumber at merge): busy paws = "new pets join here" per
  errand (`jobs[id].join`, switches in the errands shoebox) and per workers' job
  (`automation.wjoin`, side card; never adventures), `GameState._place_new` (machines with room
  first, then errands; replaces `jobs_auto`). New homes stall (`NewHomesStall`, `NewHomes`,
  data/new_homes.json): opens the first time the room is full (`_room_hit`, unlock `new_homes`,
  `"quiet": true` = no popup), pets page side column, tap a plank to pick / again to open,
  `GameState.send_home` / `homes_pick`, points toward a starter box. `Collection.leave` +
  `pets_left` (a star each). Sorting card (`SortingCard`, unlock `sorting` after 300 by hand):
  `Collection.add(pets, sorter)`, `GameState._sorter` (box openings only), `set_rule`,
  `sorted_today`. Dev steps `homes`, `rule`, `join`, `homes-points`, `others`; flow new_homes.

## Questions for Emilia (smallest safe pick used for now)

1. The errand switches live in the shoebox ("new pets join" + a switch per errand) instead of on
   each note: the notes are already full height, and a switch on the note pushed its + / − buttons
   out of view. On the workers' side card it says "new pets join here". OK, or a different spot?
2. An opened shelf takes the whole width, so the stall steps aside while a shelf is open (the
   shelf's sticker needs the room; with the stall too the shelf would be ~3 cards wide). The stall
   stays picked on that shelf when you go back. OK?
3. Tap a plank picks it for the stall; tap the picked one again opens the shelf. OK?
4. Only plain pets go by hand (holo and better stay; the rule's keep stepper can let them go).
5. The stall opens the first time the room is full; the rule card after 300 by hand (placeholder).
6. Pets on jobs can go by hand (resting ones first), since they count toward the room.
7. The stall pays in the starter box until B1's sunny box merges (data/new_homes.json `box`).
8. No finish bonus on points (a shiny common is worth 1 like a plain one).
9. The rule's "below" stepper tops out at "below mythic", so a mythic can never be sorted by the
   rule (only by hand). Add an "any rarity" step?
10. With the numbers from picks, a million commons pay 40,000 boxes at once. Fine as the late-game
    feel, or should the points shrink as the herd grows?
11. The settings "your pet at work" section now hides while it has nothing in it (the share switch
    was its only line for a while).

## Review fixes (after the first pass)

- A good pull the sorting rule sent off is no longer shown by your pet in the corner or pinned:
  `PackJob._pop` shows a pet only if `GameState.pinned` holds it; `tap()` calls
  `GameState.dismiss_pinned(held.uid)` (dismiss_pinned takes an optional uid and removes just that
  one; "" still takes the oldest). `open_boxes` remembers the pets the rule sent home in
  `GameState._sent_home` (last open only), and `_workers_open` skips them for pins and the idle
  log's "good" list.
- `NewHomesStall` no longer works out who may go on every `GameState.changed`: full refresh on the
  collection's herd_changed / pets_added / pets_removed / pets_left / pet_changed / active_changed,
  jobs_changed, automation_changed, adventures_changed, new_game, homes_paid, or a pin count
  change; plain `changed` only redoes the jar and the pile (`_refresh_jar`).
- The pets tab dropped its `pets_left` -> dirty connection (the `changed` key and `pets_added`
  already cover it).
