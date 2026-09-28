# B3 done: automation layer 2, the whistle (look A, the to-do list)

## What was built
- **The find:** a tiny whistle at the old well (event `well_whistle`, auto find) once you have
  **30 workers** (all jobs added up). New event key `after_workers` (AdventureRunner.pick_events /
  start take `workers`, GameState passes `workers_total()`). Unlock `whistle` opens
  `feature:whistle` (popup "new: the whistle!", go automation, announce "tweet! everyone, line up!").
  Opening it marks the whistle as taught (`GameState._opened`), no teach price.
- **The switch** grows a third button: your pet | workers | whistle (with a whistle doodle). The
  popup's "show me" lands on the whistle page.
- **The whistle page** (AutomationTab `_rebuild_whistle`): a clipboard (lilac board, clip on top,
  paper with a pink margin line) with "<pet>'s list", a `TodoRow` per job taught to the others:
  icon + "machines" + "N working" + a `TinyCrowd` (5 bobbing pets), the big "home" number with
  "home, N out there" (parties: "of N places"), and two `Tick`s: haul them home (parties: start new
  ones) / keep them full. Under it "N pets resting" + a tiny crowd.
- **Side card:** "the whistle", your pet (nobody here / move it here; <pet> is here ♡ managing /
  take it off), "set aside − 250k +", upgrades (a sharper pencil, a bigger wagon: normal
  ToolRows), and a "since you looked:" foot (+N tables hauled home, N pets put to work) only when
  something happened (reset when you leave the page or the tab).
- **Managing:** task `"whistle"` (pill "<pet> is managing"). Every `check_seconds` (10 s, the pencil
  makes it faster) your pet checks: hauls `whistle.haul` (1) + wagon spots per check, the cheapest next spot among
  jobs with "haul" ticked first, never spending under set aside, only while some are out there;
  then puts the best resting pets on empty spots of jobs with "fill" ticked. Parties (jobs whose
  spot has `per_place`) are filled first: empty parties get a leader, then (leaders - parties out
  right now) x the job's `party` resting pets are set aside for them before machines and tables
  fill. A party is only hauled home while (empty parties + 1) x (1 + party) resting pets are free.
  A new party goes to an open place none of the workers' parties goes to yet (also when bought by
  hand).
- **Caps:** `spot.exist` { page: count } per open map page (machines backyard 60 / beyond 600,
  tables 20 / 200), parties `per_place: 1` per open place. The cap holds for buying by hand too
  (the "+1 machine" button is gone at the cap). Saves with more keep them ("none out there").
- **Flattened prices:** past `flat_at` each spot grows by `grow_late`. `Jobs.tool_cost` is
  piecewise with geometric sums for big buys (a plain loop for up to 64 levels, so small buys cost
  exactly what they did); "as many as you can afford" is a binary search (`Automation.affordable`).
- **"show me" lands on the whistle page:** UnlockPopup's `go` signal now carries the unlock id
  (`go(tab_id, unlock_id)`), `ExpandedView.show_tab(tab_id, unlock_id := "")` calls the tab's
  `show_unlock(id)` if it has one, and `AutomationTab.show_unlock("whistle")` picks page 3. Dismissing
  the popup ("lovely") leaves the page alone.
- **Offline:** the checks run inside `_work_for_automation`, after the workers' income for that
  time, for the stool's away hours (same as the workers).

## Files
- data/automation.json (spot `flat_at`, `grow_late`, `exist` / `per_place`; `whistle` block: check_seconds, haul (base per check), keep, keep_steps, tools; _note)
- data/unlocks.json (unlock `whistle`, find `whistle`, _note), data/adventures.json (`well_whistle`,
  added to the well's events; `after_workers` in _note), data/voice.json (automation_whistle,
  automation_do_whistle, automation_stop_whistle, automation_tick_on/off, automation_keep,
  automation_tool_wagon, automation_tool_pencil)
- scripts/idle/jobs.gd (tool_cost, _geo), scripts/idle/automation.gd (WHISTLE, whistle_fresh, job()
  knows "whistle", all_tools includes its tools, exist, out_there, affordable, tick, keep,
  keep_step, check_seconds, haul_size, checks, whistle_plan(..., away), _empty, _party_size)
- scripts/adventure/adventure_runner.gd (workers param, after_workers)
- scripts/game_state.gd (_opened, spot_plan/buy_spots capped, _add_spots, _free_party_place,
  open_pages, spot_exist, spot_room, workers_total, _best_resting, _place_workers, whistle_since,
  _whistle_checks, whistle_seen, set_whistle_tick, step_whistle_keep, load of automation.whistle)
- scripts/ui/automation_tab.gd (3-button switch, whistle page, Clipboard, TodoRow, Tick,
  TinyCrowd, DashedTop; workers page hides +1 at the cap; your pet page never picks the whistle)
- scripts/ui/ui_theme.gd (doodles whistle, pencil, wagon)
- scripts/ui/unlock_popup.gd (go carries the unlock id), scripts/ui/expanded_view.gd (show_tab passes
  it on to `show_unlock`), scripts/home.gd (wires it)
- scripts/dev/dev_driver.gd (steps `manage <n>`, `workers <job> <n>` (capped at what's out there),
  `teach <job> others`; `spots` now goes through GameState._add_spots, past the caps on purpose)
- tests/test_core.gd (`_test_whistle`, "whistle" a known feature), tools/balance.gd (spot prices)
- tests/flows/whistle.flow (new), tests/flows/workers.flow (opens a second place: parties are one
  per open place now)
- docs/design.md (Automation: the whistle + caps), docs/architecture.md (AutomationTab line)

## Data shape
- save `automation.whistle` = { ticks: { job id: { haul: bool, fill: bool } } (missing = on),
  keep: int (-1 = data default), wait: 0..1 }. `automation.taught.whistle` = true once found.
  Whistle tool levels in `automation.tools` (pencil, wagon).
- **Save bump: none.** The field is additive; older saves load with all ticks on and the default
  set aside. If the merge wants a bump anyway: 22 -> 23 with no migration.

## Flows / checks
- `DESK_PETS_LANE=b3 python3 tools/play.py whistle` (shots: whistle_popup, whistle_page,
  whistle_managing, whistle_untick, whistle_beyond, whistle_crowd (2,030 machines, 3,000+ pets),
  workers_cap, your_pet_managing). Also passed: workers, automation, fits.
- test_core ALL PASSED; balance prints "workers' spots" (10th / 100th / 1000th, first 10 / 100 /
  1000, how many exist).

## Text to add

**docs/dev-plan.md, B3:** "**Built 2026-09-28 (lane b3):** the whistle (look A, the to-do list):
a find at the old well after 30 workers, a third switch button, managing is your pet's one job,
haul / fill ticks per job, set aside, pencil + wagon, caps per map page (parties one per place),
flattened spot prices, offline with the stool. Open: the numbers (30 workers, caps, set aside,
prices) are placeholders."

**CLAUDE.md "where we left off":** "- B3 (lane b3): automation layer 2, THE WHISTLE (look A): a find
at the old well once you have 30 workers (event key `after_workers`, unlock `whistle` ->
`feature:whistle`, marked taught when found). Automation switch = your pet | workers | whistle;
the whistle page is a clipboard to-do list (AutomationTab Clipboard / TodoRow / Tick / TinyCrowd)
with haul them home (parties: start new ones) / keep them full per job, set aside − / +, tools
pencil (checks faster) + wagon (hauls more). Managing = task "whistle": every 10 s it buys the
cheapest next spot among ticked jobs (never under set aside) and fills empty spots, parties first
with their pets set aside (Automation.whistle_plan, GameState._whistle_checks, offline with the stool). Spots have caps per
open map page (spot.exist; parties one per open place, per_place) that also stop buying by hand,
and prices flatten past flat_at (grow_late; Jobs.tool_cost in one go, Automation.affordable).
Save field automation.whistle (no bump). Dev steps `manage <n>`, `workers <job> <n>`,
`teach <job> others`; flow whistle."

## Questions for Emilia (smallest safe pick made)
1. The whistle turns up at 30 workers: right number?
2. The caps also stop buying machines/tables by hand (backyard 60 / 20, beyond 600 / 200): ok, and
   are those numbers roughly right?
3. Parties: one per open place?
4. The whistle has no teach price (the find is enough): ok?
5. Set aside starts at 250k (steps 0 .. 10B): ok?
6. Hauls go to the cheapest next spot among the ticked jobs: ok, or should it fill one job first?

## Review fixes (after the first pass)
- whistle_plan sets party pets aside (parties filled first) and won't haul a party nobody can lead.
- _whistle_checks only sorts resting pets when the plan puts someone on (early return otherwise).
- dev steps `spots` / `workers` use GameState._add_spots (parties get their own places; `workers` is
  capped, `spots` isn't, for the crowd shot). The whistle flow now shows "1 of 1 place".
- "show me" (not the unlock itself) switches to the whistle page (see above).
- Party wording on the list uses `spot.per_place`, not the job id; `size` in _rebuild renamed
  `page_count`; _load_automation sets the task once; the base haul is data (`whistle.haul`).
- tests: party set-aside checks in `_test_whistle`; `_tolerance` has its doc comment back.
