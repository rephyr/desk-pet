# FIXES lane: done

Branch `lanes/fixes`, from 13a1126. Every one of the 14 reported bugs was checked against the code
first and was real (the two dungeon_view.gd:268 reports are the same bug, so 13 fixes). No save
version bump: nothing in the save's shape changed.

## What changed

Bugs
- **The well page with a landing's card open during a run** (dungeon_view.gd `_build_desk`):
  `_done_shown` is now set before the hold-card branch. Before, the hold card returned early, so
  `_tick_run` asked for a new desk every frame and the card's buttons never took a click. The
  rebuild after a finished floor now gets the real `army_rules` (it used to get `{}`, so the
  orders lost the feeling word). New dev step `desk-still <s>` (DungeonView.desk_builds) and a
  check at the end of the `held` flow: card open, army sets off, desk stays put. With the old
  code it fails ("built 33 times in 1.5 s").
- **Pip slider, shelves under 10 pets**: tapping the last lit pip now takes one pet off (down to 0).
  Rounding up used to give the same count back. A small wobble on the pressed pip still counts as
  a tap. Shelves of 10 or more work as before.
- **Coins past int's top** (about 9.2e18):
  - New `Rewards.coins(f)` rounds a float payout and holds it at 9e18 instead of wrapping round.
    Jobs.pay and Machine.loot use it, so a long time away can no longer pay 1 coin.
  - The shiny step in `_pet_capsule` and `_capsule` now goes through `coins_int` (it could turn a
    huge capsule negative).
  - `Rewards.add` / `Rewards.total` and the saved `idle_log` add with `Rewards.plus`, which stops
    at the top instead of wrapping.
  - The "while you were busy" bubble shows coins short ("◆1.2Qa"), not as `%d`.
- **NumFormat.short** past the last unit, INF or NaN: `"%.2e"` isn't a GDScript format and showed
  as literal text. Now 2e36 reads "2,000Dc", an endless number is capped like a big one, NaN reads
  "0". Tests added.
- **Machine tree breathing rings** froze on screen once no "next" node was left: every tree draw
  now redraws the rings overlay too.

Lag
- **Folding crew cards** (`_on_folded`): a fold only turns crew cards into the same crew's counts.
  It now takes the folded uids out of `_job_of` and tells the board with `crews_by_themselves` on.
  The errands board catches up on its 3 s throttle instead of rebuilding with every new pet.
  Folded workers still go through `_workers_changed` (there are only as many as there are spots).
- **Dungeon page key**: it keys what the shelf rows show (the short count, the pips' fill, the
  "all" state), not the exact herd count, so a growing herd no longer rebuilds the page every
  0.5 s.
- **spare_shelves**: above 5000 cards (`SPARE_BIG`), routine `_rest_changed` calls (pets added,
  herd folds, crews) leave the count alone for its 3 s window. Clearing it right away now only
  happens for who-may-go changes: favourites/buttons, pins, the keep line, keep lines (the last two
  now call `_spare_changed` too), and after `_take_spare` spends pets.
- **_place_new**: the "rule's pets nobody took" pass only runs when the sorting rule forced some
  pets. It now checks `_job_of` / `_worker_of` instead of rebuilding `resting_cards()`.
- **The well column**:
  - `_floor_at` is a binary search, and shaft half-widths are worked out once in `refresh()`.
  - `tick()` redraws only once the party has moved a pixel or reached another floor. That is
    about 4 redraws a second on cleared floors, down from 20.
- **The run card's floor log**: the rows for this run's finished floors are kept between builds
  (taken out before the desk is cleared, freed when the run changes or the page goes). A finished
  floor only builds its own row.
- **save_game()**:
  - A save asked for while playing now waits 1.5 s (`SAVE_SOON`), so a few taps in a row write
    once.
  - It never blocks on a write that is still running: it waits for the next frame instead.
  - `save_game(true)` (quitting, a new game) and GameStates outside the tree (tests, tools) still
    write right away.
  - The 30 s autosave goes the same way.

## Checks
- Core tests: ALL PASSED (6123 checks), several times. Once, running at the same time as the
  perf_late flow, they reported "2 FAILED" without showing which. Three more runs passed, one of
  them under the same load. It looks like a timing flake (the known flaky "v21 and v23 saves load
  the same" is one candidate).
- Flows passed: dungeon, held, perks, sewing, machine, goals, errands, errands_crowd,
  working_pets, edge, new_homes, school, automation, workers, fits, tutorial, new_game, toys_late,
  settings_rebuild, errand_jobs, plushie, perf_late.
- `held` failed once while three flows ran at once. Its "walking" check comes about 3 s after a
  5 s run starts, and under load the run had already ended. Run alone it passes. The flow is
  unchanged there (my check sits at its end).

## Merge notes
- Touches `scripts/game_state.gd` in several small spots: `_rest_changed`, `_on_folded`,
  `_place_new`, `save_game` (split into `save_game` + `_write_save` + `_still_writing`),
  `_process`'s autosave, the two shiny loops and `_log_idle`. It also touches dungeon_view.gd,
  well_column.gd, machine_tree_view.gd, num_format.gd, rewards.gd, jobs.gd, machine.gd,
  pet_voice.gd, dev_driver.gd and held.flow.
- If another lane adds code that reads the save file right after `save_game()`, it must call
  `save_game(true)`.

## Questions for Emilia
- An endless number (a bug somewhere, never normal play) now shows as a huge "…Dc" count rather
  than "∞", because I wasn't sure the pixel fonts have that glyph. OK?
- The bubble's coin count now reads short like the rest of the UI ("◆12.3k" rather than "◆12345").
  OK?
