# A5 the sunset globe: done (lane globes)

Look A from lanes/mockups `design/mockups/screens/globes.html` (side by side), picks from
docs/picks.md (A5 + "Look picks, round 2").

**Status: VERIFIED (2026-09-29).** Built, reviewed, tests + balance + flows passing on lanes/globes.

## What was built

- **Globes in data** (data/machine_tree.json `globes`): sunny, sunset, midnight. Each has `find`,
  `works` (the repair that makes it work), `hatch` (its rusted hatch node), `step`, `box`, colours
  (`glass`, `body`, `seam`, `color`: a colour role or #hex), `icon`, `arrives` line, and a tree
  `view` rect. Midnight is data only (find `porch_machine` isn't in unlocks.json, no nodes).
- **Bits in data** (`bits`): name, plural, colour, globe for all 8 bits (the 4 old ones moved out
  of code: `Machine.BITS` is gone). New sunset bits: cork, pulley, wire ("copper wire"), amber
  ("amber glass").
- **Arrival:** event `fields_sunset_globe` in the far fields (`after_machine: drops`,
  `after: tiny_machine`, auto), find `sunset_globe`. Its find brings the globe home
  (`GameState._globe_home`, signal `globe_arrived`). On the machine tab the sunset globe slides in
  beside the sunny one, your pet says its `arrives` line once, and the machine tab has a news dot
  until then (`GameState.globe_news` / `greet_globe`).
- **Sunset repairs** (a chain off `drops`, `"globe": "sunset", "branch": "sunset"`, mockup
  numbers): shoo out the nest 2M (works) > cork the holes 6M + 2 corks (x2) > a pulley for the
  lever 20M + 1 pulley + 2 copper wire (x2, +1 chute) > amber glass 80M + 2 amber glass (x3,
  lights, glass) > the rusted hatch 300M + 3 of each (x5, its hatch).
- **Hand / behind** (Machine.hand / behind / newest / working): the newest globe whose `works` is
  fixed is the one you pull; the one before it (or the hand globe while it's alone) is what your
  pet's crank, workers' capsules and errands' capsule value use. Before the nest you keep pulling
  the sunny globe and the broken sunset one just stands there.
- **Per-globe numbers:** every node has `globe` (default the first). `chutes`, `lights`, `glass`
  count only on their own globe; everything else (coins_x, double, triple, shiny, shiny_x, fever_s,
  drops) on its own globe and every newer one. Coin value = base x shared coins_x x the globe's
  `step`. Shiny only works on a globe once it has its own glass (if it has glass to fix). One lights
  counter and one fever, on the hand globe.
- **The hatch:** box and pet box prizes on a globe become its box tier (walking back to the newest
  open hatch below it), and its toy set joins the toy roll (`Machine.box_of`, `Machine.toy_sets`,
  `Toys.roll(..., sets)`). Toy sets have `globe` in data/toys.json.
- **Sunset toys** (set "sunset friends", 14x14 pixel art, new palette letters s S a A y): firefly
  (common, luck), hedgehog (common, coins), sleepy owl (uncommon, xp), paper lantern (rare, fever).
  The toys page shows a chip per set once a later set shows (its hatch is open or you own one of
  its toys); hidden until then.
- **Sunset bits drop only once the globe is home:** finish rewards with `after: sunset_globe`
  (orchard cork 0.6 + amber 0.4, old well pulley 0.6, far fields wire 0.6).
  `AdventureRunner.resolve(..., found)` skips treats whose `after` isn't found; a place whose bag is
  all waiting gives no finish treat (so the old well gives no treat and no finish xp until then).
  `grant()` also drops bits of a globe that isn't home (safety net).
- **Machine tab (look A):** `StageHolder` draws the panel and the floor; two `MachineStage`s side by
  side (older 0.8, newest 1.0), each with a tilted sign above (globe icon + name) and a stat line
  under it (hand: coins a capsule + chutes, or the fever; behind: "N workers" / "your pet's
  cranking" + coins a capsule; nothing under a globe that doesn't work). Only the hand stage takes
  the mouse and shows the coin counter (top left of the whole panel). The `OddsCard` now lives on
  the holder (top right) and follows the hand globe.
  - Broken sunset drawing, one piece per `fixes`: nest (twig nest + feather inside, leaves out of
    the top and chute, rust spots), holes (3 holes, a capsule dribbling out; corks once fixed),
    sag (the lever droops at rest, follows your hand heavily and creeps back; after the pulley a
    pulley wheel + rope holds it up), amber (cloudy until fixed, then a warm glow), hatch (rusty and
    crooked until fixed). Fix sparkles as before (`MachineStage.fixed`). The stage now checks
    `Machine.broken(globe, fix)` instead of node ids, so a later globe's pieces come from data.
  - The globe behind yours: while workers (or your pet, task machine) crank it, the first one hangs
    off its lever (pixel pet, nearest filter), two wait at its feet, the lever keeps going, and
    `pet_cranked` results drop a capsule with a little "+coins" / "a toy!" / "a box!".
  - `FixList` (236 px, "sunset fixes") replaces "next up" while the newest globe has repairs left:
    a row per repair (disc, name, needs or "fixed ✓"), the picked one opens (says, gain, fix it /
    not yet). Rows are named `fix_row_<id>`.
  - Bits pills (named `bits_<id>`): the newest globe's bits while its fixes list is up; with only
    the first globe home, its bits (as before); after that, the bits the open upgrades ask for (or
    the bits you own when none ask; at most 4 pills).
  - A stage keeps its globe while that globe stays on show (the tab reorders the row, older on the
    left), so capsules in flight (a pet box) and a held lever survive a new globe arriving.
    `busy()` only looks at the hand stage (worker capsules never hold unlock popups).
  - `MachineStage.refresh_state()` works out what's broken (`_fix_state`), chutes, lights, hatch,
    coins a capsule, the crew's textures and the stat line numbers on setup, on every
    `GameState.changed` and on `toys_changed`; `_process` / `_draw` only read those.
  - FixList rows rebuild only when the pick, levels, looks or what you can pay for change; the
    next row's breathing ring runs on `Time.get_ticks_msec()`.
- **Upgrades page:** `TreeMap` frames the viewed globe's `view` (tweened), older globes' nodes fade
  (0.45), nodes of globes not home aren't drawn at all (`Machine.look` = "away"), a sign button per
  globe (`sign_<id>`) pans. A later globe's repair chain is "dim" (not "?") past its next node once
  the globe is home, so the tree and the fixes list agree (look A's mockup shows every fix). When
  the page suggests a node on another globe (the newest is all fixed), it frames that globe. Later globes' repair names sit beside their nodes. `MachineMini` draws
  the picked node's own globe. Sunset nodes wear the globe's colour (`MachineTreeView.node_color`).
- **Map / adventures card / postcard:** bits from data (`MapView.bits_of`, `bit_color`,
  `Machine.bit_name`); the orchard shows both its bits once the sunset globe is home.
- **Dev driver:** a click on a list row that rebuilds on press doesn't send the release to the freed
  row; `expect pile <box> <n>+` (at least n).

## Files

- data/machine_tree.json (globes, bits, sunset nodes, `glass: 1` on the sunny glass node),
  data/adventures.json (event, `after` treats, notes), data/unlocks.json (find `sunset_globe`),
  data/toys.json (set `globe`, sunset set + art, palette), data/voice.json (machine_fix_nest ..
  machine_fix_hatch)
- scripts/machine/machine.gd (globes, bits, per-globe `g := ""` params, `counts`, `broken`,
  `has_fix`, `repairs`, `repairs_left`, `box_of`, `toy_sets`, `step`, look "away")
- scripts/machine/toys.gd (`of_sets`, `roll(..., sets)`)
- scripts/game_state.gd (signal `globe_arrived`, save v24, `globe_news`, `greet_globe`,
  `_globe_home`, `_bit_home`, hand in `pull_lever` / `_capsule` / `machine_odds`, behind in
  `_pet_capsule` / `job_boost`, `bit_hint` from data)
- scripts/adventure/adventure_runner.gd (`resolve(..., found)`, `_finish_treat` filter)
- scripts/ui/ui_theme.gd `named_color(name, fallback)` now takes "#hex" and the seam / text roles
  (used by MachineTab, MachineTreeView, MapView.bit_color); bit doodles use `{bit}` / `{bit_mid}` /
  `{bit_dark}`, filled from the bit's data colour
- scripts/ui/machine_tab.gd (StageHolder, FixList, Disc, `needs_row`, `globe_color`,
  MachineStage globe/hand/compact, sunset drawing, crew, crank), scripts/ui/machine_tree_view.gd,
  scripts/ui/ui_theme.gd (icons bit_cork, bit_pulley, bit_wire, bit_amber, tree_nest, tree_cork,
  tree_pulley, tree_amber, tree_hatch, globe_sunny, globe_sunset, globe_midnight),
  scripts/ui/map_view.gd, scripts/ui/adventures_tab.gd, scripts/ui/postcard.gd,
  scripts/ui/toys_view.gd, scripts/ui/expanded_view.gd (machine news dot)
- scripts/dev/dev_driver.gd, tests/test_core.gd (`_test_globes`, `_test_globes_game`),
  tools/balance.gd ("globes" table), tests/flows/globes.flow (new)
- docs/design.md (Globes paragraph, the old "NEVER automated" line updated),
  docs/architecture.md (Screens, Saving)

## Data shape

```json
"globes": [
  { "id": "sunset", "name": "sunset globe", "icon": "globe_sunset", "find": "sunset_globe",
    "works": "nest", "hatch": "hatch", "step": 12, "box": "sunset", "glass": "#ff9f8a",
    "body": "#ff9f8a", "seam": "#a8604f", "color": "#ff9f8a", "arrives": "...",
    "view": [110, -430, 490, 475] }
],
"bits": { "cork": { "name": "cork", "plural": "corks", "color": "#d9a066", "globe": "sunset" } },
node: { "id": "cork", "globe": "sunset", "branch": "sunset", "at": [390, -120], ... }
finish reward: { "kind": "bit", "id": "cork", "chance": 0.6, "after": "sunset_globe" }
toy set: { "id": "sunset", "name": "sunset friends", "globe": "sunset", "toys": [...] }
```

## Save bump

**v23 -> v24** (the merge step renumbers). New `machine.globes` and `machine.greeted`. There is no
`_migrate` step: `load_game` gives a save without them just the first globe for both (already seen),
drops unknown globe ids, keeps the first globe always, and (any version, every load) adds a globe
whose find is in `finds` but isn't in the list. Nothing depends on the number: if renumbered, only
the "v24 added machine globes" comment in `_migrate` and the test's "v23 -> v24" label move. No
"sunny" id is hard-coded in GameState or the UI (fresh state starts with empty lists; the first
globe comes from `Machine.first_globe`), only in `Machine.globes()`'s fallback for a catalog
without globes.

## Flows, tests, dev steps

- `python3 tools/play.py globes` (from rich): sunny all fixed > intel + tiny machine > the sunset
  globe slides in (fixes list, "0 corks" pills) > the tree at arrival (the whole chain dim) > open a dim row > fix the nest (hand moves, lever
  sags) > a sagging pull > teach machine + workers (3 on the sunny globe, one on its lever) > cork,
  pulley (2 chutes), amber, hatch (fixes list gone, next up back) > `next-prize box` = a sunset box >
  upgrades page (sunset view, pan to sunny and back) > the sunset toy set > the orchard card with
  corks + amber glass. `expect fits` at each page.
- Re-run and passing: machine, machine_odds, fits, pet_box, workers, automation, box_tiers, toys,
  bits_map, postcard, tutorial, errands, errand_tools, gear, home_pile, unlock_popup, new_game,
  party, boxes, rummage, encounters, long_pet.
- tests/test_core.gd `_test_globes`: data (globes, find/event, branch off drops, bits complete,
  every node asks for its own globe's bits, every sunset bit has a place), hand/behind before
  arrival / broken / after the nest, "away" until home, per-globe numbers after each fix, box and
  toys at the hatch, the finish treat with and without the find (and the old well's empty treat),
  an injected midnight catalog (3 globes). `_test_globes_game` (only with `--profile`): a GameState
  in the test profile: the find brings it home + news, bits wait for it, errands and your pet's
  crank use the behind globe, a v23 save file loads with just the first globe, already seen. Also:
  the whole sunset chain is next/dim once home.
- tools/balance.gd "globes": coins a pull by hand and a worker's capsule, sunny all fixed then per
  sunset fix. With step 4 (the plan's) the nest made your pull x0.35 worse, so the sunset `step` is
  **12** (x1.05); midnight's placeholder step is 144.
- No new dev steps; `find sunset_globe`, `bits cork 5` etc. work through the existing ones.
  Driver: `expect pile <box> <n>+`.

## Changes from the plan

- `step` 12 instead of 4 (balance rule above).
- The hatch isn't an effect key: a globe's hatch is its `hatch` node id in the globe data.
- Toy sets carry `globe` (no `toys` field on globes).
- `porch_machine` isn't added to unlocks.json finds (the data test wants every find to have an
  event); the midnight globe names it, that's all.
- The sunset hatch is drawn on top of the globe (like the sunny one's), crooked and rusty.

## Text to add elsewhere

**docs/dev-plan.md**, A5 heading: `### A5. The machine later: a globe per map page  (BUILT + VERIFIED 2026-09-29, lane globes)` and add:

> - **Built:** look A. Globes + bits in data/machine_tree.json; the sunset globe comes home from the
>   far fields after the tiny machine (event `fields_sunset_globe`), broken, beside the sunny one;
>   5 repairs off the old hatch (nest > cork > pulley > amber > hatch) with corks + amber glass
>   (orchard), pulleys (old well), copper wire (far fields), only once it's home. The newest working
>   globe is the hand; your pet, workers and errands use the one behind. Shared vs own-globe effects,
>   step x12, the hatch = sunset boxes + the sunset toy set. Fixes list, sign per globe on the tree.
>   Midnight is data only (waits for E2 next door). Save v24. Flow globes.

**CLAUDE.md "Where we left off"**, new bullet:

> - A5 the sunset globe (lane globes): data/machine_tree.json `globes` (find, works, hatch, step,
>   box, colours, arrives, view) and `bits` (name, plural, colour, globe; `Machine.BITS` gone).
>   Machine.hand / behind / newest / home, per-globe `g := ""` params (chutes, lights, glass own;
>   the rest shared), `box_of`, `toy_sets`, `broken(globe, fix)`. The sunset globe: find
>   `sunset_globe` (far fields, after the tiny machine), repairs nest/cork/pulley/amber/hatch, bits
>   cork/pulley/wire/amber (finish rewards `after: sunset_globe`, `AdventureRunner.resolve(..., found)`).
>   Machine tab = two stages side by side (StageHolder, MachineStage globe/hand/compact, FixList),
>   the tree pans by globe signs. Toys: sunset set, `Toys.roll(..., sets)`. Save v24
>   machine.globes + greeted. Flow globes; balance "globes" table.

## Questions for Emilia (the smallest safe pick was made)

1. Where does the globe turn up? Picked: the far fields, on the next trip there after the tiny
   machine is home.
2. The sunset lever before the pulley: picked: it droops (rests half pulled), follows your hand
   heavily and creeps back slowly, but you can still pull it.
3. What carries over to a newer globe: picked coins, extra balls, shiny chance and pay, fever,
   drops; chutes, lights and glass are per globe (so the sunset globe has no lights/fever and no
   shiny until amber glass).
4. Sunset toys: a set of 4 (firefly, hedgehog, sleepy owl, paper lantern; common, common,
   uncommon, rare). The sunset pet box holds one pet with sunset box odds.
5. The old well now has a finish treat (pulleys), so its trips also give the finish xp, but only
   once the sunset globe is home (before that it has no treat at all). OK?
6. `step`: 4 made fixing the nest a worse pull (x0.35), so it's 12 now (x1.05). With it the
   mockup's repair prices (2M..300M) are only a few pulls each at that point; the bits are what
   pace the sunset branch. Tune prices up, or keep bits as the gate?
7. The FixList keeps "all upgrades →" at its bottom (the mockup had none). Keep?
8. Hidden Until Earned vs look A: the mockup shows every sunset fix by name and cost as soon as the
   globe is home. Picked: follow the mockup on both pages (the sunset chain is "dim" on the tree
   instead of "?"; the fixes list shows dim rows with their costs). The other way would be "?" rows
   in the fixes list like the sunny tree. Which one?
