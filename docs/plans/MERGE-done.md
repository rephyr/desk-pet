# MERGE done: lanes/prices into lanes/house

**Status: VERIFIED 2026-09-29** (after the review fixes below; SAVE_VERSION 26 = house v23/v24 +
prices v25/v26, renumber again at the final merge).

lanes/house (C1 the herd + C3 new homes) now also has lanes/prices: A3 (savings jar, kitchen,
scouting) and PRICES (errand tools, boxes and your pet's box reserve priced in capsules). One
`git merge --no-ff lanes/prices`; the conflicts were resolved keeping both sides.

## Save chain (SAVE_VERSION 26, one line, each migration its own number)

| v | from | what |
|---|------|------|
| 23 | house C1 | the herd (load_game `from_version < 23`: refold, room margin) |
| 24 | house C3 | new homes, "new pets join here" switches (load_game `from_version < 24`) |
| 25 | A3 (was v23 on prices) | `scout_notes` (defaults to 0, no code) |
| 26 | PRICES (was v24 on prices) | `coin_reserve` -> `reserve_capsules` (`_migrate` `version < 26`) |

The reserve migration only runs when the save still has `coin_reserve`, so a save that already
keeps `reserve_capsules` keeps it. A save with neither gets the default (boxes.json reserve).
Test-profile saves made on the prices lane (they say v23/v24 but already have the new fields)
skip the herd's room margin: harmless, only test profiles have them. Old real saves (v22 and
older, tests/saves) run every step. test_core checks v22 / v24 saves with `coin_reserve` 400 on a
tape+oil+flap machine (-> 50 capsules), a v25 save with `reserve_capsules` 30 (kept) and a save
with neither (the default).

## Conflicts and how they went

- tools/play.py: the prices side (hashed display + free_display + retry).
- docs/architecture.md: both paragraphs, prices' renumbered to v25 / v26.
- tests/test_core.gd: both test lists.
- scripts/ui/errands_tab.gd: house's `_resting_n` / `resting_faces` + A3's `_countdowns.clear()`;
  A3's `_job_note` lines use `size` (the jar's pay words, the kitchen line when `size > 0`).
- scripts/game_state.gd: `_work_for` = herd `job_size` + the scouting-full skip; `job_rate` =
  herd speeds + A3's 3-slot `_job_tools` (kitchen bonus, tools' crew power); `errand_tool_plan` =
  house's `levels_left` + prices' capsule value; `_auto_place(uids, counts, only)` keeps house's
  signature and gets A3's `Jobs.shared_out` filter; `_send_auto_party` keeps house's bool returns
  and passes `by_you = false`; `load_game` keeps the herd clamp, drops `coin_reserve` for
  `reserve_capsules`, keeps A3's offline catch-up before the errands and house's v23/v24 block
  after them; `_migrate` has both comments and the reserve step.

## Fixes after the merge (the herd x A3)

- `GameState._crew_speed(job_id)`: an errand crew's average speed (cards + each herd count at its
  rarity's template), cached in `_job_speed`; `job_rate` and `kitchen_bonus` both use it.
- `kitchen_bonus()`: cooks = `_crew_speed(kitchen) x job_size(kitchen)`, others = `job_size` of
  every other job (A3 counted card uids only, so herd cooks did nothing).
- `job_fill_now`: scouting waits full when `job_size > 0` (was `job_crew(...).is_empty()`, which
  missed a crew made only of herd pets).
- DevDriver `job <id> <n>` checks `job_size` (same reason).
- "New pets join here": `set_job_join` / `job_joins` refuse the kitchen and scouting (not shared
  out, you staff them), the errands side column only lists switches for shared-out jobs (with five
  jobs open it also spilled 5 px past the window), and the v24 `jobs_auto` migration only switches
  on shared-out errands.

## The room priced in capsules (new)

- data/herd.json `room`: `"coins": 500` -> `"capsules": 500` (note updated). A starter box is 50
  capsules, so a level still costs 10 boxes, as it did in coins on a fresh machine.
- `Herd.room_cost(catalog, level, value := 1.0)`: capsules x value x cost_grow^level, at least 1,
  capped at `Jobs.MAX_PRICE`; falls back to `coins` if the data has no `capsules`.
- `GameState.room_price()` passes `capsule_value()`. `buy_room` unchanged. The open room card
  refreshes on `GameState.changed` (a machine fix emits it), checked in pets_shelves.
- tools/balance.gd prints a "more room" table: price per level on a fresh machine, after flap
  (x8), when errands open (a capsule ~75) and on a maxed machine.

## Tests / flows

- test_core ALL PASSED (3523): `_test_prices` + room (capsules, 8x after tape+oil+flap, 10 starter
  boxes, never negative up to level 1000) + the reserve save chain; `_test_herd_game` + a kitchen
  and a scouting crew made only of herd stand-ins (bonus > 0, the coin hunt gets faster, scouting
  works and waits full, share out skips both, no join switch on the kitchen, everyone comes home).
- balance: runs clean.
- Flows passed: fits, tutorial, prices, errand_jobs, errand_tools, errands, errands_crowd, boxes,
  pets_shelves, new_homes, workers, automation.
- pets_shelves has a new last part: room 1, open the card ("900"), fix tape/oil/flap, the card
  reads "7,200" (shot room_machine).

## Review fixes (after the merge check)

- fits.flow was flaky (`click MiniCard#5` found nothing when the bookcase cushion rolled fewer
  cards): the dev step is now `pets <n> [seed]` (the seed stays on the pet roller for the rest of
  the run) and fits.flow uses `pets 9 7`, so the same pets come every run (8 cushion cards).
- `GameState.scout_hold()` is kept in `_scout_hold` until `_tools_changed()` (buying a tool, load,
  new game): the errands tab asks for it every frame through `job_fill_now` / `scout_full`.
- `send_on_adventure` checks `by_you` and `scout_notes > 0` before working out
  `Intel.left_to_find` (auto parties and sends without notes skip the lookup).
- The room card (RoomPill) lines its right edge up with the pill again on every refresh, so a
  wider price after a machine fix grows it to the left, never past the window.
- Settings: the reserve slider's coin label reads `capsule_value()` when it formats and updates on
  `GameState.changed` (a machine fix while settings is open).
- docs/architecture.md: the v24 paragraph says a v23 `jobs_auto` save switches on only errands
  that share out. docs/dev-plan.md: A3's `scout_notes` says save v25 (the rest of the dev plan
  text below is still to add; this lane doesn't edit the dev plan any further).

## Text to add

**docs/design.md** (done in place): the room bullet says "more room" is priced in capsules
(herd.json room "capsules" 500 x1.8 per level x a capsule's worth: 10 starter boxes a level, the
open card follows the machine); the "Priced in capsules" bullet mentions the room.

**docs/architecture.md** (done in place): the errands paragraph lists `Herd.room_cost(catalog,
level, value)` via `GameState.room_price()` and says crews are cards + herd counts everywhere
(`job_size`, `_crew_speed`); the save paragraph has v23 (herd), v24 (new homes), v25
(`scout_notes`), v26 (`reserve_capsules`, only a save that still has `coin_reserve` converts).

**docs/dev-plan.md**: mark A3 and PRICES merged into the house lane; note "the room's more room is
priced in capsules (10 starter boxes a level at every machine size)".

**CLAUDE.md "where we left off"**:
- Merge (lanes/house <- lanes/prices): save v25 = scout_notes (A3), v26 = reserve_capsules
  (PRICES; only saves that still have coin_reserve convert). The kitchen, scouting and the dev
  `job` step count herd crews (`job_size`, `GameState._crew_speed`); "new pets join here" never
  shows on the kitchen or scouting. "More room" is priced in capsules (herd.json room "capsules",
  `Herd.room_cost(catalog, level, value)`); balance prints its table.

## Questions for Emilia (smallest safe pick for now)

1. "New pets join here" switches only show on errands that share out pets, so not on the kitchen
   or scouting (A3: you staff those yourself). Fine, or should those get a switch too?
2. More room costs 500 capsules x1.8 per level (10 starter boxes a level). On a maxed machine that
   is 97M coins for the first upgrade, 1.8B at level 5 (balance table). Right once the machine is
   big, or should the room stay in plain coins / grow slower?
