# MERGE: lanes/b2-d1 (B2 boost plumbing + D1 knacks) into care

`git merge lanes/b2-d1` in this worktree (base 9e57dd0). Dry run (`git merge-tree`) conflicts in
8 files: game_state.gd, intel.gd, run_state.gd, catalog.gd, dev_driver.gd, automation_tab.gd,
errands_tab.gd, test_core.gd. Everything else auto-merges (docs, adventure_runner, adventures_tab,
collection_tab, ui_theme, fits.flow, play.py).

## Save
HEAD (test) is at SAVE_VERSION 24, b2-d1 is at 22 and changed nothing (no save field, the run
dict's `knacks` is optional). Keep 24, no new migration, no bump. Noted in MERGE-done.md.

## Conflict resolution (keep both sides)
- **catalog.gd**: keep `book`, `boosts`, `knacks` (vars + loads).
- **run_state.gd**: keep `scout` + `scouted` (A3) and `knacks` (D1); to_dict has both `scout` and
  `knacks`; `walk` comment says boots + trip knacks.
- **intel.gd**: `roll(location, known, tries, rng, bonus := 0.0, x := 1.0)`, chance =
  `spot * x + SAFETY_NET * tries + bonus`. GameState: `Intel.roll(location, _place_known,
  spot_tries, _rng, float(run.scout.get("spot", 0.0)), run.knack("spots"))`. D1's test call
  `Intel.roll(..., 1.5)` becomes `(..., 0.0, 1.5)`.
- **dev_driver.gd**: keep `book`, `stickers` and `boosts`, `dress` (docs + match arms).
- **errands_tab.gd**: keep HEAD's `chunk` line ("coins when full").
- **automation_tab.gd**: B2's form, `crank_seconds(...) / boost("automation")` (book now inside boost).
- **test_core.gd**: run both `_test_book` and `_test_knacks`.
- **game_state.gd**:
  - signals: keep `sticker_opened` and `knacks_changed`; ready: keep the book hooks and the
    boost/knack hooks.
  - `_work_for`: keep HEAD's meal / note handling (it already does `Rewards.add` below).
  - `send_on_adventure`: `trip_knacks(going)` arg AND HEAD's scout note block.
  - Machine.roll calls: `boost("toys")` (+ `boost("pet_boxes")` on the lever); fever: `boost`.
  - `_boost_trip_loot`: D1's version (loot x party knacks, finds on parts, boxes separate).
  - load: keep HEAD's position of the coin trickle (before the errands catch-up) with D1's
    `* boost("away")`; drop D1's duplicate block. Call `_knacks_changed()` once the save's
    collection, stickers, toys and machine are in, before any catch-up reads a boost.
  - drop HEAD's `boost()` / `toy_boost` / `book_x`; keep B2's cached `boost()` + `boost_parts()`.

## Route A4 book stickers through boost(kind)
- `Book.parts(catalog, stickers, kind) -> Array[Dictionary]`: one `Boosts.part("book", page_id, x)`
  per open sticker of that kind. `Book.multiplier` goes (like `Toys.multiplier`); its tests use
  `Boosts.total(Book.parts(...))`.
- `boost_parts` appends toys, book, knacks, kitchen (the data/boosts.json `sources` order).
- `book_x` and `_book_x` removed. Call sites:
  - errands: `job_rate` ends `* boost("errands")` (B2); the tools' speed is just 1 + tools.
  - automation: `_work_for_automation` does `seconds *= boost("automation")` (B2) and calls
    `Automation.crank(catalog, automation, seconds)` without the book x (no double count); the
    workers' speed loses its `* book_x`; background box timer uses B2's `delta * boost(...)`;
    its progress getter divides the same way. `Automation.crank_seconds/crank` keep A4's
    `x := 1.0` param (unused default, harmless) - or revert it; pick revert if nothing else uses it.
  - `check_book`: `_boosts_changed()` instead of clearing `_book_x`/`_job_tools`/`_worker_speed`;
    new game / load: drop `_book_x.clear()` (B2 clears boosts there).
- Tests: `gs.book_x("automation")` -> `gs.boost("automation")`; "luck is the toys' luck times
  the magnifying glass" compares `gs.boost("luck")` with `Boosts.total(Toys.parts(...)) * 1.1`.

## Route A3's kitchen through boost("errands")
- Source `kitchen`, kind `errands` only: part `Boosts.part("kitchen", "kitchen", 1 + kitchen_bonus())`
  when the bonus is above 0.
- `job_rate`: `_job_tools[id]` = [crew power, 1 + tools speed, tools' crew power] (HEAD's 5-arg
  `Jobs.rate` stays); rate `* boost("errands")`, divided by `1 + kitchen_bonus()` for the kitchen
  job itself (it never sped itself up).
- Every `_kitchen = -1.0` (pet_changed, `_tools_changed`, `_crews_changed`) becomes
  `_kitchen_changed()`: `_kitchen = -1.0` + `_boosts.erase("errands")`, so the cached total follows.
- No recursion: `kitchen_bonus()` reads `_speed_of` (pet speed x own knack share), never `boost()`.
- Numbers change a little (was 1 + tools + kitchen, now (1 + tools) x (1 + kitchen)). Diff
  balance.gd before/after and note it; question for Emilia (B2 already asked).

## Checks
- `grep` for `toy_boost`, `book_x`, `Toys.multiplier`, conflict markers: none left.
- test_core (--profile=test-care), balance.gd (diff against pre-merge HEAD output).
- Flows (DESK_PETS_LANE=care): fits, tutorial, gear, book, errand_jobs, knacks; also toys (its
  `boosts` step should now list book parts when stickers are open), errands, automation, workers.
  Look at the book, errand_jobs (kitchen line) and knacks screenshots.
- Optional extra flow step: add `boosts` to book.flow after a page fills, to log the book part.

## Files
game_state.gd, intel.gd, run_state.gd, catalog.gd, dev_driver.gd, automation_tab.gd,
errands_tab.gd, book.gd (Book.parts), automation.gd (maybe revert x), data/boosts.json (_note:
book and kitchen are sources now), test_core.gd, book.flow, docs/design.md + docs/architecture.md
(Boosts section: sources toys, book, knacks, kitchen), docs/plans/MERGE-done.md.
No UI changes, no new data files.

## Commit
One merge commit on lanes/care ("merge b2-d1: boosts + knacks"), fixes after it as small commits.
No push.

## Questions for Emilia
- The kitchen now multiplies errand speed instead of adding to the tools' speed (a bit stronger).
- The blanket (automation sticker) now also speeds the on-screen box opening (PackJob's rest),
  since it goes through boost("automation") like everything else. Before it was only the crank,
  background boxes and workers.
