# Architecture

How the code is laid out and where new things go. Game design lives in `design.md`.

## Layers

```
data/*.json          what exists: parts, rarities, finishes, traits, boxes (tune here, not in code)
scripts/core/        generic helpers with no game rules (Catalog loads data/, Weighted picks, Boosts: the boost kind table and its arithmetic)
scripts/pets/        pet rules and pet visuals (Pet, PetRoller, Collection, Knacks, PetLook, PetView)
scripts/adventure/   adventure rules: runs, events, parties, rewards, rumours, the pet's voice
scripts/idle/        errands (Jobs) and automation (Automation): pure rules for idle jobs, see data/errands.json, data/automation.json
scripts/machine/     the capsule machine (Machine) and capsule toys (Toys): pure rules, see data/machine.json, data/toys.json
scripts/dev/         debug-only: launch flags, test profiles, scripted test flows (DevDriver)
scripts/game_state   the player's progress + saving (autoload "GameState")
scripts/ui/          screens and widgets; they read GameState and call its functions
scripts/platform/    everything OS/compositor specific, behind WindowSource
scripts/home.gd      the window: switches layers, sizes the window, runs the desktop pet
```

Dependencies only point downwards: UI → GameState → pets → core → data. Nothing below the UI
knows the UI exists; state changes are announced with signals (`GameState.changed`,
`Collection.pets_added`, `Collection.active_changed`).

## Boosts

- One plumbing for every multiplier: `GameState.boost(kind)` (the total) and
  `GameState.boost_parts(kind)` (what makes it: `{ source, id, x }`). Kinds are in
  `data/boosts.json`. `Boosts` (core) is only the kind table (`kind`, `is_kind`, `kinds`,
  `all_covers`), `part()` and `total()` (the product, 1.0 with none); it imports no game system.
- `GameState.boost_parts` gathers the sources, since it holds their state: it checks the kind
  (`[]` and an error for an unknown one), then appends `Toys.parts(toys, catalog, kind, now)` (one
  part per edition working now), `Book.parts(catalog, stickers, kind)` (one per open sticker),
  `Knacks.parts(...)` (your active pet) and, for "errands" only, the kitchen
  (`Boosts.part("kitchen", "kitchen", 1 + kitchen_bonus())`; `job_rate` divides it back out for
  the kitchen itself). A new source appends its own `X.parts(...)` there, and calls
  `_boosts_changed()` whenever its state changes (`check_book`, `_kitchen_changed`).
- `boost()` is called every frame (errand meters, the machine), so totals are kept in `_boosts` and
  cleared by `_boosts_changed()`: on `toys_changed`, a new game, a load, and the once-a-second tick
  (plays run out). `boost_parts()` is never cached (the `boosts` dev step, the receipt later).
- Game code only ever calls `boost()`; no source has its own multiplier call.
- Knacks (D1) are the second source: `Knacks` (scripts/pets/knacks.gd, static, pure: a gate
  Callable goes in) works a pet's knacks out of its parts and finish; nothing is saved. `of` /
  `best` build display rows (the UI only). Totals (`total`, `parts`, `own`, `party_all`) take the
  lean path: `counting(kind)` makes a lookup table once (slot -> part id -> size before the
  finish, only parts whose knack kind counts and is open), `sum_in` / `own_in` then add a pet up
  with no rows or strings (about 2.5 us a pet a kind). `GameState.boost_parts` appends
  `Knacks.parts(catalog, collection.active(), kind, knack_gate)`. `knack_gate(gate)` answers
  "adventures", "machine:<node>" and unlock ids. `GameState.knack_own(pet, kind)` keeps each
  pet's own share by uid (`_knack_own`, tables in `_knack_steps`). `_knacks_changed()` (a pet's
  parts, a new game, a load, a regate) clears boosts, those and the errand and worker speeds;
  `_knack_gates_changed()` (unlock, unlocked, machine_upgraded, tutorial_changed, debug lock-all,
  the `fix` dev step) clears boosts and the knack caches, clears the errand / worker speeds only
  when the tables for "errands" / "automation" changed, bumps `knack_version` and emits
  `knacks_changed` (the collection grid redraws its badges only when the open kinds differ from
  its last draw). active_changed only clears boosts (your active pet never works). Other pets:
  `_pet_speed` (errand speed x `knack_own(.., "errands")`, used to pick who goes on and who comes
  off), `workers_speed` x `knack_own(.., "automation")`. The adventures tab keeps
  `trip_knacks(pets)` by a key of place, picks, gear, active pet, trip boosts and `knack_version`,
  so a big swarm isn't walked on every click. Trips pack `RunState.knacks` when they set off
  (`GameState.trip_knacks`: boost x party share for trip, tough, safe, spots, finds, pickups,
  treats; loot is the party share only), read with `run.knack(kind)` (1.0 when missing):
  `AdventureRunner.walk_of` (boots then / trip), hurt and injured counts / tough, lost / safe,
  `Intel.roll(.., x)` lead chance x spots, trail pickups, treat zoom, extra bits and parts in
  `_boost_trip_loot`.

## Pets

- `Pet` is plain data (parts, finish, traits, stats, rarity) with `to_dict` / `from_dict`.
- `PetRoller` rolls pets like card packs: the rarity is rolled once with the box odds, one
  "signature" part gets that rarity, the others roll at or below it. The finish is a separate
  roll. So the odds shown on a box are exactly what you get (checked by `tests/test_core.gd`).
  Box tiers: `PetRoller.roll_box` rolls a box's `pets` [min, max]; parts come from
  `Catalog.parts_in(slot, tier, box)` (a part with `from` only rolls from that shop box or a later
  one; `Rewards.roll_part` does the same with a place's box). `BoxShop` (scripts/pets) holds the
  tier rules tests can reach: `open_tiers` (a tier is in the shop once its map page is open),
  `split_open` (workers open N boxes, not N pets), `best_first`, and `fix_retired` (lucky boxes).
  `Catalog.parts_in` and `box_rank` are cached (catalog data never changes after loading);
  box workers open at most `GameState.WORKER_BOXES_MAX` boxes at once.
  `GameState.shop_boxes / stash_boxes / box_is_new / boxes_bought / boxes_greeted`.
- `Collection` owns the pets, the active pet and the book counts (`part:<slot>:<id>`,
  `finish:<body>:<finish>`).
- `Book` (scripts/pets/book.gd, pure rules, data/book.json) says which book page is full and what
  its reward sticker multiplies. `GameState.stickers` keeps the opened ones for good,
  `check_book()` opens new ones (`sticker_opened`, shown by `UnlockPopup`), and
  its stickers are the `book` boost source (coins, luck, errands, automation; see Boosts).
- `PetLook` is the placeholder art (pixel maps in code). Real art replaces `PetLook` only;
  `PetView` (draws a pet, blinking, squash, finish shader) and everything above stay the same.
- Finish effects are one shader, `shaders/finish.gdshader`; `finishes.json` picks the mode.

## Screens

`home.gd` holds two layers inside one window:

- `CompactView` - the small idle panel (active pet opening packs, needs, feed / pat / let out).
- `ExpandedView` - the full game: the `Spine` of tabs and the page. Tabs: `HomeTab` (the pet's
  room), `MachineTab` (the capsule machine: `MachineStage` draws it and runs the lever, `Machine` in
  scripts/machine has its rules, `GameState.pull_lever()` pays out; a pet box out of a capsule is opened right there with a
  `PackOpening`; `OddsCard` is the "prizes" tag that flips into the odds card, from
  `Machine.odds` via `GameState.machine_odds`, refilled on machine_upgraded / toys_changed /
  unlocked / tutorial_changed while open, placed on the stage's resize), `BoxesTab` (shop, `PackOpening` for one box, `BoxReveal` grid for many),
  `CollectionTab` (pets grid + `PetDetails`, and the `BookView`), `AdventuresTab` (adventures:
  `MapView`, the place card, trip cards, and `TrailView` for watching a trip; upgrades: `GearView`,
  gear bought with xp, rules in `Gear`, levels in `GameState.gear`, packed onto each trip as
  `RunState.gear`), `ErrandsTab` (jobs: the corkboard; upgrades:
  `ErrandToolsView`, the pegboard of tools bought with coins; rules in `Jobs`, levels in
  `GameState.errand_tools`; tool and box prices are in capsules x `GameState.capsule_value()`
  (`Jobs.tool_cost(tool, have, n, value)`, `GameState.box_price` / static `box_cost`); the kitchen speeds every other job via `GameState.kitchen_bonus()`, the `kitchen` source of the "errands" boost (its line: `Jobs.faster_words`),
  scouting fills `GameState.scout_notes` and `send_on_adventure` packs one onto `RunState.scout`,
  read by `Intel.roll` and `AdventureRunner`), `AutomationTab` (a card per job your pet can do, `JobScene` draws each one; rules in
  `Automation`, state in `GameState.automation`: what's taught, the one job it does, tools, the party; the workers page:
  `WorkerCard` / `WorkerSpot`, `GameState.put_workers` / `buy_spots` / `teach_others`; the whistle page: `Clipboard`,
  `TodoRow`, `Tick`, `TinyCrowd`, rules in `Automation.whistle_plan` / `exist` / `checks`, applied by
  `GameState._whistle_checks`, caps via `GameState.spot_room`), `InventoryTab`
  (the bag and sewing) and `SettingsTab` (general and video pages).
  Tabs can be locked or hidden until something opens them (`data/unlocks.json`).
- The full game is laid out at 920x600 (`home.gd` `EXPANDED_SIZE`) and scaled to the chosen
  resolution with `content_scale_factor`, never past what fits the screen. Nothing may need more
  room than that: long one-line labels shrink with "…" or wrap (checked by `expect fits`).

`scripts/ui/reveal/` is the single-box ritual: `PackOpening` runs the steps (land, rip, light
climb, peek, pull, mist, celebration, result) and owns input and timing; `CardPack`,
`RevealEffects` (stacking effect layers named in `data/reveal.json`), `RevealBlocker` (the mist)
and `RevealResult` only draw. Every tween goes through `PackOpening._tween()` so the reveal
speed setting and skipping apply to all of it.

A new tab is a new Control added in `ExpandedView._init`. Shared colours, the Theme and small
widget helpers live in `UiTheme`.

## Platform

`WindowSource` is the only place that talks to the OS or compositor about windows:
where other windows are, fullscreen apps, the mouse, placing the overlay, sizing the home window
and the UI scale. The base class has plain Godot fallbacks; `HyprlandWindowSource` does it through
`hyprctl` (window rules can't be used because Godot sets titles after windows open, so it styles
our windows with direct dispatches). The Windows port adds a `WindowsWindowSource` backed by a
small GDExtension; nothing else should need to change.

## Saving

`GameState` saves to `user://save.json` every 30 s, after opening boxes and on quit. The file
has a `version`; `GameState._migrate` upgrades older files step by step, so bump
`SAVE_VERSION` and add a migration step whenever the format changes.

Gates live in data: an unlock id opens things (`GameState.is_unlocked`), an adventure event can
wait for a find (`after`) or a fixed machine node (`after_machine`, checked in
`AdventureRunner.pick_events`), and an errand can wait for an unlock (`needs`, see
`GameState.open_jobs`). The machine tree's card says where a missing bit comes from
(`GameState.bit_hint`, from the places' `finish_rewards` and `leads_to`).
An unlock's `earn` can also wait for another unlock (`open`, e.g. the workbench from parts waits
for `feature:parts`). Save v20 re-gates saves from v15-v19: whatever `data/unlocks.json` opens
closes again unless something earned opens it (`UnlockRules.stale`); places stay open, older
saves (and the test saves) keep what their migrations gave them. Save v21 moves your pet opening boxes
into automation: a save with the cushion gets the automation tab and the boxes job (doing it if it was on).
Save v22 adds `gear` (older saves start with none; loading drops unknown gear and clamps levels);
runs save the gear they packed and the leaf's saves (`RunState.gear`, `saves_used`).
Save v23 adds `scout_notes` (older saves start with 0); runs save the scout note they took
(`RunState.scout`). The new jobs' crews and tool levels ride in the existing `jobs` / `errand_tools`.
Save v24 adds `stickers` (book page ids; older saves start with none and get the stickers of
already-full pages, with their popups, right after loading).
Save v25 keeps your pet's box reserve in capsules (`reserve_capsules`, replacing `coin_reserve`):
the coins an older save kept become capsules at what one was worth on its machine (at least 1 if
it kept any). `GameState.coin_reserve()` is the coins that means now.
Save v26 retires the lucky box and adds box tiers. `BoxShop.fix_retired` runs on every load,
whatever the save's version (idempotent): lucky boxes on the pile, "save for me" and loot of runs
still out (also pre-v5 runs' `boxes`) become sunset boxes, and unknown box ids are dropped from the
bag. New fields `boxes_bought` (a tier is "new!" until the first) and `boxes_greeted` (its arrival
played); a save without them counts what's on the pile as bought and greeted.
Save v27 adds the whistle, `automation.whistle` = { ticks: { job: { haul, fill } }, keep, wait }
(no migration: a save without it starts with every tick on and the default set aside);
`automation.taught.whistle` comes back from the `feature:whistle` unlock.

## Testing

- `godot --headless -s tests/test_core.gd -- --profile=core-test-<lane>` - data sanity, box odds over 100k
  rolls, save round trip, adventures, errands. With a profile it also tests GameState itself
  (`_test_game_state`): `_state_from(save)` writes a save dict into the profile and makes a fresh
  `GameState` from it (no scene tree, about 0.1 s; `saved_at` in the future unless a test wants time
  away). Old saves are built in code (`_old_save`, `_v21_save`). Covered: migrations v14..now and a
  round trip, crank catch-up with and without the stool, the auto-adventure loop, thousands of
  workers with time budgets, gear (A2) and the jar, kitchen and scouting (A3). Without a profile
  those are skipped (they must never touch the real save) and the last line says "BUT SKIPPED".
  The profile must be one of your own: every `user://` is shared by all worktrees (it's keyed on
  the game's name), so each lane uses its own name (`core-test-x4`, like `DESK_PETS_LANE` for
  `play.py`), and the name `test` is refused (every `--from=<save>` run plays in it). Time limits
  print their times and fail at 5x a quiet machine's time; `DESK_PETS_SLOW=3` stretches them when
  several copies run at once.
- `godot --headless -s tools/balance.gd` - what every place pays per minute, and errands for
  crews of 1 to 1000.
- `godot --headless -s tools/pace.gd -- --profile=test-sim [--minutes=240] [--runs=5]
  [--style=steady|casual] [--treats] [--tweak=<path>=<value>]` - the pacing sim (A1): pretend
  players (`tools/pace_player.gd`) play a fresh game on their own `GameState` instance (never in the
  tree, saving off, the sim's own clock: trips, fever and rummage timestamps are moved onto it) and
  call the tabs' real functions. Prints milestones (median minute), coins a minute by source every
  10 minutes, how long each gate waited on bits and on coins, and what coins went on. `--tweak`
  changes a catalog value in memory (by id or index in a list) to try a suggestion without touching
  data/. It refuses to run without `--profile`. Kept in step by hand: `pace_player.gd` copies
  `GameState._work_for_automation`, `_zoom_runs` and the coin/decay part of `_process`, so re-check
  those when they change. Report: docs/reports/pace.md. `tools/machine_pace.gd` is the older
  tree-only check.
- `python3 tools/play.py <flow>` - plays `tests/flows/<flow>.flow` in a test profile (its own save
  and settings, window parked off-screen), prints the log and saves screenshots. Steps are listed
  in `DevDriver`; `expect fits` checks the full game fits its window. Test saves: `tests/saves/`.
- A headless script check must use a profile: `godot --headless --quit-after 30 -- --profile=check`
  (without one it loads and saves the real save).
- `godot -s tests/look_sheet.gd -- out.png` - renders every part and finish into one picture.
- Debug launch flags (`DevArgs`): `godot . -- --expanded --tab=collection --book --open=starter:10`,
  and `--open=starter:1 --force=mythic --autoplay` to watch a reveal at any rarity hands-free.
- `python3 tools/film.py <out_dir> <name> "<godot args>" 1.5 3 5` - launches the game on Hyprland
  and screenshots its window at those times (combine with `--autoplay` to check animations).
