# A1 pacing simulator: done notes

## Built

- `tools/pace.gd` (SceneTree): the arguments, runs the players, prints the milestones, coins a
  minute by source every 10 minutes (and by errand job), the gates (minutes waiting on bits, then
  on coins), and what coins went on. `--tweak=<path>=<value>` changes a catalog value in memory
  (the path starts at a Catalog field; in a list it picks the entry with that id, or an index),
  so suggested numbers can be tried without touching data/ (a value that isn't JSON is refused, an
  index out of range says "can't set"). It tidies up its scratch files, and refuses to run without
  `-- --profile=<name>`. Numbers print as 950 / 12.3k / 4.5M / 1.2B / 7.3T.
- `tools/pace_player.gd`: one pretend player on its own GameState instance
  (`load("res://scripts/game_state.gd").new()`, never in the tree, `_can_save = false`, a scratch
  save path, then `debug_new_game()`). It plays through the real functions and keeps its own
  clock:
  - it moves trips (`started` / `next_at`), fever and rummage timestamps onto the sim clock
  - errands run with `_work_for(1.0)`
  - automation repeats `_work_for_automation` so your pet's crank and the workers count
    separately, then `_auto_adventures()`
  - the passive coin and care follow `_process`
  - these copies (`_automation`, `_zoom`, `_passive`) and the moved timestamps have to be kept in
    step with GameState by hand; both headers list them. The machine node `chute2` is the one gate
    off the repair/drops branches (`GATE_NODES`, checked against the tree at start), and a new
    machine spot's worker speed comes from `Automation.worker_speed`.
- Player styles: `steady` (default) and `casual`. `--treats` also tosses every treat on its own
  trips, the same way as `_zoom_runs`, so the pouch counts.
- `tools/machine_pace.gd`: one comment line pointing to pace.gd.
- `docs/reports/pace.md`: the findings and suggested numbers. docs/architecture.md (Testing) and
  docs/design.md (the start) each got a short mention.

## Data, save, UI, flows

- **Data:** unchanged. **Save:** no change, no version bump. **UI, flows, dev steps:** none.
- Run: `godot --headless -s tools/pace.gd -- --profile=test-sim [--minutes=240] [--runs=5]
  [--style=steady|casual] [--seed=1] [--treats] [--tweak=...]`. A 10-minute single run takes under
  a second. A 4-hour steady player takes about 100 s: after better drops it has 3000 pets.
- Checks: test_core ALL PASSED (3341), balance.gd runs, and the fits flow passes.
- Note: any `-s` script (tests and balance too) makes Godot create the GameState autoload, which
  saves a fresh save.json into the profile when it quits. That was already true before this step.
  The sim's own GameState never saves.

## Review fixes (same step)

- `--tweak` sets list entries by index (`--tweak=rummage_spots/0/coins/1=10`) and prints the
  change; non-JSON values are refused.
- pace.gd refuses to run without a profile; headers now say exactly which rules are copied.
- `GATE_NODES` const + start check; spot-machine gain uses `Automation.worker_speed`.
- `_buy_gear` stops when `buy_gear` refuses (no endless loop); `_num` has a T step.
- Follow-up steps (not done here, each its own step):
  - one clock in GameState (`clock_offset` + `now()` everywhere it reads the time, `_process` body
    in `tick(delta)`, `_work_for_automation` returning coins per source) so the sim drops its
    copies and calls `gs.tick(1.0)`.
  - any `-s` tool makes the GameState autoload load and save the (profile's or real) save.json;
    GameState._init could set `_can_save = false` when a tool script is the main loop.

## Text for the docs

**docs/dev-plan.md**, A1:
> **Built (2026-09-28, plan in docs/plans/A1.md):** `tools/pace.gd` + `tools/pace_player.gd`: pretend
> players (steady / casual, `--treats`) on the real GameState with a sim clock; milestones,
> coins/min by source, gate waits; `--tweak` tries numbers in memory. Report: docs/reports/pace.md
> (suggested numbers, not applied). Findings:
> - errands earn 10-50x the lever (stacked multipliers; tools priced in coins, pay in capsules)
> - bits are the only gate on the tree (coins never wait)
> - the pond opens late (glass)
> - 50-coin boxes flood pets
> - automation is bought the minute it opens and pays ~1% of the lever
> - 60 trips isn't reached in 4 h
>
> **Open questions for Emilia:** see the report.

**CLAUDE.md "where we left off"**:
> - A1 (lane sim): tools/pace.gd plays pretend players (tools/pace_player.gd) on their own
>   GameState with a sim clock, through the whole early game. Prints milestones, coins/min by
>   source, and gate waits. `--tweak=<path>=<value>` tries a number without editing data/.
>   Report with suggested numbers: docs/reports/pace.md (nothing applied). Re-run it after big rule
>   or data changes. Run: `godot --headless -s tools/pace.gd -- --profile=test-sim --runs=5`.

**docs/architecture.md** and **docs/design.md**: already edited in this lane (Testing section, and a
line under "The start").

## Questions for Emilia

See docs/reports/pace.md, "Questions". In short:
- should errands out-earn the lever?
- how much should your pet's crank matter?
- boxes priced in capsules, or a lower crew_power?
- is the pretend player the right player?
- is 4 hours the early game? (toys left out)
