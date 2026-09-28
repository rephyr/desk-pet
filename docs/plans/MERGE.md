# MERGE: lanes/prices into lanes/house

This branch has C1 + C3 (the herd, the room, new homes, sorting). lanes/prices brings two steps:
A3 (more errand jobs: savings jar, kitchen, scouting; commits 9712be2, 250f2f1, d1e435d) and
PRICES (errand tools, boxes and the pet's reserve priced in capsules). One merge:
`git merge --no-ff lanes/prices`, then fixes in their own commit.

## Conflicts (a trial merge found 5 files)

- **tools/play.py:** take the prices side (hashed display + free_display + retry). It already has
  everything house's version does.
- **docs/architecture.md:** keep both paragraphs, renumbered (see the save chain below).
- **tests/test_core.gd:** keep both test lists (`_test_herd`, `_test_herd_game`, `_test_new_homes`,
  `_test_new_homes_game`, `_test_prices`).
- **scripts/ui/errands_tab.gd:** keep house's `_resting_n` / `resting_faces` and add A3's
  `_countdowns.clear()`. A3's lines in `_job_note` use `crew` (gone on house): switch them to
  `size` (`_pay_words(job, size)`, kitchen line when `size > 0`).
- **scripts/game_state.gd** (10 hunks):
  - `_work_for`: house's `job_size` + A3's `scout_full()` skip.
  - `job_rate`: house's herd speeds + A3's 3-slot `_job_tools` (kitchen bonus, tools' crew power).
  - `kitchen_bonus`: herd-aware. Cooks = the kitchen's average speed x `job_size` (the same sum
    `job_rate` makes, cards + `Herd.template` per count). Others = `job_size` of every other job.
  - `capsule_value()`: keep it (prices).
  - `errand_tool_plan`: house's `levels_left` name + prices' `value` / `base`.
  - `_auto_place(uids, counts, only)`: house's signature, plus A3's `Jobs.shared_out` filter.
  - `_send_auto_party`: house's bool returns, plus A3's `send_on_adventure(..., false)`.
  - `load_game`: keep `_clamp_herd_places()` inside the held saves. Drop the `coin_reserve` line
    for `reserve_capsules`. Offline catch-up stays where A3 moved it (before the errands catch up),
    and house's v23/v24 block (refold, room margin, room_was_full) stays after the errands.
  - `_migrate`: both comments and the reserve migration, renumbered.
- Also check `job_fill_now`, which auto-merges with `job_crew(...).is_empty()` for scouting:
  change it to `job_size(...) == 0`, so a scout crew made only of herd pets still counts. Grep
  every A3 `job_crew(` use for the same issue.

## Save chain (one line, each migration its own number)

| v | from | what |
|---|------|------|
| 23 | house C1 | the herd (load_game `from_version < 23`: refold, room margin) |
| 24 | house C3 | new homes, join switches (load_game `from_version < 24`) |
| 25 | prices A3 (was 23) | `scout_notes` (defaults to 0, no code) |
| 26 | prices PRICES (was 24) | `coin_reserve` -> `reserve_capsules` (`_migrate` `version < 26`) |

`SAVE_VERSION := 26`. The reserve migration only converts when the save still has `coin_reserve`,
so a save that already has `reserve_capsules` keeps its reserve. That covers test-profile saves
from the prices lane: they claim v23/v24 but have the new field. Real saves (v22 and older, the
tests/saves v12 ones) run every step. I will note in MERGE-done.md that lane test-profile saves
from prices (v23/v24) skip the herd's room margin: harmless, since only test profiles have them.

## The house card priced in capsules (the one new feature bit)

The room card's "more room" price goes the prices way:
- data/herd.json `room`: `"coins": 500` becomes `"capsules": 500` (`_note` updated). A starter box
  is 50 capsules, so a room level still costs 10 boxes, as it did in coins before.
- `Herd.room_cost(catalog, level, value := 1.0)`: capsules x value x cost_grow^level, at least 1,
  capped at MAX_PRICE. It falls back to `coins` if data has no `capsules`.
- `GameState.room_price()` passes `capsule_value()`. `buy_room` is unchanged.
- RoomPill already shows `UiTheme.num(room_price())`. Check that the card refreshes when the
  machine grows while it's open, the same way the boxes tab `_refresh` does.

## Tests / checks

- `_test_prices`: add the room. It is priced in capsules, costs 8x on tape + oil + flap, and is
  never negative with every machine node.
- The `_test_herd` room math still holds (at value 1 it is the same numbers).
- The A3 tests on a herd save: put a kitchen / scouting crew of counts (herd pets) on. The kitchen
  bonus and scouting must work, share out / `_place_new` must skip the kitchen and scouting, and
  `_test_herd_game` must still pass.
- Run test_core, balance, and the flows: fits, tutorial, prices, errand_jobs, errand_tools,
  errands, errands_crowd, boxes, pets_shelves, new_homes, workers, automation. Check the shots of
  errand_jobs (kitchen / jar / scouting notes with herd crews) and pets_shelves room_card /
  room_poor (the price now scales with the rich save's machine).
- Fix whatever breaks, then commit ("merge prices into house" = the merge commit, then e.g.
  "room priced in capsules, jobs work with the herd").

## Notes -> docs/plans/MERGE-done.md

The save chain above, the room price change, the A3 herd fixes, and the text to add to
design.md / architecture.md / dev-plan / CLAUDE.md.

## Questions for Emilia (smallest safe pick used)

1. "New pets join here" switches only show on errands that share out (not the kitchen or
   scouting, which A3 says you staff yourself). Fine, or do you want a switch on those too?
2. The room costs 500 capsules x1.8 per level (10 starter boxes, the same ratio as before). Too
   steep or too cheap once the machine is big?
