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
  part per edition working now), `Book.parts(catalog, stickers, kind)` (one `book` part per open
  sticker of that kind), `Knacks.parts(...)` (your active pet) and, for "errands" only, a `kitchen`
  part (x `1 + kitchen_bonus()`, only when above 0), then `Care.parts(catalog, kind, hunger,
  happiness)` (a `care` part per care buff on: full tummy on coins, happy on luck), in
  data/boosts.json "sources" order. A source
  calls `_boosts_changed()` whenever its state changes (`check_book` does); the kitchen calls
  `_kitchen_changed()` (crews, tools, a pet's parts), which also drops the kept "errands" total.
  `kitchen_bonus()` only reads the cooks' own speeds, never `boost()`, so there's no loop.
- Where kinds are read: errands `job_rate` = `Jobs.rate(...)` x (1 + tools' speed) x
  `boost("errands")`, divided by the kitchen part again for the kitchen job itself (it never
  speeds itself); automation: `_work_for_automation` multiplies its seconds by
  `boost("automation")` once (your pet's crank and the workers' machines and tables), the box
  opening out of sight runs its timer x `boost("automation")`, `PackJob` shortens its breaks by it,
  and the automation tab's crank line divides `crank_seconds` by it.
- `boost()` is called every frame (errand meters, the machine), so totals are kept in `_boosts` and
  cleared by `_boosts_changed()`: on `toys_changed` (also emitted when a play runs out), a book
  sticker, a knack or knack-gate change, a new game and a load. `boost_parts()` is never cached (the `boosts` dev step, the receipt).
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
  (`GameState.trip_knacks`: boost x party share for each kind marked `"trip": true` in
  data/boosts.json, `Boosts.trip_kinds`: trip, tough, safe, spots, finds, pickups, treats; loot is
  the party share only), read with `run.knack(kind)` (1.0 when missing):
  `AdventureRunner.walk_of` (boots then / trip), hurt and injured counts / tough, lost / safe,
  `Intel.roll(.., x)` lead chance x spots, trail pickups, treat zoom, extra bits and parts in
  `_boost_trip_loot`.
- The receipt (B2UI): `GameState.boost_receipt()` = `Boosts.receipt(catalog, parts_by_kind, namer)`
  over every kind's `boost_parts` (kinds in boosts.json order, lines in `sources` order, unknown
  sources last; `[{ kind, name, total, lines: [{ source, name, x }] }]`). Line names come from
  `GameState._boost_line_name` (toys: `Toys.edition_name`, book: the sticker's page name, knacks:
  `Knacks.part_names`, kitchen: "the kitchen"; a new source adds its case there). `Boosts.times(x)` formats "x1.25". UI: `BoostTag` (a Button by the
  coin pill in ExpandedView, StitchBox dashes, checks `boost_parts("coins")` every 0.5 s) toggles
  `BoostReceipt` (a Control on ExpandedView's `_paper` overlay, a plain Control child of the page
  body, z `UiTheme.Z_PAPER`, so it adds no minimum size and draws over the tab, under the bubble). The receipt
  refreshes every 30 frames while open (rebuilt only when the rows change), sizes itself
  (`max_height` = the page) and scrolls its lines past that. It also holds the paper drawing both
  papers use (`draw_paper`, `barcode`, `rule`, `leader`: Labels, so flows can find the text).
- "Why so much?": `Boosts.why(start_name, start_value, lines, total)` -> `{ start: { name, value },
  lines: [{ name, x }], total }` (drops lines within 0.005 of x1). `_boost_trip_loot` returns the
  trip's (same maths, recorded as it goes; `collect_run` puts it on the trip as `coins_why`, never
  saved), `capsule_why()` (`Machine.coin_parts`: one `{ id, name, x }` per bought coins_x node,
  their product x base_coins = `coin_value`), `errands_why()` (`_errands_layered(tools, goals,
  tips)`: the per-minute total with layers switched off, each layer = the ratio; layered tips, then
  tools, then goals, so the fancy cups count as a tool). `errands_per_minute()` IS
  `_errands_layered(true, true, true, true)` (each job's errands boost, `_job_errands_x`: the kitchen
  leaves out its own bonus) x the coins boost, "our boosts" = that over the plain total, and `job_rate` /
  `job_boost` / `job_tips` take the same switches (`_job_plain_rate`, `_job_tool_numbers`), so the
  slip always multiplies up to the pill (test_core checks it). `WhyTape` (a
  Button, TapeBox StyleBox) re-reads its `source` Callable every 0.5 s and shows only with a line;
  `WhyTape.wrap(target, source, right)` puts a chip / pill in a plain Control box with the tape on
  its top edge and the `WhySlip` (z 3, ignores the mouse) under it. The machine's tape is a child
  of MachineStage placed at the end of the capsule line when the line changes (the line is worked
  out every 0.2 s; `also`: not in the tutorial or fever). Z order over the page (UiTheme `Z_*`):
  tape 2, slip 3, receipt 4, the machine's prize picture 4, bubble 5, the unlock popup and the
  tutorial guide 10 (z is shared by the whole window); a popup showing folds the receipt. `expect fits` also checks every visible BoostReceipt and WhySlip is inside the window.

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
  `finish:<body>:<finish>`). Pets are **cards** (whole `Pet`s in `pets`) or **the herd** (`herd`:
  `"rarity:finish"` -> count, see `Herd` and data/herd.json). `add()` marks `new_part` and calls
  `refold()`: past `keep_cards` plain cards a shelf, the oldest that may fold (not `always_card`,
  not in `busy`, a Callable GameState sets: away, pinned, party leaders) become counts, and
  `pets_folded(uids, keys)` lets GameState move their errand or machine place to a count.
  `refold()` only walks `_plain_cards` (the plain-finish cards), so piles of holo+ cards cost it
  nothing. Totals
  (`count`, `count_of`, `shiny_of`, `plain_count`) are running numbers: nothing loops over the herd.
  `get_pet("h:<rarity>:<finish>:<n>")` gives a **stand-in** (`Herd.stand_in`: seeded look, average
  stats, no traits); removing one takes it off its count. Stars are `fallen` (palettes, the first
  `fallen_keep`) plus `fallen_n`.
- `Book` (scripts/pets/book.gd, pure rules, data/book.json) says which book page is full and what
  its reward sticker multiplies. `GameState.stickers` keeps the opened ones for good,
  `check_book()` opens new ones (`sticker_opened`, shown by `UnlockPopup`) and clears the kept
  boosts; each open sticker is a `book` part of its kind (`Book.parts`, see Boosts).
- `Care` (scripts/pets/care.gd, pure rules, data/care.json): food (`GameState.hunger`) and mood
  (`happiness`) as buffs. `Care.drain` lowers a stat for seconds the game is open (never below the
  floor); `GameState._process` drains only when the frame is under `FRAME_GAP` (5 s, a longer gap
  is the computer asleep), and `load_game` drains nothing for time closed. `Care.parts` gives the
  `care` boost parts above a buff's line (strictly); `boost_parts` leaves them out while
  `_loading` (time closed) or `_away` (`_without_care(work)` wraps the live sleep catch-ups in
  `_work_jobs` / `_work_automation`), and `load_game` / `_without_care` drop the kept coins and
  luck totals after. `GameState._check_care()` runs after every snack, pat, kitchen meal, load
  and `debug_new_game`, and from `_process` only when `Care.crossed` says a drain tick crossed a
  line (no per-frame allocation): when a buff turns on or off it drops the kept totals of the
  buffs' kinds (coins, luck) and emits `changed`. `pat()` gives mood at most once every
  care.json `pat.every` seconds (`_pat_at`, not saved). `feed()` pays `snack_price()`
  (`Care.snack_price`: snack capsules x `Machine.coin_value`). The bars (`UiTheme.bar(color,
  Care.line(catalog, stat))`, `UiTheme.light_bar`, `HomeTab.show_care`) draw a mark at their own
  buff's line and light up while it's on (`CompactView._process` skips while hidden). There is no passive coin trickle.
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
  unlocked / tutorial_changed while open, placed on the stage's resize; machine globes: the tab shows
  the newest two globes side by side in a `StageHolder`, one `MachineStage` each (`globe`, `hand`,
  `compact`; only the hand one takes input and shows the counter, the one behind shows your pet /
  workers on its lever and their `pet_cranked` capsules; a stage keeps its globe while it stays on
  show, so capsules in flight survive a globe arriving; what a stage draws from is worked out in
  `refresh_state()` on changes, not per frame; only the hand stage holds unlock popups), and a `FixList` of the newest globe's
  repairs in place of "next up"; `MachineTreeView` frames a globe's `view` of the tree with a sign
  per globe to pan, `MachineMini` draws a node's own globe), `BoxesTab` (shop, `PackOpening` for one box, `BoxReveal` grid for many),
  `CollectionTab` (pets: the `Bookcase` with its cushion of `MiniCard`s and a `ShelfPlank` per
  rarity with a `Mound`; a plank opens the `ShelfView` with `PetDetails`; the `RoomPill`; and the
  `BookView`), `AdventuresTab` (adventures:
  `MapView`, the place card, trip cards, and `TrailView` for watching a trip; next door's page
  is drawn by `StreetPage` (night paper, house backs whose windows are the lights, gardens coloured
  in when they're ours); upgrades: `GearView`,
  gear bought with xp, rules in `Gear`, levels in `GameState.gear`, packed onto each trip as
  `RunState.gear`), `ErrandsTab` (jobs: the corkboard; upgrades:
  `ErrandToolsView`, the pegboard of tools bought with coins; rules in `Jobs`, levels in
  `GameState.errand_tools`; tool and box prices are in capsules x `GameState.capsule_value()`
  (`Jobs.tool_cost(tool, have, n, value)`, `GameState.box_price` / static `box_cost`); the kitchen speeds every other job via `GameState.kitchen_bonus()`, a `kitchen` part of `boost("errands")` (its line: `Jobs.faster_words`),
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
`WindowSource.home_rect()` says where the corner panel / full game window is (quiet paws faces it).

`DesktopPet` (the pet out on your windows, in the overlay) owns a `QuietPaws` (scripts/pets: the
brain; reads GameState, `step()` picks the pose NONE / BOXES / MACHINE / HOLD / WAIT and says when
to stand still; listens to `opened_in_background` and `pet_cranked`; never opens or marks
anything seen) and two `PawsView`s (behind and in front of the pet: pile, pack in paws, puff,
tiny machine, sparkles, dust; own colours, and `PawsView.draw_pack` is also the corner panel's
pile). `Settings.paws` (0..2, settings.json) picks how much shows. For tests a `DesktopPet` can run
in stage mode (`stage` = a Control, with a `StageSource` of pretend window rects) inside the game
window: the headless tests do that, and so does the dev-only `DeskStage` (DevDriver `desk on`).
Neither `DesktopPet`, `QuietPaws` nor `PawsView` names an autoload, so the headless tests can load them.
Presents: `Gifts` (scripts/pets/gifts.gd, pure rules, data/gifts.json) moves the clock
`{ next_at, pocket }` on unix time only (`tick`), so open and closed pay the same;
`GameState._tick_gifts` runs every second and once at the end of loading, and only while the boxes
tab is open. `GameState.open_gift` rolls when opened (`Gifts.roll`), grants the boxes of
`newest_box_id()` (the highest box tier in the shop) and a toy like the machine does (`Toys.roll` + `Toys.add`), emits `gifts_changed`.
`QuietPaws` has a `DIG` pose and `worn` (priority hold > dig > wait > stint; `step`'s
`window_edge` says it isn't on the screen's bottom); `DesktopPet.tap()` opens the worn present
instead of a pat (`QuietPaws.popped`), and `PawsView.draw_present` draws the present (also the home
tab's, in theme colours). `PetView.top()` is where the top of the pet's art is (for things on its head), from
`PetLook.top_row()` (worked out from the Image when the picture is built, asked for lazily).
`HomeTab.busy()` holds unlock popups while a present opens (like `MachineTab.busy()`), and
`MachineTab.show_toy` is the toy prize card both the machine and presents use.

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
Save v28 adds the herd (C1), new homes and busy paws (C3; built as v23 and v24 in their lane,
one number at the merge): `collection` is `{ pets (cards), herd, active, next_id, seen, fallen
(palettes), fallen_n, stand_next, herd_ever }`, errands are `{ crew (card uids), herd, fill }`,
`automation.wherd` holds workers from the herd (a party leader stays a uid slot, a stand-in's uid for
a herd pet), and top-level `room`. Old collections load as they are (stars keep their palettes,
the first pet with each part is marked); `load_game` ends with `collection.refold()`, which turns
old crews and workers of uids into counts through `pets_folded`. A save from before v28 that already
has more plain pets than the first room holds gets room for them plus data/herd.json
`room.old_save_margin` (`Herd.room_level_for`), so box openings and box jobs keep going.
`Collection.herd_changed(keys)` says which counts changed; the pets tab rebuilds once a frame at
most and leaves an open shelf of another rarity alone.
Who's resting is worked out once (`GameState._resting`: cards, herd counts minus errands, workers,
stand-ins away or leading) until `_rest_changed()`.
It also adds new homes: top-level `new_homes` `{ points, by_hand, sorted, room_was_full,
rule { on, below, to, keep }, today { day, n } }` (`NewHomes`, data/new_homes.json), `jobs[id].join`
and `automation.wjoin` ("new pets join here"); `jobs_auto` is gone (an older save with it on gets every
shared-out errand's switch on (not the kitchen or scouting); an older save whose room is full has `room_was_full`, so the stall is there).
`Collection.add(pets, sorter)` asks the sorter about each pet after the book counts it ("homes": it
never joins, a star); `Collection.leave(counts, uids)` takes pets off for good (a star each, the
stand-in looks of a count leaving never come back) and emits `pets_left(n)` (the night sky redraws).
`GameState.send_home(rarity, n)` / `homes_pick` (the stall), `_sorter` / `_sort_pet` (the rule, box
openings only: `open_boxes`, the machine's pet box), `_place_new(uids)` (busy paws, replaces
`jobs_auto`; the rule's work pets go to every open errand when nothing takes them), `_room_hit()`
(first full room: unlock `new_homes`). Unlock entries can be `"quiet": true` (no popup card) and earn
`room: "full"` / `homes_by_hand`. UI: `NewHomesStall`, `SortingCard`, the pets page's side column in
`CollectionTab`, `Bookcase.stall_on` / `picked` (tap picks, tap again opens), `ShelfPlank` picked
border and "sorted today" tag.
Save v29 adds `gifts` ({ next_at, pocket }; nothing to convert: older saves with the boxes tab
open start the present clock on load, the first 3 h later; built as v25 in its lane).
Save v30 adds machine globes (built as v24 in its lane): `machine.globes` (globe ids you have; the first is always there,
unknown ids dropped) and `machine.greeted` (the machine tab showed it arriving). `load_game` gives a
save without them just the first globe for both (no `_migrate` step needed). On every load a save with a globe's find but not the globe gets it. The globe
you pull is derived (`Machine.hand`: the newest globe whose `works` repair is fixed), never saved.
Save v31 (built as v24 in its lane) counts visits per place (`visits`: trips welcomed back with somebody home; old saves get
one per place in `visited`) and runs save `ours`. Whether a place is ours is never saved: `Ours`
(scripts/adventure/ours.gd) works it out from the visits against its `lights` (next door) or its
page's `ours_after` (the backyard), or `ours_at_start`, and only while next door is open. An ours
run meets the place through `AdventureRunner.place` (danger and loot scaled, worked out once per
run into the unsaved `RunState.met`; `run_gap` reads the catalog, ours doesn't change the walk) and
never draws `"local": true` events. A place that just became ours goes into
`GameState.unshown_ours` (not saved); MapView takes it from there when it's on the page you're
looking at (`GameState.ours_shown`), keeps the colouring-in timing itself (`_colouring`) and hands
`grow` to `StreetPage.draw` / its own doodles, so the drawing never changes state.
Unlocks with `"earn": { "called": true }` are opened only by code: `GameState.open_page(page_id)`
fires the page's unlock (popup, announce) through the same `_open_entry` as `check_unlocks`, and
emits `page_opened`; `UnlockRules.stale` never closes them.

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
  and settings) on a hidden Xvfb screen of its own (a free display number, software rendering;
  `--show` plays on the real desktop), prints the log and saves screenshots. Steps are listed
  in `DevDriver`; `expect fits` checks the full game fits its window. Test saves: `tests/saves/`.
  `DESK_PETS_LANE=<name>` adds a suffix to the profile (`play-<flow>-<name>`) so several
  worktrees (the lanes in ~/projects/desk-pets-lanes) can play flows at once. Flows with big
  `pets` / `herd` steps send `stickers off` after `view full`, or the book's sticker popup covers
  the later shots.
- A headless script check must use a profile: `godot --headless --quit-after 30 -- --profile=check`
  (without one it loads and saves the real save).
- `godot -s tests/look_sheet.gd -- out.png` - renders every part and finish into one picture.
- Debug launch flags (`DevArgs`): `godot . -- --expanded --tab=collection --book --open=starter:10`,
  and `--open=starter:1 --force=mythic --autoplay` to watch a reveal at any rarity hands-free.
- `python3 tools/film.py <out_dir> <name> "<godot args>" 1.5 3 5` - launches the game on Hyprland
  and screenshots its window at those times (combine with `--autoplay` to check animations).
