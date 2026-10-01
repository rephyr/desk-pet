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
  `best` build display rows (the UI only; `row` is one part's row on a pet of a finish with n
  buttons, which the workbench's bag tiles and sewing table use). Totals (`total`, `parts`, `own`, `party_all`) take the
  lean path: `counting(kind)` makes a lookup table once (slot -> part id -> size before the
  finish, only parts whose knack kind counts and is open), `sum_in` / `own_in` then add a pet up
  with no rows or strings (about 2.5 us a pet a kind). `GameState.boost_parts` appends
  `Knacks.parts(catalog, collection.active(), kind, knack_gate)`. `knack_gate(gate)` answers
  "adventures", "machine:<node>" and unlock ids. `GameState.knack_own(pet, kind)` keeps each
  card pet's own multiplier (its knacks in full: data "own" 1.0) by uid (`_knack_own`, tables in `_knack_steps`). `_knacks_changed()` (a pet's
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
  Box tiers: `PetRoller.roll_box` rolls a box's `pets` [min, max]; parts come from
  `Catalog.parts_in(slot, tier, box)` (a part with `from` only rolls from that shop box or a later
  one; `Rewards.roll_part` does the same with a place's box). `BoxShop` (scripts/pets) holds the
  tier rules tests can reach: `open_tiers` (a tier is in the shop once its map page is open),
  `split_open` (workers open N boxes, not N pets), `best_first`, and `fix_retired` (lucky boxes).
  `Catalog.parts_in` and `box_rank` are cached (catalog data never changes after loading);
  box workers open at most `GameState.WORKER_BOXES_MAX` boxes at once.
  With the room (the herd), `GameState.open_boxes` opens box by box while the room has space for
  one more pet: a box's pets all come in (a sunset box can take the room over by a pet or two), the
  rest wait on the pile; callers count what opened from the pile, not from `count`.
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
- `Wish` (scripts/pets/wish.gd, pure rules, data/wish.json) is the wishing jar: steps, where a
  jar is (`where`), `add(catalog, state, key, n, palettes)`, `weights` (book key -> x for every
  look with a full step). `GameState.wish` = `{ on, jars: { book key: { sent, dots } } }`,
  `set_wish`, `wish_shelves` (rarity -> pets that may go and the next one's face, from
  `spare_shelves()` like the edge), `send_to_wish` (`_take_spare`: the shared rule, a star each), signal `wish_changed(step)`. `WishJarCard` looks over the
  shelves at most once a second while pets stream in (box tables) and changes chip counts and faces
  in place. `PetRoller.wish` takes the weights (set on load, new game and every full step): with it
  empty the roller runs exactly as before; with it, `_pick_part` and `_signature_slot` pick weighted
  inside the tier already rolled. Every box goes through `GameState._roller`, so your rips, your
  pet's opening, box tables and the machine's pet box all follow it. UI: `WishJarCard`
  (scripts/ui/wish_jar.gd, the jar drawn in code, `JarArt`) beside `BookView` in `narrow` mode
  (`CollectionTab._show_jar`); earned by the unlock `wish` (earn key `others`: a job taught to the
  other pets).
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
  rarity with a `Mound`; a plank opens the `ShelfView` with `PetDetails`; the `RoomPill`, which opens the `HouseCard` (the
  room steps: `HouseDrawing` draws the cut-away house as an SVG made in code, pets pasted in, split
  only where a later shape covers a pet; the card redraws it only when the steps or looks change); and the
  `BookView`), `AdventuresTab` (adventures:
  `MapView`, the place card, trip cards, and `TrailView` for watching a trip; next door's page
  is drawn by `StreetPage` (night paper, house backs whose windows are the lights, gardens coloured
  in when they're ours); past the edge: `MapView` draws the torn paper, the tucked page's scribbles
  and the signpost, `EdgeCard` sends pets, rules in `Edge`, state in `GameState.edge`; upgrades: `GearView`,
  gear bought with xp, rules in `Gear`, levels in `GameState.gear`, packed onto each trip as
  `RunState.gear`), `ErrandsTab` (jobs: the corkboard; upgrades:
  `ErrandToolsView`, the pegboard of tools bought with coins; rules in `Jobs`, levels in
  `GameState.errand_tools`; tool, box and room prices are in capsules x `GameState.capsule_value()`
  (`Jobs.tool_cost(tool, have, n, value)`, `GameState.box_price` / static `box_cost`,
  `Herd.room_cost(catalog, level, value)` via `GameState.room_price()`; a squeeze-in room step costs
  wisps instead, `Herd.room_currency`); the kitchen speeds every other job via `GameState.kitchen_bonus()`, a `kitchen` part of `boost("errands")` (its line: `Jobs.faster_words`),
  scouting fills `GameState.scout_notes` and `send_on_adventure` packs one onto `RunState.scout`,
  read by `Intel.roll` and `AdventureRunner`), `AutomationTab` (a card per job your pet can do, `JobScene` draws each one; rules in
  `Automation`, state in `GameState.automation`: what's taught, the one job it does, tools, the party; the workers page:
  `WorkerCard` / `WorkerSpot`, `GameState.put_workers` / `buy_spots` / `teach_others`; the whistle page: `Clipboard`,
  `TodoRow`, `Tick`, `TinyCrowd`, rules in `Automation.whistle_plan` / `exist` / `checks`, applied by
  `GameState._whistle_checks`, caps via `GameState.spot_room`; parties only go by themselves to
  `GameState.party_places()`, no dungeons and no risky place until it's ours, which also sets the
  parties cap; the school page: `SchoolView`, rules in
  `School`, state in `GameState.school`, `GameState.school_boost()` is the `school` source of the
  automation and errands boosts; `HerdPicker` is the shelves + 1 / 10 / 100 / all the edge and the
  school share; pages are strings: `pet`, `workers`, `whistle`, `school`); the adventures tab's
  dungeon page is `DungeonView` (`WellColumn` draws the well's cross-section, `FrontRow` the front
  row; rules in `Dungeon`, state in `GameState.dungeon` and `GameState.wisps`; the sewing room: `SewDoor` on
  the column; `DungeonView.door_opened` has the adventures tab show `SewingPage` in its place:
  the room strip, seats, the pet picker; seats in `GameState.sew_seats` (not saved), `sew_seat` /
  `sew_unseat` / `sew_party` / `sew_last`; rules in `Sewing`. The old `SewingRoom` pane slid in
  beside the column is no longer reachable and can go once the dungeon page redo is merged), `InventoryTab`
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

Your pet talks through `PetBubble` (two rows at most). Two bits of news at once go through
`PetBubble.show_lines()`, one bubble after the other, never joined into one long line that gets
cut off. On the map, `MapView._inside()` keeps names, bit lines and place notes on the page, and
the walking tag steps aside from a place's note.

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
stand-ins away or leading, and the dungeon's army) until `_rest_changed()`.
**Who may go (one rule, save v41):** `GameState.spare_pick(rarity, n)` picks the pets of a rarity
that may leave or go somewhere, for every place that takes pets by the shelf: the new homes stall,
the edge, the school, the wishing jar, workshop helpers, held landings and the army's herd. Every
resting pet goes before any working one (then they come off their errands and machines,
`_herd_off_places`), the plainest finish first, counts before the oldest cards. Only finishes below
the sorting card's keep line (`keep_line()` = `homes.rule.keep`, `may_go_finish()`; it works with the
rule on or off), and never `Collection.kept()` pets (favourites, your active pet, a new part, buttons,
a keep line) or busy ones (away, pinned pulls, party leaders, the army, the plushie keeper).
`_take_spare(rarity, n, keep, star)` takes them (`Collection.leave`; `star` false = they stay on
somewhere) and returns `{ n, counts, palettes }`. `spare_shelves()` (rarity -> `{ n, working }`, for
pickers that ask every frame) is cached until `_spare_changed()` and at most a second. The army's
front row can take cards off errands too (`_working_cards`, `_off_work`). `join_up_to` (save field):
"new pets join here" takes new pets up to that rarity only (`_place_new`; the errands tab's "up to"
stepper).
It also adds new homes: top-level `new_homes` `{ points, by_hand, sorted, room_was_full,
rule { on, below, to, keep }, today { day, n } }` (`NewHomes`, data/new_homes.json), `jobs[id].join`
and `automation.wjoin` ("new pets join here"); `jobs_auto` is gone (an older save with it on gets every
shared-out errand's switch on (not the kitchen or scouting); an older save whose room is full has `room_was_full`, so the stall is there).
`Collection.add(pets, sorter)` asks the sorter about each pet after the book counts it ("homes": it
never joins, a star); `Collection.leave(counts, uids)` takes pets off for good (a star each, the
stand-in looks of a count leaving never come back) and emits `pets_left(n)` (the night sky redraws).
`GameState.send_home(rarity, n)` / `spare_pick` (the stall), `_sorter` / `_sort_pet` (the rule, box
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
one per place in `visited`) and runs save `ours`. The save also counts pets sent per place (`sent`, every party added
up, no version bump: a save without it starts from its visits plus the parties still out); an
event with `after_sent` waits for that many (the rope at the well). Whether a place is ours is never saved: `Ours`
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
Save v32 (C2, built as v24 in its lane) adds `edge` (`{ page, sent, ever, marks }`, see `Edge`) and
`school` (`{ seated: { count key: n }, classes: [{ size, step, faces }] }`, see `School`); older saves
start with fresh ones (`Edge.clean`, `School.clean`), and a class with more pets than seats gives
the rest back to the herd (`School.trim`). A page whose `need` dropped below a save's `sent` opens
on load (the rest carry on to the next page); `_init` runs `check_unlocks` and `_open_edge_pages`
deferred after every load, so an update's new unlocks a save has already earned open (with their
popups) right away. A full page past the edge opens its map page with `GameState.open_page` (next
door's unlock is `called`). The school's boost is cached (`school_changed_boost()` after the bell,
a load, a new game; it resets the kept boosts) and is the `school` part of `boost("automation")`
and `boost("errands")` (on the receipt as "the little school"). Teacher and desk faces are
`GameState.school_face(key, n)` = stand-in number `-1 - n`: live stand-ins count up from 0, so
they never share a look or a cached Pet. Pets past the edge and in the school are off the herd
(`Collection.take_plain`, stand-in numbers skip past them); pets past the edge get stars from
`Collection.add_stars(palettes, n)` (a few colours kept, the rest counted; `stars_added` redraws
the sky). Teachers stay on, so the bell adds no stars. The sorting rule's `to` can be `school`
(`GameState.rule_destinations()`, once the school is open): `_sort_pet` seats the pet while there
are seats (else it stays) and `Collection.add` drops it without a star.
Save v33 (E1, built as v24 in its lane) adds the dungeon: `wisps` and `dungeon` = `{ deep, bands, target, home_at, first, cards
(uids), herd ({ rarity: n } picks), run ({} or { at, floors: [{ f, cleared, lost_cards, lost_herd,
pay }], why, turned, cards, herd ({ count key: n }), sent, target }), last, firsts, entrance }`.
Army cards count as busy (`GameState._out()` = away + the army), the army's herd picks are spread
over counts after everyone else's (`_army_herd`). A run is simulated when it sets off; the 1-second
tick finishes it (`_finish_dungeon_run`: `Collection.remove` / `lose_plain` add stars). The v33
migration turns an old save's open cellar/below places into bands, drops rumours about them and moves
parties going there to the well. Band places have `"band"` in data/adventures.json and are never
open (`location_open`); retired rumours are never heard (`Rumours.hearable`).
Save v34 (F1/F2, built as v24 in its lane) adds the plushie machine: top-level `plushie` (see
`Plushie.fresh`), optional `buttons` (slot -> 1..5) on pet dicts, and bag keys `slot:id@n`. Older
saves load an empty machine (nothing to move); `Plushie.clean` and `Pet.from_dict` fix up odd values.
Wisps are one purse (`GameState.wisps`, saved since v33): the dungeon's floors and the machine's
misses both pay in through `grant_wisps` (`grant({ "wisps": n })` too). The keeper stays home: not
sendable, never in the army (`army_choices`, `set_army_card`), and an army pet can't be the keeper
(`plushie_keepers` skips `_out()`).
`GameState.homes_rule_changed` fires when the sorting rule changes: the sorting card rebuilds its
steppers on it (and on new pets, or a new place to send them), the "sorted today" numbers on the card
and the planks update in place on `changed` (the pets page never rebuilds for them).
`Collection.finish_seen(id)` is what the keep stepper offers from; `set_finish` (the dev `dress`
step) keeps the room count right; `_herd_to_stars` is the one "a count's pets become stars" path
(`leave`, `lose_plain`).

Save v35 (E3, built as v27 in the sewing lane) adds the sewing room: top-level `sewing` `{ cleared }` (`Sewing`, data/sewing.json),
`new_homes.rule.lines` ([keep line picks, "" = nothing]) and `new_homes.kept` ({ pick: [uids, oldest
first] }); a room run is the dungeon's `run` with `room`, `door`, `seconds` (so its pets are busy through
`_out()` like any run) and `dungeon.last.room`. Nothing moves; an older save already past floor 20 gets
the key (`finds.little_key`). `Dungeon._fight` is the one fight (a well floor, or a room through
`Dungeon.simulate_room`); `run_seconds` / `run_floor` read a room run's own time and door.
`GameState.send_to_room(i)` / `_finish_room_run` / `sew_can_go` / `sew_marks` / `sew_front` (the army's
best front_row cards) / `sew_hint(mark)` (like `bit_hint`) / `debug_sewn(n)`; unlock earn key `sewing`
(rooms cleared). Keep lines: `keep_lines()` / `set_keep_line(i, pick)` / `kept_count`; `_sorter` is valid
when the rule is on OR a keep line picks something, `_sort_pet` asks `_keep_new` first;
`Collection.keep_uids` (rebuilt from `homes.kept` by `_keep_lines_changed`) counts in `always_card`, so
kept pets never fold and the stall never takes them.

Save v36 (built as v28 in the sewing lane) adds the wisps perk tree: top-level `perks` `{ perk id: level }`
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

Save v37 (built as v29 in the sewing lane) adds held landings: `dungeon.held` `{ "10": { count key: n } }`
and `dungeon.start` (0 or a fully held landing). `Dungeon.hold_every / hold_need / hold_what / held_n /
is_held / hold_spots / starts / held_landings / kind_at / hold_int` (data/dungeon.json `hold`: need,
faces, card_faces, looks...); a fully held guard landing has no guard in the rules either
(`strength(catalog, f, held)`, `simulate` takes `orders.held`, `floor_words` uses them); `Dungeon.clean` drops landings that aren't
every 10th, clamps each crowd to its need and puts `start` back to 0 unless it's in `starts()`, the
target at least start + 1. `Dungeon.simulate` takes `orders.start`: the loop begins at start + 1, so
skipped floors are never in `floors` (no pay, no losses); a run keeps `start`, and `run_seconds` /
`run_floor` count only walked floors (the army is drawn from the landing). `GameState.hold_spots()`,
`hold_room(f)` (what it still needs, never below 0), `hold_can_go(f, rarity)` (`spare_pick`, capped at
`hold_room`; the dungeon page keys its rebuilds on it, so a growing herd doesn't rebuild it), `send_holders(f, rarity, n)` (off
places like `send_home`, `Collection.leave(counts, uids, false)`: no star, no `pets_left`, their
stand-in looks go), `hold_faces(f, n)` (stand-in Pets for the crowd), `set_start(f)` (checks `starts()`, clamps the target, saves; `set_order("start", ±1)` uses it);
`send_army` passes the start (so the music box and your pet leading the army start there too);
`_finish_dungeon_run` counts a run from a landing as at least that deep and gives firsts only for
walked floors. `Mound` takes Pets as faces too, and mirrors flipped sprites with a transform (a
negative-width rect drew them a sprite's width to the right). UI: `HoldSpot` (a Button with a custom
`_has_point`: the crowd and the pill) placed by `WellColumn._place_holds` (`hold_pressed(f)`,
`set_hold_picked`, `hold_spot(f)`); `DungeonView.pick_hold(f)` / `_hold_card` (its shelf list keeps its scroll across rebuilds) /
`hold_pick` / `hold_list` (flows) and
the orders' start line.

Save v38 (built as v26 in the wish lane) adds `wish` (the wishing jar; older saves start with
nothing wished for, `Wish.clean` drops unknown looks and clamps jars to 8,800).
Save v39 (built as v27 in the workshop lane) adds the shed workshop (F3): top-level `workshop` `{ pinned: [ids, one per spot, "" when
empty], prog: { id: { sent, qual } }, built: [ids], helpers, vane: { "place:event": option } }`
(`Workshop` in scripts/idle, pure rules: `fresh`, `clean`, `useful`, `take`, `build` / `finish`,
`vane_pick`; data/workshop.json); older saves get `Workshop.fresh` (the first 3 pinned) from
`Workshop.clean` in `load_game` (no migration step). Toys'
`playing` entries gain `play` (the play length id, `Toys.play`) and `again` (default true; false
after a tap on the playing toy, `Toys.flip_again` / `GameState.toy_again`), so `Toys.ending` can
hand them again; `Toys.mend` is the sewing basket. Unlock earn key `ours: <place>` (`GameState._earned`,
`is_ours`); unlock `workshop` opens `feature:workshop` with `open: feature:whistle`.
`Collection.leave(counts, uids, false)` (the new `star` flag) takes helpers off with no star and no `pets_left`.
GameState: `workshop_open / workshop_shown / built(id) / helpers_can_go / send_helpers` (through
`spare_pick`, off errands and machines first) `/ build_drawing / debug_build`, signal
`workshop_changed(built_id)`; the chores: `_ring_bell` (every second: done non-auto runs except
`watching` go through `collect_run`, their postcard dicts wait in `postcards`, not saved,
`letterbox_keep` at most; each postcard dict carries its `news` and `announce` lines, which
`AdventuresTab._show_postcard` hands back to your pet), `_vane` (in `_advance_runs`; `answer_event` remembers your picks in
`workshop.vane`), `_finish_plays` (the shelf, also at load; saves when it hands one again), `_workshop_chores`
(spade: `rummage` on ready spots; basket: `Toys.mend` once a minute via `_mend_acc`, so
`toys_changed` doesn't fire every second, plus the closed time at load), `job_joins` true for every errand
with the chart. `watching` is the run on the trail (AdventuresTab `_watch`, not saved). UI:
`WorkshopCard` (the card, with inner `Paper` and `Meter`), `AdventuresTab` (shed tap with the
workshop shown, the pills, bell postcards one at a time, `_open_letterbox`), `MapView._draw_built`
(built things at their `at`, a pop when just built, the letterbox count and its `letterbox` hotspot,
`letter_picked`), `TrailView` (the banner tosses treats), `ErrandsTab` (no join switches with the
chart), `UiTheme.drawing(art, size, color, width)` (a 48 px crayon sheet), `NewHomesStall.face_for`.
Dev steps `helpers <drawing> <n> [qual]`, `build <drawing>`, `expect built <id>`, `expect postcards
<n>`; `visit` now also calls `check_unlocks`. Flow: workshop.
Save v40 (HOUSE, built as v27 in the house lane) makes `room` the number of room steps built
(data/herd.json "room" steps + the endless "more"; `Herd.room_step / room_cap / room_cost /
room_currency`, `GameState.room_next / room_price / room_currency / buy_room / room_split`). The
squeeze-in steps cost wisps (the one purse) and show once `GameState.wisps_shown()` (wisps held, the
dungeon or the plushie machine open). A v28-v39 save's old level (500 x 1.5^L) becomes the fewest
steps that hold at least as much (`_migrate`); older saves get the margin rule on steps.

## Testing

- Tool and test scripts (`godot -s ...`) never load or save a save: `GameState.tool_run()` sees the
  `-s` and the GameState (the autoload, and any a script makes) starts empty with saving off.
  A script that wants the profile's save sets `GameState.tool_saves = true` (test_core does, around
  the GameState tests); `GameState.testing = true` starts empty too (tests, the pace players).
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
