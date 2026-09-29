# MERGE plan: lanes/c1-c3 + lanes/b3 into lanes/workshop

This branch (lanes/workshop) is E2 next door on top of B1 box tiers + SMALL (machine odds).
All three branches start from the same base (dde1560, save v22). Order: c1-c3 first, then b3.
No new features: only the merges and the fixes they need.

## 1. `git merge --no-ff lanes/c1-c3` (the herd, shelves, new homes)

Conflicts (preview with `git merge-tree`): data/unlocks.json, docs/architecture.md,
scripts/dev/dev_driver.gd, scripts/game_state.gd (6 hunks), scripts/pets/collection.gd, tests/test_core.gd.

- **unlocks.json / architecture.md / test_core run list / dev_driver**: keep both sides (both
  `_note` additions; next door + herd tests; dev steps tiers/open/visit AND herd/room/fill-room/fav/
  shelf/give-box/homes/rule/join/homes-points, in the doc comment and the match).
- **signals**: keep `page_opened` + `WORKER_BOXES_MAX` (ours) and `room_full` + `homes_paid` (herd).
- **collection.gd**: keep ours `look_keys` / `new_keys` and c1-c3's new `add(new_pets, sorter) -> Array[Pet]`.
  `new_keys` uses `times_seen`, which the herd collection still has (the book counts every pet, folded or not).
- **open_boxes** (the real semantic clash): a sunset box holds 2-3 pets, but the room check counts
  boxes. Smallest safe rule: open box by box; a box opens while the room has at least 1 space; all
  its pets come in (the room can go over by a pet or two); stop when the room is full. Code:
  roll each box with `_roller.roll_box`, then one `collection.add(pulled, _sorter())`, `_sent_home`
  as c1-c3 has it, `_room_hit()` when full. Doc comment merged (sunset 2-3 + room + sorting rule).
- **auto_open_pack**: loop over every pulled pet (ours) AND skip ones the sorting rule sent off (c1-c3).
- **pet_box_order** (ours) and **boxes_on_pile** (c1-c3): keep both; `can_auto_open` keeps the room check.
- **Save chain** (see 3).
- Look over the auto-merged spots that touch both: `_workers_open` (our split by box kind +
  WORKER_BOXES_MAX vs the room cap), reveal_result.gd (new tags + sent-home pets), boxes_tab.gd
  (our shop rework + c1-c3's room-full bits), unlock_popup.gd, machine_tab.gd, catalog.gd (both load
  new data: box tiers/ours and herd/new_homes).

## 2. `git merge --no-ff lanes/b3` (the whistle)

Conflicts vs this branch: data/adventures.json, data/unlocks.json (`_note`s: keep both),
adventure_runner.gd, game_state.gd, tools/balance.gd. Vs c1-c3's code: game_state.gd,
automation.gd, automation_tab.gd, dev_driver.gd, test_core.gd.

- **adventure_runner**: `start(..., gear, ours := false, workers := 0)` and
  `pick_events(..., fixed, ours, workers)`: both filters (locals skip ours trips; `after_workers`).
  GameState passes `is_ours(location_id), workers_total()`.
- **_open_entry** (ours, also used by open_page) gets b3's `_opened(str(o))` per opened thing.
- **balance.gd**: both sections (`_box_tiers`, `_ours`, `_spots`).
- **Whistle on the herd** (workers are now cards `workers[id]` + counts `wherd[id]`):
  - drop b3's `_best_resting` / `_place_workers`; `put_workers` stays c1-c3's (`_pick` + `_add_workers`).
  - `_whistle_checks`: resting number = `resting_count()`; placing n pets = `_pick(resting_cards(),
    resting_herd(), n, speed, true)` then `_add_workers(id, cards, counts)` (parties get stand-ins).
  - `Automation._working` counts `workers[id]` uids + `Herd.total(wherd[id])`.
  - `workers_total()` sums `workers_count(id)` (cards + herd).
  - Automation.fresh / doc: keep `wherd`, `wjoin` AND `whistle`. `_load_automation`: keep both the
    wjoin/wherd load and the whistle load (task set once, after both).
  - automation_tab rebuild key: c1-c3's wherd/wjoin + b3's whistle bits, `resting_count()` for pages >= 1.
    TodoRow "N working" / "N pets resting" use `workers_count` / `resting_count` (not array sizes).
    TinyCrowd faces from `worker_faces` / `resting_faces`.
  - "new pets join here" (wjoin) and the whistle's "keep them full" both fill empty spots: fine together.
  - dev steps: keep c1-c3's plus b3's `manage`, `workers`, `teach <job> others`, `spots` via `_add_spots`.
- Next door pages: `spot.exist` has only backyard / beyond, so next door adds no machines/tables;
  parties are one per open place, next door's places count. (Question below.)

## 3. Save chain (one line, every old save loads)

| v | what | from |
|---|------|------|
| 22 | base | all |
| 23 | box tiers (BoxShop.fix_retired, works on any version) | ours |
| 24 | visits per place (keyed on `not data.has("visits")`) | ours |
| 25 | the herd: fold plain pets into counts (`from_version < 25`) | c1-c3's v23 |
| 26 | new homes: jobs_auto -> joins, full room -> stall (`from_version < 26`) | c1-c3's v24 |
| - | whistle: additive field, no bump | b3 |

`SAVE_VERSION := 26`. Our two migrations don't depend on the number, so they stay. c1-c3's
checks move 23 -> 25 and 24 -> 26 (load_game, _migrate comments, tests that build old saves).
The fold must be safe to run on a save that already has counts (check it).
Note for the final merge: `test` has its own v23 (scout_notes) and v24 (stickers); that renumber
is the later merge step's job, listed in MERGE-done.md.

## 4. Checks after each merge

- `godot --headless -s tests/test_core.gd -- --profile=test-workshop` (renumber version numbers in
  `_test_herd_game`, `_test_new_homes_game`, next door's visits test; add one check: a v22 save with
  plain pets + visited places loads to v26 with counts, visits and every tick on).
- `godot --headless -s tools/balance.gd -- --profile=test-workshop`.
- Flows (`DESK_PETS_LANE=workshop python3 tools/play.py <flow>`): fits, tutorial, then ours
  (next_door, box_tiers, machine_odds, boxes, unlock_popup), c1-c3 (pets_shelves, new_homes,
  long_pet), b3 (whistle, workers, automation). Look at the shots: whistle page with herd crowds,
  shelves after a sunset box, room full with a multi-pet box.
- Fix what breaks, commit the merge commits (`merge the herd`, `merge the whistle`, plus small fix
  commits), no push.

## 5. Done notes

docs/plans/MERGE-done.md: conflicts and how each was settled, the save chain table, flows run,
text for design.md / architecture.md / dev plan / CLAUDE.md.

## Questions for Emilia (smallest safe pick made)

1. A sunset box (2-3 pets) opens when the room has 1 space left, so the room can go over by a pet
   or two. Ok, or should it wait for 3 spaces?
2. Next door adds no workers' machines/tables to the caps (only backyard / beyond do). Should
   places that became ours add some?
