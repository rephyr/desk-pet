# X4 Tests: done

## What was built

New GameState tests in `tests/test_core.gd`, run from `_init` through `_test_game_state`:

- `_test_migrations`: a v21 save with everything in use loads with all of it (30 pets, coins, bits,
  machine, unlocks, the automation state: job, tools, crank, party, workers page, workers including an
  empty party slot, parties, wfill; errand crew and tools; a workers' auto party out on a trip in
  slot 0). Gear starts at `{}` and scout notes at 0. A v22 save loads the same as a v21 save. Round
  trip: load, save, load, save gives the same file. v14 cushion saves (on and off) get the boxes job.
  A v17 cushion save keeps it through the v20 re-gating. A v18 save closes parts again but keeps the
  parts. A save from a newer version loads but is never written over. Bad data gets cleaned up:
  scout notes are clamped, unknown gear dropped, jobs that are gone forgotten, bad workers dropped.
  Bad workers are ones who are gone, the active pet, errand pets, doubles, pets on two jobs, and
  workers past the spot count. A party whose leader is gone waits with an empty slot.
- `_test_crank_catch_up`: with the game closed 2 h, no stool means no cranking, and stool lv 1
  cranks exactly 1 h. The same goes for machine workers. A long time away (500 workers, stool 8) loads
  in about 0.1 s and pays coins. Scaling is tested without randomness: the same seed with 4x the
  pulls (`_pet_cranks(800)` vs `_pet_cranks(3200)`) gives exactly 4x the coins. After the computer sleeps, 60 s count
  without the stool and the stool's hour counts with it.
- `_test_auto_adventures`: the policy chooser never waits (every place, 5 seeds) and always picks an
  allowed option. Your pet's party goes out with auto on, slot -1, "policy" and n = 3. The active
  pet, pinned (unseen) pets, workers and errand pets stay home while resting pets can go. No scout
  note is taken and gear is packed. Only one party goes at a time. A party that's home is welcomed
  back quietly: trips +1 and idle log `trips`, then the next party goes out. A pet that stays behind
  gets an announcement and leaves your pets. A party set to a closed place, or to no place, goes to
  the first open place that takes a party. Nothing is sent during the tutorial.
- `_test_many_workers`: 5000 pets on 2000 machines, 1000 tables and 200 parties.
  - Fastest workers go on first. Nobody works two jobs, and neither the active pet nor errand pets
    are used. `workers_speed` is the sum of the worker speeds.
  - Time limits (`_check_quick`): each prints its time, even when it passes, and fails at 5x a quiet
    machine's time multiplied by `DESK_PETS_SLOW` (default 1). Quiet times: putting 2000 on about
    0.2 s, an hour of work about 0.15 s (saves held, as in the tick), sending 200 parties about 0.3 s,
    save plus load about 0.6 s, a long catch-up load about 0.15 s.
  - Taking party leaders off leaves empty slots at the end. A lost pet frees its machine and its
    party waits.
  - Box workers open the pile and never buy.
- `_test_gear_state` (A2): `buy_gear` spends xp, and refuses when the gear is hidden, xp is short or
  the gear is at max. Trips you send and auto parties both pack gear; dungeons pack none. Gear and
  each trip's packed gear survive a save.
- `_test_jobs_state` (A3):
  - The kitchen speeds the other jobs by exactly `1 + kitchen_bonus` but not itself. It feeds your
    pet up to `meal_upto` and never feeds a full pet down.
  - Scout notes fill to the hold, then the meter waits (`job_fill_now` = 1). The map case holds one
    more. A trip you send takes a note and a party your pet sends doesn't. Notes survive a save.
  - A full jar pays exactly one chunk (capsules x coin value).
  - `share_out` skips the kitchen and scouting.
  - The job-level chain opens lemonade, kitchen, jar and scouting, including a real
    `buy_errand_tool(-1)`.

How they reach GameState: `_state_from(data, away)` writes the dict into `DevProfile.path("save.json")`
(after deleting .bak/.tmp) and runs `load("res://scripts/game_state.gd").new()`. The GameState
autoload is not loaded in `-s` mode, so nothing else touches that file. `saved_at` is set 60 s in the
future unless a test wants time away, so loading catches nothing up. Without `--profile` these tests
are skipped, and the last line says so ("ALL PASSED, BUT SKIPPED the GameState tests (no
--profile)"). The profile name `test` is refused and counts as a failed check, because every
`--from=<save>` run plays in that profile. `user://` is shared by all worktrees, so each lane passes
its own name (`--profile=core-test-<lane>`). The profile save is deleted at the end. They take about
2-4 s.

## Bugs found and fixed

- **Sending auto parties slowed down with many pets.** `send_on_adventure` rebuilt `sendable_pets()`,
  a pass over every pet, for each party sent. With 5000 pets, sending 200 parties took about 0.7 s
  quiet and 2 s under load. It now checks each pet directly (in the collection, not active, not
  away), which gives the same result. The scout-note check (`Rumours.hearable` / `Intel.left_to_find`)
  now only runs for trips you send while holding a note. 200 parties now take about 0.08 s on a quiet machine (0.2-0.3 s with other lanes running).
  (scripts/game_state.gd, `send_on_adventure`, with a comment on why the cheap checks come first.)

## Review fixes (second pass)

- The "4x the time away brings about 4x the coins" check could fail at random (1 in 6 runs). Each
  load scaled up a different random sample of 200 capsules. It is now a seeded check on
  `_pet_cranks` itself and gives exactly 4x. The load-time checks only test the time and that coins
  come in.
- The docs used `--profile=test`, which is shared by every worktree and wiped by `--from=` runs.
  They now use `--profile=core-test-<lane>`, and the tests refuse `test`. A run without a profile
  now says "BUT SKIPPED" in its last line.
- Time limits print their times and scale with `DESK_PETS_SLOW` (see above).

## Problems left (not fixed here)

- Each save with 5000 pets takes about 90 ms. `put_workers`, `buy_spots`, `open_boxes` and each
  `send_on_adventure` outside the automation tick save straight away. That's fine at these sizes, but
  it will need batching at 100k+ pets.
- Box workers opening boxes outside the tick (for example a direct `_workers_open`) save once per box
  kind. In the game the tick holds the saves, so only the tests saw this.
- Not caused by this step, but seen in the tutorial flow's `adventures.png`: on the first map, the
  lead labels at the edges are cut off ("gears out this way?" on the left, "bolts out this w" on the
  right). The "the garden path" label sits under the speech bubble.

## Files

- tests/test_core.gd (new tests and helpers)
- scripts/game_state.gd (`send_on_adventure` speed fix)
- docs/architecture.md (Testing section)
- docs/plans/X4.md, docs/plans/X4-done.md

## Data, save, flows, dev steps

- No data changes. No save change: SAVE_VERSION stays 23, no bump.
- No new flows or dev steps. `fits` and `tutorial` flows pass.
- Checks: `godot --headless -s tests/test_core.gd -- --profile=core-test-x4` gives ALL PASSED
  (3446 checks). `tools/balance.gd` passes.

## Text to add

**docs/dev-plan.md** (X4):

> - **X4. Tests:** done. `tests/test_core.gd` now tests GameState itself in a test profile
>   (`_test_game_state`): save migrations v14..now plus a round trip, crank catch-up with and without
>   the stool, the auto-adventure loop, thousands of workers with time limits, gear (A2) and the jar,
>   kitchen and scouting (A3). It found that sending hundreds of auto parties was slow with many
>   pets, and that is fixed.

**CLAUDE.md, "where we left off"**:

> - X4 tests: `godot --headless -s tests/test_core.gd -- --profile=core-test-<lane>` (use `main` in
>   the main checkout; never `test`, which is refused) now also makes real GameStates from saves
>   written into the profile (`_state_from`). They cover migrations from v14 up, crank catch-up, auto
>   adventures, 5000 pets on 3200 workers with time limits, gear and the new errand jobs. Without a
>   profile those tests are skipped and the last line says "BUT SKIPPED". Time limits print their
>   times; `DESK_PETS_SLOW=3` stretches them when lanes run at once. `send_on_adventure` no longer
>   goes through every pet for each party it sends.
>
> Also change the "Checks:" line in CLAUDE.md to:
> - Checks: `godot --headless -s tests/test_core.gd -- --profile=core-test-main`, `godot --headless -s tools/balance.gd`.

**docs/architecture.md**: done in place (Testing section).

**docs/design.md**: nothing (no design change).

## Questions for Emilia

- Welcome-back payouts: after a long time away, `_pet_cranks` rolls 200 capsules and scales them up
  to every pull made. One lucky golden or shiny capsule in those 200 can be multiplied thousands of
  times. Rolling more (say 1000), or scaling only the plain coins, would make the payout steadier.
  Not changed here because it's a balance call.
