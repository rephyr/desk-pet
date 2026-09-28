# D1 done: knacks (look C, sewn badges)

## What was built
Every part has a named knack (the 35 from design/mockups/screens/knacks.html; "no accessory" has
none). Size n (a %) = the kind's step x rarity (common 1, uncommon 2, rare 3, epic 5, legendary 8,
mythic 12) x the pet's finish (normal 1, shiny 1.25, holo 1.5, ghost 1.75, glitch 2, prismatic 2.5),
rounded to a whole %; it multiplies by 1 + n/100. Knacks of the same kind on one pet add up.
Traits stay as they are. Nothing is saved: knacks come from a pet's parts and finish.

- **Your active pet:** its knacks are the `knacks` boost source in the B2 plumbing
  (`GameState.boost_parts` appends `Knacks.parts(...)`, one part per kind, id like
  `body:bunny+eyes:cyclops`). "all" (the void body's "the hum") counts for coins, xp and luck.
- **Other pets:** a quarter (`own: 0.25`) of their knacks on their own work: errand speed
  (`_speed_of` x own "errands"), worker speed (`workers_speed` x own "automation"), and their trips
  (party average, below).
- **Trips:** `send_on_adventure` packs `RunState.knacks` (like gear) from `GameState.trip_knacks`:
  per kind boost(kind) x the party's average own share for trip, tough, safe, spots, finds, pickups,
  treats; `loot` = the party share only (your active pet's loot is in boost("loot") at collect).
  Kinds at x1 are left out. Read with `run.knack(kind)` (1.0 when missing):
  - trip: `AdventureRunner.walk_of` = 1 - (1 - boots walk) / trip (x1.15 = 15% quicker).
  - tough: hurt and injured counts / tough; safe: lost counts / safe (both on top of the harness).
  - spots: `Intel.roll(..., x)` multiplies each lead's own chance (not the safety net).
  - finds: `_boost_trip_loot` rolls an extra copy of each part and bit at (finds - 1).
  - pickups: trail pickups x pickups (with sticky paws); treats: treat zoom x treats.
  - The adventures tab's time and "about N% come home" preview use the knacks they'd pack.
- **New knack-only boost kinds hooked up:** away (errands' and the crank's time away and the old
  coin trickle count x away, also after the computer slept), rummage (rummage coins), shiny (the
  machine's shiny chance: lever, your pet's crank, errand shiny), pet_boxes (pet box weight in
  `Machine.roll` on the lever; not the sure-within-10 net).
- **Hidden until earned:** a knack shows and counts only when knacks are open (`feature:parts`,
  40 trips), its kind is a boost kind (or "all"), and its kind's gate is open: fever `machine:wires`
  (the lights), toys `feature:toys`, errands and away `feature:errands`, automation `tab:automation`,
  shiny `machine:shiny`. `power` isn't a boost kind, so the demon horns' "little horns" stays hidden
  and does nothing until fights add the kind.
- **UI (look C):** `KnackBadge` (32 px round sewn badge: tinted fill, 3 px edge in the part's tier
  colour, dashed stitch ring, the kind's doodle; chosen = tilted -8 degrees, x1.12, pink ring;
  hover lifts it). Pet details: a centred badge row under the rarity/finish tags, then a small card
  reading the chosen one ("one big eye", "+30% spotting", "eyes: cyclops"); the best badge (highest
  part rarity, then biggest) is read first. No knacks showing = no row, no card. Collection grid
  cards wear their best badge (24 px, tilted 10 degrees) on the top-right corner; box reveal cards
  stay plain. The grid redraws when the set of open knack kinds changes.
- Knack icons: `UiTheme.DOODLES` `knack_<kind>` (from the mockup's paths; pixel style uses them too).

## Files
- data/knacks.json (new), data/boosts.json (11 new kinds: spots, trip, tough, safe, finds,
  pickups, treats, away, rummage, shiny, pet_boxes)
- scripts/pets/knacks.gd (new, `Knacks`), scripts/ui/knack_badge.gd (new, `KnackBadge`)
- scripts/core/catalog.gd (`catalog.knacks`), scripts/game_state.gd, scripts/adventure/run_state.gd,
  scripts/adventure/adventure_runner.gd, scripts/adventure/intel.gd, scripts/machine/machine.gd,
  scripts/ui/pet_details.gd, scripts/ui/pet_card.gd, scripts/ui/collection_tab.gd,
  scripts/ui/adventures_tab.gd, scripts/ui/ui_theme.gd, scripts/dev/dev_driver.gd
- tests/test_core.gd (`_test_knacks`; `_gear_losses` takes knacks), tests/flows/knacks.flow (new),
  tests/flows/fits.flow (knacks open for the last card checks)
- docs/design.md (Knacks paragraph after Boosts), docs/architecture.md (Boosts section, pets line)

## Data shape
```json
{ "opens": "feature:parts",
  "rarity_x": { "common": 1, ..., "mythic": 12 },
  "finish_x": { "normal": 1, "shiny": 1.25, ..., "prismatic": 2.5 },
  "own": 0.25,
  "kinds": { "spots": { "step": 4, "text": "+{n}% spotting", "icon": "knack_spots" },
             "fever": { "step": 6, "text": "fever {n}% longer", "icon": "knack_fever", "opens": "machine:wires" }, ... },
  "parts": { "body:bunny": { "name": "big ears", "kind": "spots" }, ..., "accessory:none": {} } }
```
Mockup kinds renamed to boost ids: capsule -> speed, workers -> automation, hurt -> tough,
boxes -> pet_boxes. Texts changed where the maths is a divide: "adventures {n}% quicker",
"+{n}% tougher", "+{n}% safe home"; the crown's "automation {n}% faster" (it speeds your pet's
crank too, not only workers).

`RunState.knacks`: `{ "trip": 1.15, "spots": 1.48, ... }` in the run dict (key `knacks`).

## Save
No save change, no SAVE_VERSION bump. The run dict's new `knacks` field is optional (old runs
load as x1).

## Dev step
`dress <slot>=<id> ... [finish=<id>]`: your active pet gets these parts and finish, e.g.
`dress body=bunny eyes=cyclops finish=holo`.

## Checks
- test_core: ALL PASSED (3527 checks). `_test_knacks`: every part has an entry and every entry is a
  real part; every kind has step/text/icon and is a boost kind, "all" or power; sizes (common blob 3,
  legendary x-eyes 24, holo cyclops 30); nothing before parts open; power hidden; big ears + one big
  eye = one part x1.32; golden touch x1.40; the hum (prismatic) x1.6 on coins, xp, luck and not
  speed; fever waits for the lights; own = a quarter; party average; trip knack divides the walk
  (with boots too); a run's knacks survive a save and old runs are x1; tough + safe lose fewer
  pets; spotting knacks spot more.
- tools/balance.gd output byte-identical before and after (diffed): knacks are shut until parts open
  and every multiplier is exactly 1.0 without them.
- Flows, all PASSED: knacks (new), fits (extended), gear, toys, errands, errands_crowd,
  errand_tools, automation, workers, machine, party, postcard, rummage, tutorial, new_game, pet_box,
  encounters, boxes. machine printed the known flaky "2 resources still in use at exit" once.
- Screenshots looked at: knacks before_parts (no badges), grid (corner badges, the best badge read
  first), badge (tapped: one big eye), all_badges (fever and royal appear once opened), other_pet;
  fits pets_knacks. Everything inside the window, readable, matches look C.
- `boosts` in the knacks flow logs e.g. `boost spots x1.480 knacks body:bunny+eyes:cyclops x1.480`,
  and fever / automation parts appear after `fix wires` / `unlock tab:automation`.

## Review fixes (D1 follow-up)
- Lean totals: `Knacks.counting(catalog, kind, open)` builds a lookup table once per call
  (slot -> part id -> step x rarity, only open counting kinds); `sum_in` / `own_in` add a pet up
  with no display rows. `total`, `parts`, `own`, `party_all` use it; `of` / `best` are for the UI
  only. Measured in test_core: party_all over the 8 trip kinds 70 -> 20 us a pet (about 2.5 us a
  pet a kind; before, `of` alone was about 60 us a pet).
- `GameState.knack_own(pet, kind)` caches each pet's own share by uid; `trip_knacks`,
  `_pet_speed` (errands) and `workers_speed` use it. Cleared by `_knacks_changed()` (pet_changed,
  new game, load, `_regate`).
- New `_knack_gates_changed()` for unlock / unlocked / machine_upgraded / tutorial_changed /
  debug_lock_all / the `fix` dev step: clears boosts and the knack caches, and the errand and
  worker speeds only when the counting table for "errands" / "automation" changed (so a machine fix
  no longer drops them). Bumps `GameState.knack_version`, emits new signal `knacks_changed`.
  active_changed now only clears boosts.
- `put_on_job` (one pet and 10/100/all) picks by `_pet_speed` (errand knacks included), the same
  as `take_off_job` and `job_rate`.
- Adventures tab: `trip_knacks(pets)` runs only when `_trip_key` (place, picks, gear, active uid,
  trip-kind boosts, knack_version) changes; the result is kept in `_knacks` and used for the walk
  time and `estimate_return` (same key).
- Collection tab listens to `GameState.knacks_changed` (not `changed`); `_rebuild` records the
  open-kinds key, so the grid only redraws (and jumps to the top) when the kinds really changed.
- KnackBadge: `grow` instead of shadowing `scale`; the hover tween is killed before a new one.
- Dev step `fix` now calls `GameState._knack_gates_changed()` (no sparkles: machine_upgraded isn't
  sent), so knack badges gated by the machine show after `fix wires`.
- test_core: lean totals match the rows' totals for 300 rolled lucky-box pets over every boost
  kind and two gate sets; prints the party_all timing.

## Merge notes
- `Machine.roll` gained a trailing `pet_rate := 1.0`; `AdventureRunner.start` and
  `estimate_return` gained a trailing `knacks := {}`; `Intel.roll` a trailing `x := 1.0`.
- `_boost_trip_loot(loot, packed, knacks)`: a lane that also changes it should keep the knacks arg.
- A lane adding a boost source should keep `Knacks.parts` in `GameState.boost_parts`.
- The collection grid's scroll pad is now 12 px on top and 10 px on the right (room for the corner
  badges).

## Text to add
**docs/dev-plan.md (D1):** D1 knacks built (lane b2-d1, look C): data/knacks.json (35 knacks, one
per part, sizes step x rarity x finish), `Knacks` (scripts/pets/knacks.gd), your active pet's knacks
are the `knacks` boost source, other pets' count a quarter on their own errands, worker jobs and
trips (packed as `RunState.knacks`), 11 knack-only boost kinds (spots, trip, tough, safe, finds,
pickups, treats, away, rummage, shiny, pet_boxes). Hidden until parts open and until each kind's
system opens; power waits for fights (E1). Badges on the pet details (tap to read), the best badge
on grid cards' corners. Numbers are placeholders (tune with A1 / Star Reels later).

**CLAUDE.md "where we left off":** D1 knacks (look C, sewn badges): every part has a named knack
(data/knacks.json, `Knacks` in scripts/pets/knacks.gd; size = step x rarity 1/2/3/5/8/12 x finish
1..2.5, same kind adds up). Your active pet's knacks are the `knacks` boost source; other pets'
count `own` (25%) on their own errands/workers/trips. Trips pack `RunState.knacks`
(`GameState.trip_knacks`, `run.knack(kind)`). New boost kinds fed only by knacks: spots, trip, tough,
safe, finds, pickups, treats, away, rummage, shiny, pet_boxes. Hidden until feature:parts and each
kind's gate (`GameState.knack_gate`: adventures, machine:<node>, unlock ids); power hidden until
fights. UI: `KnackBadge` row + read card on PetDetails, best badge on collection PetCard corners.
Dev step `dress <slot>=<id> ... [finish=<id>]`; flow knacks. No save change.

## Questions for Emilia
- Knacks open with parts (feature:parts, 40 trips). Should they open earlier?
- Same-kind knacks add up (as the mockup says), then multiply with other boost sources. OK?
- Other pets count 25% on their own trips/jobs; finish x1.25 ... x2.5. All placeholders.
- "tougher" / "safe home" / "adventures quicker" work as divides (x1.12 = about 11% fewer or
  shorter), so the texts say "+12% tougher" rather than "12% fewer bumps".
- The crown's text says "automation 60% faster" (the mockup said workers): it also speeds your
  pet's own crank and box opening. Keep "workers"?
- Trip knacks are packed when a trip sets off, like gear (swapping your active pet mid-trip doesn't
  change a trip that's out).
- The corner badge is only on the collection grid, not on box reveal cards.
- "while away" makes time away count more (errands, the crank, the coin trickle) rather than
  raising the away-hours cap. OK?
