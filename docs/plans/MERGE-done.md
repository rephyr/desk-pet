# MERGE done: lanes/b2-d1 (B2 boost plumbing + D1 knacks) into care

`git merge lanes/b2-d1` (base 9e57dd0) into lanes/care (A2 gear, A3 errand jobs + kitchen, A4 book
rewards). Conflicts in 8 files, all kept both sides. Committed as one merge commit on lanes/care
("merge boosts and knacks into care", with the review fixes below); step VERIFIED. Not pushed.

## Save

- SAVE_VERSION stays **24** (care's). b2-d1 was at 22 and made no save change: the run's
  `knacks` field is optional (missing = x1). No new migration, no bump. Migrations up to v24 run in
  order as before.

## What changed in the merge

- **One boost path.** `GameState.boost(kind)` (B2, cached) is the only multiplier call.
  `boost_parts(kind)` gathers sources in data/boosts.json "sources" order: toys, book, knacks,
  kitchen. Gone: `toy_boost`, `book_x`, `_book_x`, `Toys.multiplier`, `Book.multiplier`, and A4's
  own `boost()` (toy_boost x book_x).
- **Book stickers** are boost parts: `Book.parts(catalog, stickers, kind)` gives one
  `Boosts.part("book", page_id, x)` per open sticker of that kind. `check_book()` calls
  `_boosts_changed()`.
  - Errands: `job_rate` ends with `* boost("errands")` (was `* book_x("errands")` inside the tools'
    speed).
  - Automation: `_work_for_automation` multiplies seconds by `boost("automation")` once (B2), so
    `Automation.crank` / `crank_seconds` lost A4's `x` parameter again (automation.gd is back to the
    base version). Workers no longer take `* book_x` in `workers_speed` (they keep D1's
    `knack_own(pet, "automation")`). The box timer out of sight uses B2's
    `_pack_timer += delta * boost("automation")`, and `background_packing()` divides by the plain
    `BACKGROUND_PACK_EVERY`.
- **The kitchen** is a `kitchen` part of "errands" only: x `1 + kitchen_bonus()`, added only when
  above 0. In `job_rate` the tools' speed is just `1 + speed + all_speed`, the rate is x
  `boost("errands")`, and the kitchen job itself divides its own part back out (a 4th `_job_tools`
  entry says whether the job is the kitchen). Every `_kitchen = -1.0` is now `_kitchen_changed()`,
  which also drops the kept "errands" total. `_knacks_changed` / `_knack_gates_changed` (when the
  errands knack table moves) reset `_kitchen` too, since the cooks' speeds hold their knacks.
  No loop: `kitchen_bonus()` only reads `_speed_of` (pet speed x its own errand knack), never
  `boost()`.
- **Intel.roll** is `roll(location, known, tries, rng, bonus := 0.0, x := 1.0)`, chance =
  `spot * x + SAFETY_NET * tries + bonus`. `_spot_places` passes the scout note's `spot` and
  `run.knack("spots")`.
- **RunState** keeps `scout` / `scouted` (A3) and `knacks` (D1); `to_dict` saves both.
- **send_on_adventure** packs `trip_knacks(going)` and keeps A3's scout-note block.
  `_boost_trip_loot` is D1's version (boost("loot") x the party's loot knack; finds).
- **Machine**: both `Machine.roll` calls use `boost("toys")`; the lever also passes
  `boost("pet_boxes")`.
- **Load**: A3's coin trickle (before the errands catch-up, for the kitchen's meals) now x
  `boost("away")`; D1's duplicate trickle block dropped. `_knacks_changed()` runs after the toys
  load and before any catch-up reads a boost; the `_book_x.clear()` calls in new game and load are
  gone.
- dev_driver keeps `book`, `stickers`, `boosts`, `dress`. errands_tab keeps A3's "coins when full"
  line. automation_tab uses `crank_seconds(...) / boost("automation")`. catalog loads `book`,
  `boosts`, `knacks`.

## Numbers that moved

- The kitchen used to add to the tools' speed (1 + tools + kitchen); now it multiplies
  ((1 + tools) x (1 + kitchen)), so it's a little stronger when a job has speed tools.
  balance.gd output is byte-identical before and after (it prints the kitchen's % only, not a
  combined speed).
- The blanket sticker (automation) now also shortens `PackJob`'s breaks on screen, since that reads
  `boost("automation")` (B2).

## Files

- scripts/game_state.gd, scripts/adventure/intel.gd, scripts/adventure/run_state.gd,
  scripts/core/catalog.gd, scripts/dev/dev_driver.gd, scripts/ui/automation_tab.gd,
  scripts/ui/errands_tab.gd, scripts/pets/book.gd, scripts/idle/automation.gd (reverted A4's `x`)
- data/boosts.json (`_note`: sources are live now)
- tests/test_core.gd (runs `_test_book` and `_test_knacks`; book tests use `Boosts.total(Book.parts(...))`
  and `boost`; the toys-luck check compares against `Boosts.total(Toys.parts(...)) * 1.1`; the
  test emits `toys_changed` after a raw `Toys.play` so the kept boosts refresh; D1's spotting test
  call is `(..., 0.0, 1.5)`)
- tests/flows/book.flow (a `boosts` step at the end logs the book parts), tests/flows/errand_jobs.flow
  (a `boosts` step logs the kitchen part)
- docs/architecture.md (Boosts section: sources, where kinds are read; Book bullet; kitchen),
  docs/design.md (book page rewards, Boosts paragraph, kitchen)

## Checks run

- `godot --headless -s tests/test_core.gd`: ALL PASSED (3687 checks).
- `godot --headless -s tools/balance.gd`: identical to the pre-merge output.
- Flows, all PASSED: fits, tutorial, gear, book, errand_jobs, knacks, toys, errands, errands_crowd,
  errand_tools, automation, workers. Logged parts: book `coins x1.210 (palettes, finishes)`,
  `errands x1.210`, `luck x1.100`, `automation x1.100`; errand_jobs `errands x1.158 kitchen`;
  knacks as on the D1 branch.
- Looked at book finishes_open, errand_jobs kitchen, knacks all_badges, fits pets_knacks, gear
  all_gear, automation cranking: all inside the window, readable.

## Text to add

**docs/dev-plan.md** (under B2 / D1 / A3 / A4):
> Merged on lanes/care (MERGE-done.md): book stickers and the kitchen go through `boost(kind)`
> (sources toys, book, knacks, kitchen); `toy_boost` / `book_x` are gone. The kitchen multiplies
> errand speed now instead of adding to the tools' speed. Save stays v24.

**CLAUDE.md "where we left off"**:
> - Merge (lanes/care): B2 boost plumbing + D1 knacks merged with A2-A4. One `GameState.boost(kind)`
>   for everything; `boost_parts` = toys, book stickers (`Book.parts`), your active pet's knacks,
>   the kitchen (errands only, `_kitchen_changed()`). Intel.roll(.., bonus, x). Save v24 (no bump).
>   Dev step `boosts` in book / errand_jobs / knacks flows.

(docs/design.md and docs/architecture.md are already updated in this merge.)

## Questions for Emilia

- The kitchen now multiplies errand speed instead of adding to the tools' speed, so it's a bit
  stronger with speed tools. OK, or keep it additive?
- The blanket sticker (automation) now also speeds your pet's box opening on screen (same
  `boost("automation")` path). OK?

## Review fixes (after the merge)

- Trip kinds are data now: `"trip": true` on loot, spots, trip, tough, safe, finds, pickups, treats
  in data/boosts.json, read by `Boosts.trip_kinds(catalog)`. `GameState.TRIP_KNACKS` is gone;
  `trip_knacks()`, `AdventuresTab._trip_key()` and the test's `party_all` timing use the helper
  (a new test check: trips pack the kinds marked trip).
- The once-a-second `_boosts_changed()` in `_process` is gone: a play running out already emits
  `toys_changed` (from `Toys.finish_plays` on the same tick), which clears the kept totals.
- `follow_lead` and `follow_rumour` call `_knack_gates_changed()` after writing unlocks (knack gates
  may be `location:` / unlock ids).
- `pets_removed` also drops the pets' entries from `_knack_own`.
- Stale docs fixed: Boosts class doc (sources: toys, book, knacks, kitchen), `_test_boosts` doc,
  `GameState.boost()` doc (points at data/boosts.json for the kinds), RunState.knacks comment,
  architecture.md (what clears `_boosts`; trip kinds from data).
- No save change (still v24). Tests: ALL PASSED (3688 checks). Balance unchanged. Flows knacks,
  fits, toys, party, postcard pass.

Text for CLAUDE.md "where we left off" (add to the knacks line): trip knack kinds are marked
`"trip": true` in data/boosts.json (`Boosts.trip_kinds`).
