# MERGE done: lanes/c1-c3 + lanes/b3 into lanes/workshop

Branch lanes/workshop now has E2 next door + B1 box tiers + SMALL machine odds (ours), C1-C3 the
herd / shelves / new homes, and B3 the whistle. No new features, only the merges and their fixes.

Status: VERIFIED, both merges committed on lanes/workshop (not pushed).

- Merge 1, lanes/c1-c3: d9267bd `merge the herd`. The open_boxes room rule and the boxes tab count
  are in this one.
- Merge 2, lanes/b3: 76070e1 (its message says "merge the herd: whistle keeps parties out of
  dungeons, review fixes", but it's the whistle merge, parents d9267bd + lanes/b3 3166927). It also
  holds the two flow fixes (new_homes, pets_shelves buttons), `_test_merged_saves`, and the review
  fixes listed at the bottom.
- Save: `SAVE_VERSION := 26` on this lane (22 base -> 23 box tiers, 24 visits, 25 herd, 26 new homes).
  The merge into `test` has to renumber it (see the save chain).

## Conflicts and how each was settled

### lanes/c1-c3
- data/unlocks.json `_note`: both texts in one (called / pages / ours_after AND new_homes, sorting,
  room, homes_by_hand, quiet).
- docs/architecture.md: both (box tiers + bookcase/shelves in the tab list; ours saves + herd saves).
  The herd's save notes are renumbered v23 -> v25 and v24 -> v26.
- scripts/dev/dev_driver.gd: every dev step from both sides (tiers/open/visit and herd/room/fill-room/fav/
  shelf/give-box/homes/rule/join/homes-points).
- scripts/pets/collection.gd: ours `look_keys` / `new_keys` + c1-c3's `add(new_pets, sorter) -> Array[Pet]`.
- scripts/game_state.gd:
  - signals `page_opened` + `room_full` + `homes_paid`, `WORKER_BOXES_MAX` kept, `SAVE_VERSION := 26`.
  - `open_boxes` (the real clash): boxes open **one at a time while the room has space for one
    more pet**. Each box's pets all come in (`_roller.roll_box`), so a sunset box can take the room over
    by a pet or two. Then there's one `collection.add(pulled, _sorter())`, `_sent_home`, and `_room_hit()`
    when the room is full. A full room opens none (`room_full` when opened by hand). `packs_by_hand`
    counts the boxes that actually opened.
  - `auto_open_pack`: every pet in the box, skipping the ones the sorting rule sent off.
  - `pet_box_order` (ours) and `boxes_on_pile` (c1-c3) both kept. `can_auto_open` keeps the room check.
  - `_workers_open`: counts opened boxes by what left the pile (the room can stop a batch part way).
  - migrations renumbered (see the chain below).
- scripts/ui/boxes_tab.gd (auto-merged, fixed after): `open()` counts what left the pile, so "opening
  N boxes" / "open N more" never claim more than the room let open.
- tests/test_core.gd: both test lists. The new homes save test is now v25 (it was c1-c3's v23).
- tests/flows/new_homes.flow, pets_shelves.flow: `click "open 1"/"open 10"` became
  `click name:open_starter_1/_10` (the box tiers shop's buttons read "1 / 10 / all").

### lanes/b3
- data/adventures.json / unlocks.json `_note`s: both. The whistle unlock sits after new homes / sorting.
- adventure_runner: `start(..., gear, ours := false, workers := 0)`, `pick_events(..., fixed, ours,
  workers)`, with both filters (the locals skip ours trips; `after_workers`). GameState passes
  `is_ours(location_id), workers_total()`. b3's whistle tests now pass `false` for ours.
- `_open_entry` (ours, also used by `open_page`) calls b3's `_opened(str(o))` for everything it opens.
- tools/balance.gd: `_box_tiers`, `_ours`, `_spots`.
- The whistle on top of the herd:
  - b3's `_best_resting` / `_place_workers` are dropped. `put_workers` stays the herd's (`_pick` + `_add_workers`).
  - `_whistle_checks`: `whistle_plan(..., resting_count(), ...)`. Each job to fill gets
    `_pick(resting_cards(), resting_herd(), n, worker_speed, true)` then `_add_workers` (parties get
    stand-in leaders).
  - `Automation._working` adds `Herd.total(wherd[id])`.
  - `workers_total()` sums `workers_count(id)` over every job (cards + herd), not `_worker_of.size()`.
  - `Automation.fresh()` has `wherd`, `wjoin` and `whistle`. `_load_automation` loads wjoin/wherd,
    then the whistle, and sets the task once after both.
  - automation_tab: the rebuild key has wherd/wjoin + the whistle's bits, with `resting_count()` for
    pages >= 1. The to-do rows' tiny crowds use `worker_faces`. The "pets resting" note uses
    `resting_count` / `resting_faces`.
  - dev steps: c1-c3's `others` plus b3's `spots` (via `_add_spots`), `workers`, `manage`.

## Save chain (`SAVE_VERSION := 26`)

| v | what | from | check |
|---|------|------|-------|
| 22 | base | all | - |
| 23 | box tiers, lucky box retired | ours | `BoxShop.fix_retired` on every load, any version |
| 24 | visits per place | ours | `version < 24 and not data.has("visits")` |
| 25 | the herd (fold plain pets, room for old saves) | c1-c3's v23 | `from_version < 25` |
| 26 | new homes (jobs_auto -> joins, full room -> stall) | c1-c3's v24 | `from_version < 26` |
| - | the whistle (`automation.whistle`, missing = every tick on) | b3 | no bump |

The fold (`collection.refold()` at the end of load_game) runs on every load and is idempotent: a
save that already has counts loads the same (checked by the new test).

**For the later merge into `test`:** `test` has its own v23 (scout_notes) and v24 (stickers).
That merge has to renumber again, e.g. 23 scout_notes, 24 stickers, then this branch's 25 box tiers
(number-free), 26 visits (field-checked), 27 herd, 28 new homes. Only the herd's and new homes'
`from_version <` checks, their comments and the tests' old-save versions (`_test_new_homes_game`
builds a v25 save) need to move.

## Checks

- `godot --headless -s tests/test_core.gd -- --profile=test-workshop`: ALL PASSED (3979 checks).
  New `_test_merged_saves`: a v22 save (200 plain pets, 20 machine workers of uids, garden + meadow
  visited) loads with herd counts, 20 workers, `visits` {garden: 1, meadow: 1}, and every whistle
  tick on. It saves as v26, and a second load changes nothing. A sunset box opens with 1 space left,
  every pet comes in, the room is full, and the next box waits.
- `godot --headless -s tools/balance.gd -- --profile=test-workshop`: runs, all three new sections print.
- Flows (all pass; screenshots looked at): fits, tutorial, next_door, box_tiers, machine_odds,
  boxes, unlock_popup, pets_shelves, new_homes, long_pet, whistle, workers, automation, and also
  pet_box, errands, errands_crowd, home_pile, party, errand_tools, gear, machine.
  - The whistle page runs a crowd of 2,030 machine workers, mostly herd counts, with tiny crowds of
    stand-ins.
  - The shelves and the full room look right.
  - The automation flow failed once, when 13 flows ran at the same time: "opening your pile" was
    showing where "the pile is empty" was expected. It passed twice when run alone, so it looks like
    a timing flake under load, not the merge.

## Text for the shared docs

**docs/design.md / docs/architecture.md:** already edited here: the room rule for multi-pet boxes,
the whistle on the herd, and the renumbered herd saves.

**docs/dev-plan.md:** "Merged lanes/c1-c3 (C1-C3) and lanes/b3 (B3) into lanes/workshop
(E2 + B1 + SMALL). One save chain v22 -> v26 (23 box tiers, 24 visits, 25 herd, 26 new homes;
the whistle needs no bump). Boxes open one at a time while the room has space for one more pet.
The whistle places herd counts. Next on this lane: the workshop (opened by the whistle)."

**CLAUDE.md "where we left off":** "lanes/workshop now holds next door, box tiers, machine odds,
the herd + shelves + new homes, and the whistle (merged; save v26 on this lane: 23 box tiers,
24 visits, 25 herd, 26 new homes). A sunset box opens while the room has 1 space left (the room
can go over by a pet or two). The whistle fills spots from the herd. New test
`_test_merged_saves`. Flows new_homes / pets_shelves click `name:open_starter_1` now."

## Questions for Emilia (smallest safe pick made)

1. A sunset box (2-3 pets) opens when the room has 1 space left, so the room can go over by a pet
   or two. Is that ok, or should it wait until there's room for 3?
2. Next door adds no workers' machines or tables to the caps (`spot.exist` only has backyard /
   beyond); parties still get one per party place, next door's places included (not the doghouse
   until it's ours). Should places that
   became ours add some? The whistle's popup says "old machines and tables ... from places you've
   taken", which now sounds a lot like "ours".

3. Parties the game places by itself (whistle, bought spots) skip dungeons AND risky places that
   aren't ours yet (the doghouse). Should the doghouse count once it's ours (it does now), or never?

## Review fixes (merge pass)

- **Pets lost only by choice:** new `GameState.party_places()` = open places without `type:
  dungeon` and without `risky` places that aren't ours yet. `_free_party_place`, the fallback in
  `auto_party`, `spot_exist` / `spot_room` (the per-place cap) and the whistle list's "of N places"
  all use it, so the whistle never starts a party in the well / cellar / below. You can still move a
  party there yourself. Test `_test_party_places` (every other place taken, new parties stay out of
  dungeons; it fails on the old code with ["well", "cellar", ...]).
- **"show me" matches what the unlock opens, not its id:** `UnlockPopup.go(tab_id, opens: Array)`,
  `ExpandedView.show_tab(tab_id, opens := [])`, `AutomationTab.show_unlock(opens)` checks
  `"feature:whistle" in opens` and calls `speak()` once the page is set (your pet says the whistle
  line, not the general one).
- **`UiTheme.segmented_select(p, i)`:** the picked-look loop lives there; `segmented` uses it for its
  buttons and presses, `AutomationTab._select_mode` calls it.
- **Load guard:** a save with `"whistle": null` (or `ticks` not a dict) loads with defaults.
- **`debug_new_game`** calls `whistle_seen()` so "since you looked" starts empty.
- No save bump. Tests, balance, flows whistle / fits / workers / unlock_popup / automation pass.

Text for **docs/architecture.md** (add to the automation part): "`GameState.party_places()`:
open places the workers' parties may take by themselves (no dungeons, no risky place until it's
ours). The parties cap (`spot.per_place`) and the auto places both count it."
