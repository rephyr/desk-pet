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
scripts/dungeon/     the old well's dungeon (Dungeon): floors, power, a whole run worked out at once, pay; the sewing room (Sewing): rooms, chalk locks, keep lines; the wisps perks on the well wall (Perks); pure rules, see data/dungeon.json, data/sewing.json, data/perks.json
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
  part per edition working now). A new source (book, knacks, kitchen) appends its own `X.parts(...)`
  there, and calls `_boosts_changed()` whenever its state changes.
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
  `knacks_changed` (the pets tab marks itself dirty, so an open shelf redraws its `MiniCard` corner
  badges, only when the open kinds differ from its last draw). active_changed only clears boosts (your active pet never works). Other pets:
  `_pet_speed` (errand speed x `knack_own(.., "errands")`, used to pick who goes on and who comes
  off), `workers_speed` x `knack_own(.., "automation")` (cards; herd counts in crews and on machines work
  at `Herd.template` speed: `knack_own` is 1.0 for a pet with no uid, so the templates never share
  a cache slot). The adventures tab keeps
  `trip_knacks(pets)` by a key of place, picks, gear, active pet, trip boosts and `knack_version`,
  so a big swarm isn't walked on every click. Trips pack `RunState.knacks` when they set off
  (`GameState.trip_knacks`: boost x party share for trip, tough, safe, spots, finds, pickups,
  treats; loot is the party share only), read with `run.knack(kind)` (1.0 when missing):
  `AdventureRunner.walk_of` (boots then / trip), hurt and injured counts / tough, lost / safe,
  `Intel.roll(.., x)` lead chance x spots, trail pickups, treat zoom, extra bits and parts in
  `_boost_trip_loot`.

- Buttons (F1/F2) grow knacks: `Knacks.of` / `sum_in` / `parts` multiply a part's size by
  `Plushie.knack_x(buttons)` (1 + knack_per_button x buttons; x1 with none), read off `Pet.buttons`.
  Buttons are sewn through `GameState._plushie_sewn` (pet_changed, so `_knacks_changed()` runs).

## The plushie machine

- `Plushie` (scripts/machine/plushie.gd, static, pure) holds the rules over a plain state dict
  (`GameState.plushie`, saved as it is): `{ keeper, hopper: [pet dicts], nudges, bought: { nudge,
  hold }, try: { fed, spins, spins_max, reels: [5 x { strip, held, hold, banked, fresh, before,
  was_hold }], wild: {} or { slot, strip } } }`. `spin(catalog, state, keeper, rng, forced)` banks
  unheld reels, lands the live ones (`forced`: slot or "wild" -> symbol, the dev driver's `land`),
  returns `{ sewn, landed, puffed, wisps, wild }`; `next_pet`, `bank`, `can_hold` /
  `toggle_hold`, `nudge`, `wild_available`, `price` / `buy` (capped at shop.max), `wild_step`,
  `odds_for`, `puff`, `clean` (from a save). `set_keeper(catalog, state, pet)` banks anything still
  held onto the new keeper and keeps `banked` (only `next_pet` clears it), so a swap there and back
  never spins a banked reel again. The UI asks `can_hold` / `wild_available`, never re-derives them.
- `GameState.plushie_*` are thin wrappers: `plushie_keepers()` (sorted, for ‹ ›) / `plushie_keeper()`
  (read-only: null while the keeper is away; only when none is picked or it's gone for good does
  the first on the list take over), `plushie_can_swap()` (a cheap count), `plushie_swap`,
  `plushie_feed_herd(rarity)` (a stand-in from a resting count, else one off a job: the pet is
  found first, then `_herd_off_places` takes it off and returns how many it took; `collection.remove`
  so it's a star), `plushie_cards()` / `plushie_has_cards()` / `plushie_feed_card(uid)`, `plushie_spin()` (next pet when
  `Plushie.needs_next`), `plushie_bank / hold / nudge / buy / wild_step / price / odds`. Signals
  `plushie_changed` and `plushie_spun(result)` (the UI plays the landings from it). The keeper is in
  `_busy_uids()` while the machine is open, so it never folds into the herd mid-try, and
  `sendable_pets()` leaves it out, so it never goes on an adventure.
- Wisps: `GameState.wisps` (top level in the save), `grant_wisps(n)` and `grant({ "wisps": n })`.
  `UiTheme.WISP` (themes.json `wisp` in all 5 themes), doodles `wisp`, `button`, `reel_blank`,
  `reel_crack`.
- The one opening hook: data/unlocks.json `plushie` (earn `find: plushie_machine`, opens
  `feature:plushie` + `tab:inventory`, `button_gift: 1` -> `GameState._gift_buttons`). The find
  has `given_by` (the sewing room, E3): E3 only has to `grant({ "find:plushie_machine": 1 })`.
- Grafting keeps buttons: bag keys are `slot:id` or `slot:id@n` (`Grafting.key`, `split_key`,
  `valid_key`); a part that comes off goes back with the slot's buttons, sewing an `@n` part on sets
  them. `InventoryTab` reads keys through `split_key` and draws the buttons on the sticker.
- UI: `PlushieMachine` (scripts/ui/plushie_machine.gd, the workbench's `plushie`): the cabinet
  (Hopper, Bulbs, ReelView x5 + the wild one, Marks, odds, bank / hold, Lever, the spin button) and
  the side card (keeper, hopper rows or the card picker, wisps, the shop); effects on an Fx layer.
  The hopper rows are rebuilt only when the rarities shown change (herd / cards / jobs / plushie
  signals mark them; counts update in place); the picker shows 20 card pets a page (‹ n/m ›).
  `busy()` while reels roll (the dev driver waits on it). `KnackBadge.draw_buttons` puts the buttons
  on a badge's rim (the details and the shelf cards' corners).

## Pets

- `Pet` is plain data (parts, finish, traits, stats, rarity) with `to_dict` / `from_dict`.
- `PetRoller` rolls pets like card packs: the rarity is rolled once with the box odds, one
  "signature" part gets that rarity, the others roll at or below it. The finish is a separate
  roll. So the odds shown on a box are exactly what you get (checked by `tests/test_core.gd`).
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
- `PetLook` is the placeholder art (pixel maps in code). Real art replaces `PetLook` only;
  `PetView` (draws a pet, blinking, squash, finish shader) and everything above stay the same.
- Finish effects are one shader, `shaders/finish.gdshader`; `finishes.json` picks the mode.

## Screens

`home.gd` holds two layers inside one window:

- `CompactView` - the small idle panel (active pet opening packs, needs, feed / pat / let out).
- `ExpandedView` - the full game: the `Spine` of tabs and the page. Tabs: `HomeTab` (the pet's
  room), `MachineTab` (the capsule machine: `MachineStage` draws it and runs the lever, `Machine` in
  scripts/machine has its rules, `GameState.pull_lever()` pays out; a pet box out of a capsule is opened right there with a
  `PackOpening`), `BoxesTab` (shop, `PackOpening` for one box, `BoxReveal` grid for many),
  `CollectionTab` (pets: the `Bookcase` with its cushion of `MiniCard`s and a `ShelfPlank` per
  rarity with a `Mound`; a plank opens the `ShelfView` with `PetDetails`; the `RoomPill`; and the
  `BookView`), `AdventuresTab` (adventures:
  `MapView`, the place card, trip cards, and `TrailView` for watching a trip; upgrades: `GearView`,
  gear bought with xp, rules in `Gear`, levels in `GameState.gear`, packed onto each trip as
  `RunState.gear`), `ErrandsTab` (jobs: the corkboard; upgrades:
  `ErrandToolsView`, the pegboard of tools bought with coins; rules in `Jobs`, levels in
  `GameState.errand_tools`), `AutomationTab` (a card per job your pet can do, `JobScene` draws each one; rules in
  `Automation`, state in `GameState.automation`: what's taught, the one job it does, tools, the party; the workers page:
  `WorkerCard` / `WorkerSpot`, `GameState.put_workers` / `buy_spots` / `teach_others`); the adventures tab's
  dungeon page is `DungeonView` (`WellColumn` draws the well's cross-section, `FrontRow` the front
  row; rules in `Dungeon`, state in `GameState.dungeon` and `GameState.wisps`; the sewing room: `SewDoor` on
  the column, `SewingRoom` slid in beside it with `ChalkMark`s, rules in `Sewing`), `InventoryTab`
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
Save v23 adds the herd: `collection` is `{ pets (cards), herd, active, next_id, seen, fallen
(palettes), fallen_n, stand_next, herd_ever }`, errands are `{ crew (card uids), herd, fill }`,
`automation.wherd` holds workers from the herd (a party leader stays a uid slot, a stand-in's uid for
a herd pet), and top-level `room`. Old collections load as they are (stars keep their palettes,
the first pet with each part is marked); `load_game` ends with `collection.refold()`, which turns
old crews and workers of uids into counts through `pets_folded`. A save from before v23 that already
has more plain pets than the first room holds gets room for them plus data/herd.json
`room.old_save_margin` (`Herd.room_level_for`), so box openings and box jobs keep going.
`Collection.herd_changed(keys)` says which counts changed; the pets tab rebuilds once a frame at
most and leaves an open shelf of another rarity alone.
Save v25 adds the plushie machine: top-level `plushie` (see `Plushie.fresh`) and `wisps`, optional
`buttons` (slot -> 1..5) on pet dicts, and bag keys `slot:id@n`. Older saves load an empty machine
and 0 wisps (nothing to move); `Plushie.clean` and `Pet.from_dict` fix up odd values.
Who's resting is worked out once (`GameState._resting`: cards, herd counts minus errands, workers,
stand-ins away or leading, and the dungeon's army) until `_rest_changed()`.
Save v24 adds the dungeon: `wisps` and `dungeon` = `{ deep, bands, target, home_at, first, cards
(uids), herd ({ rarity: n } picks), run ({} or { at, floors: [{ f, cleared, lost_cards, lost_herd,
pay }], why, turned, cards, herd ({ count key: n }), sent, target }), last, firsts, entrance }`.
Army cards count as busy (`GameState._out()` = away + the army), the army's herd picks are spread
over counts after everyone else's (`_army_herd`). A run is simulated when it sets off; the 1-second
tick finishes it (`_finish_dungeon_run`: `Collection.remove` / `lose_plain` add stars). The v24
migration turns an old save's open cellar/below places into bands, drops rumours about them and moves
parties going there to the well. Band places have `"band"` in data/adventures.json and are never
open (`location_open`); retired rumours are never heard (`Rumours.hearable`).
Save v26 adds new homes (C3): top-level `new_homes` `{ points, by_hand, sorted, room_was_full,
rule { on, below, to, keep }, today { day, n } }` (`NewHomes`, data/new_homes.json), `jobs[id].join`
and `automation.wjoin` ("new pets join here"); `jobs_auto` is gone (an older save with it on gets every
open errand's switch on; an older save whose room is full has `room_was_full`, so the stall is there).
`Collection.add(pets, sorter)` asks the sorter about each pet after the book counts it ("homes": it
never joins, a star); `Collection.leave(counts, uids)` takes pets off for good (a star each, the
stand-in looks of a count leaving never come back) and emits `pets_left(n)` (the night sky redraws).
`GameState.send_home(rarity, n)` / `homes_pick` (the stall), `_sorter` / `_sort_pet` (the rule, box
openings only: `open_boxes`, the machine's pet box), `_place_new(uids)` (busy paws, replaces
`jobs_auto`; the rule's work pets go to every open errand when nothing takes them), `_room_hit()`
(first full room: unlock `new_homes`). Unlock entries can be `"quiet": true` (no popup card) and earn
`room: "full"` / `homes_by_hand`. UI: `NewHomesStall`, `SortingCard`, the pets page's side column in
`CollectionTab`, `Bookcase.stall_on` / `picked` (tap picks, tap again opens), `ShelfPlank` picked
border and "sorted today" tag. `GameState.homes_rule_changed` fires when the rule changes: the
sorting card rebuilds its steppers on it (and on new pets), the "sorted today" numbers on the card
and the planks update in place on `changed` (the pets page never rebuilds for them).
`Collection.finish_seen(id)` is what the keep stepper offers from; `set_finish` (the dev `dress`
step) keeps the room count right; `_herd_to_stars` is the one "a count's pets become stars" path
(`leave`, `lose_plain`).
One place at a time (the dungeon, the plushie machine and new homes together): `wisps` is one field
(the dungeon pays through `grant_wisps`, the plushie machine spends). `plushie_keeper_uid()` is left
out of `sendable_pets`, `army_choices` / `army_best` / `set_army_card`; `plushie_keepers` skips
`_out()` (away + the army). `_busy_uids` = `_out()` + pinned + party leaders + the keeper, which
`homes_pick` skips; its working count also leaves out `army_herd_keys()`, so the stall never takes the
army's herd pets. Pets with buttons are always cards (`Collection.always_card`); the sorting rule
only sees new pets from boxes.

Save v27 adds the sewing room (E3): top-level `sewing` `{ cleared }` (`Sewing`, data/sewing.json),
`new_homes.rule.lines` ([keep line picks, "" = nothing]) and `new_homes.kept` ({ pick: [uids, oldest
first] }); a room run is the dungeon's `run` with `room`, `door`, `seconds` (so its pets are busy through
`_out()` like any run) and `dungeon.last.room`. Nothing moves; a v26 save already past floor 20 gets
the key (`finds.little_key`). `Dungeon._fight` is the one fight (a well floor, or a room through
`Dungeon.simulate_room`); `run_seconds` / `run_floor` read a room run's own time and door.
`GameState.send_to_room(i)` / `_finish_room_run` / `sew_can_go` / `sew_marks` / `sew_front` (the army's
best front_row cards) / `sew_hint(mark)` (like `bit_hint`) / `debug_sewn(n)`; unlock earn key `sewing`
(rooms cleared). Keep lines: `keep_lines()` / `set_keep_line(i, pick)` / `kept_count`; `_sorter` is valid
when the rule is on OR a keep line picks something, `_sort_pet` asks `_keep_new` first;
`Collection.keep_uids` (rebuilt from `homes.kept` by `_keep_lines_changed`) counts in `always_card`, so
kept pets never fold and the stall never takes them.

Save v28 adds the wisps perk tree (renumber at the lane merge): top-level `perks` `{ perk id: level }`
(`Perks`, data/perks.json; only levels > 0, links clamped to their max, tips any level). The
migration moves `dungeon.entrance` (a level) into `perks.entrance`; `Dungeon.fresh/clean` no longer
keep it. Count links ADD their steps to a base: `Perks.count_base` (entrance / front_row from data/dungeon.json
`entrance.start` / `front_row`, the rest 0), `Perks.count` / `count_at`, `Perks.card_value` (the nail
card's whole number); `Dungeon.entrance(catalog, level)` = `count_at("entrance", level)`. An army for the rules can
carry `front_n` / `front_x` / `behind_x` / `band_x` ({ rope | doors | stairs | room: x }), orders
`pay_x`; `GameState._army_rules` fills them from `boost("front" | "herd_power" | "cellar" | "stairs")`,
`send_army` / `send_to_room` pass `pay_x = boost("lanterns")`. `boost_parts` appends `Perks.parts`
(source "perks"). Counts: `front_row_size()` (army_best, sew_front, FrontRow), `perk_holds()` /
`perk_nudges()` (passed to `Plushie.holds_max / can_hold / toggle_hold / next_pet` as extras; the shop's
hold price still counts bought holds only), `perk_away_hours()` (`_army_while_away` on load: finishes
the run that was out and sends the same army again back to back from the save time, up to
perks.json `away_runs_max` runs, each quiet (`send_army(true)` / `_finish_dungeon_run(true)`: no
signals, save, refold or unlock check; `_home_again()` does those once after), nothing for a save
with no `saved_at`; wisps into `idle_log.wisps` and `dungeon_news`). `boost("pets")` speeds box opening
(`_open_in_background`, `PackJob`'s rest, the workers' box tables). `GameState.perks_shown()` /
`perk_available` / `perk_price` / `buy_perk` / `debug_perk`, the pages rebuild on
`dungeon_changed`. UI: `PerkNail` (a Button; `PerkNail.texture(thing, look, px)` renders the SVG
things) placed by `WellColumn` (lane x 40, `nail_at`, `_thread`, tips under the last floor drawn,
`nail_pressed(id)`); `DungeonView.pick_nail(id)` / `_nail_card` in the side column. The well panel
is 236 wide (the column's middle at 0.55), the page's gaps 10, FrontRow's gap 3, the picker's 5.

## Testing

- `godot --headless -s tests/test_core.gd` - data sanity, box odds over 100k rolls, save round
  trip, adventures, errands.
- `godot --headless -s tools/balance.gd` - what every place pays per minute, and errands for
  crews of 1 to 1000.
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
