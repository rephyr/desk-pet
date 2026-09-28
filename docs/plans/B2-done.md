# B2 done: boost plumbing (no receipt UI)

## What was built
One place that answers "how much is this kind boosted right now, and by what?".
- `GameState.boost(kind) -> float` and `GameState.boost_parts(kind) -> Array[Dictionary]`.
- `Boosts` (scripts/core/boosts.gd, static, no game rules, imports no game system): the kind table
  (`kind`, `is_kind`, `kinds`, `all_covers`), `part` and `total`.
- `GameState.boost_parts(kind)` gathers the sources (it holds their state): checks `Boosts.is_kind`
  (`[]` + error if not), then appends `Toys.parts(toys, catalog, kind, now)`. A new source appends
  its own `X.parts(...)` there and calls `_boosts_changed()` when its state changes.
- `GameState.boost(kind)` is cached in `_boosts` (kind -> total; it runs every frame for errand
  meters and the machine). `_boosts_changed()` clears it: on `toys_changed`, new game, load, and the
  once-a-second tick (plays run out). `boost_parts()` is not cached.
- `Toys.parts(state, catalog, kind, now)`: one part per edition working now (playing or favourite).
  `Toys.multiplier` is deleted (tests use `Boosts.total(Toys.parts(...))`).
- `Toys.KINDS` and `Toys.ALL_COVERS` are gone: the kind table owns them (`"all": true` on coins, xp, luck).
- `GameState.toy_boost` is REMOVED; its 18 call sites (game_state 15, machine_tab 1, errands_tab 2)
  call `boost()`. A lane still calling `toy_boost` fails to parse at merge, so it can't quietly
  skip new sources. Fix: rename to `boost`.
- New kinds with no source yet (all 1.0, nothing changes):
  - `errands`: multiplies `GameState.job_rate()`.
  - `automation` ("automation speed", the name in docs/picks.md): every timed automation job.
    Multiplies the seconds in `_work_for_automation` (your pet's crank and the workers' machines and
    tables, live and away), the out-of-sight box timer (`_open_in_background`) and the on-screen
    PackJob's rest between packs; divides the automation tab's "a pull every Ns" and the crank
    animation. Not adventures (they run on the trip's own clock).
- Gear stays out: the tote still multiplies trip coins in `_boost_trip_loot` next to
  `boost("loot") * boost("coins")`, and gear luck still adds to success chance.
- Dev step `boosts`: logs every kind's total and parts to the flow log, e.g.
  `boost speed x1.100 toys snail:normal x1.100`.

## Files
- data/boosts.json (new), scripts/core/boosts.gd (new), scripts/core/catalog.gd (`catalog.boosts`)
- scripts/machine/toys.gd, scripts/game_state.gd, scripts/ui/machine_tab.gd, scripts/ui/errands_tab.gd,
  scripts/ui/automation_tab.gd, scripts/ui/pack_job.gd, scripts/dev/dev_driver.gd
- tests/test_core.gd (`_test_boosts`; the toys test checks bonuses against `Boosts.is_kind`)
- tests/flows/toys.flow (`boosts` step after the quick play)
- docs/design.md (Boosts paragraph after capsule toys), docs/architecture.md (Boosts section; the
  core line keeps "no game rules")

## Data shape
```json
{ "sources": ["toys", "book", "knacks", "kitchen"],
  "kinds": [ { "id": "coins", "name": "coins", "all": true }, ... ] }
```
Part: `{ "source": "toys", "id": "acorn:holo", "x": 1.14 }`. Total = product of every x (1.0 with none).
`sources` order and `name` are for the receipt later; nothing shows them yet.

## Save
No save change.

## Checks
- test_core: ALL PASSED (3286 checks). `_test_boosts` shows totals and parts: no toys = no parts;
  two acorns + the moth playing = 3 coins parts, 1 luck, 0 speed, 0 fever; the coins total = the
  product of each edition's `Toys.boost`; a finished play stops counting; a favourite counts
  without playing; a fake book part x1.5 multiplies the total; an unknown kind isn't in the table.
- tools/balance.gd output is byte-identical before and after (diffed).
- Flows re-run, all PASSED: toys, errands, errand_tools, machine, automation, workers, fits
  (after the review fixes: toys, fits, automation, workers, errands, machine; balance still
  byte-identical to the committed code).
  Screenshots look the same as before (no UI changes). machine once printed "2 resources still in
  use at exit" at quit; four more runs (with and without this change) didn't, so it's flaky and not
  from this step.

## Merge notes
- Rename any `toy_boost(` in other lanes to `boost(`.
- The kitchen (9712be2, not on this branch) should become source `kitchen` of kind `errands`:
  append `Boosts.part("kitchen", "kitchen", 1.0 + kitchen_bonus())` in `GameState.boost_parts`
  (only for kind `errands`), call `_boosts_changed()` where the kitchen's crew changes (and in
  `_crews_changed`), and take it out of the tools'
  speed sum in `job_rate` (which now ends `* boost("errands")`). Adding and multiplying give
  slightly different numbers, so diff the balance at merge.
- A4 (book stickers) and D1 (knacks) plug in the same way as sources `book` / `knacks`: append in
  `GameState.boost_parts`, call `_boosts_changed()` when a sticker opens / the active pet changes.

## Text to add
**docs/dev-plan.md (B2):** B2 boost plumbing built (lane b2-d1): `GameState.boost(kind)` /
`boost_parts(kind)`, `Boosts` + data/boosts.json kind table, toys are the first source, `toy_boost`
removed. Kinds `errands` and `automation` exist with no source yet. Receipt UI by the coin pill
still waits for its look.

**CLAUDE.md "where we left off":** B2 boost plumbing: every multiplier goes through
`GameState.boost(kind)` / `boost_parts(kind)` (parts `{ source, id, x }`, sources multiply; kinds in
data/boosts.json; scripts/core/boosts.gd is just the table + arithmetic). Toys are the only source
so far (`Toys.parts`); book/knacks/kitchen append theirs in `GameState.boost_parts` and call
`_boosts_changed()` (boost() totals are cached). Kind `automation` = automation speed (crank, box
opening, workers; not adventures). `toy_boost` is gone. Dev step `boosts` logs every
kind. No receipt UI yet, no save change.

## Questions for Emilia
- Should automation speed also make automated adventures quicker? For now it covers the timed jobs
  (crank, box opening, workers) and not trips.
- Should the kitchen multiply errand speed (as a boost source) instead of adding to the tools' speed?
- Should any gear (the tote, the lucky charm) count as a shared boost? For now it stays inside adventures.
