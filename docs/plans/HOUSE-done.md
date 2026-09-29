# HOUSE: room upgrades, the dollhouse card: done notes (lane house)

**Status: VERIFIED. Built, tests + balance + flows (house, pets_shelves, fits) pass; committed on
lanes/house (07546a3), not pushed.** Save **v27** (one bump from this
branch's 26; renumber at the merge).

Built from docs/plans/HOUSE.md, picks.md ("Brainstorm 3 picks": room upgrades, the house card;
"Look picks, round 3": the room house, look A the dollhouse) and the mockup
lanes/mockups2 design/mockups/screens/room-house.html look A.

## What was built

- **Room steps instead of room levels.** The room (every plain pet together, pets on jobs too) grows
  in named steps, each ONE currency:
  - 4 coin steps, priced in capsules x `Machine.coin_value` (like errand tools and boxes):
    a second plank 750 (500 capsules = 10 starter boxes), bunk beds 1,100 (900), a loft 1,700
    (1,620), the attic 2,500 (2,920).
  - wisp squeeze-in steps: beds three high 5,000 (60 wisps), hammocks 10,000 (240), pets in the
    drawers 20,000 (960), pets in the teapot 40,000 (3,840), under the rug 80,000 (15,360).
  - then "one more squeeze" forever: room x2, wisps x4 each (room stops at 1e15, price at
    `Jobs.MAX_PRICE`).
  - The squeeze-in steps stay hidden until wisps have shown up (`GameState.room_next()` is empty:
    the card says "everyone's moved in ♡" with "500 › 2,500").
  - All numbers are placeholders in data/herd.json "room" (the pace sim tunes them).
- **The house card (look A, the dollhouse)**, `HouseCard`, opened by tapping the room pill (the
  old little "more room" card is gone):
  - Head: house icon, "our house", the count "464 / 500" (pink when cozy), ✕.
  - A dark well (232 px) with the cut-away house (`HouseDrawing`) and two chips top-left: pets on
    the shelves and pets out on jobs (`GameState.room_split()`; the two add up to every plain pet).
  - "Next up" (dashed StitchBox; coral dashes for a wisp step): the step's name, the room growing
    (house icon, "750 › 1,100"), and "build it" + coin + price, or "squeeze in" + wisp + price.
  - Short on it: the button stays tappable (muted) and your pet says `room_poor` /
    `room_poor_wisps`.
  - A build: the pencil part turns solid, sparkles rise, its pets hop in, your pet says the step's
    line (`room_<id>`, `room_more` for the endless ones), and the card stays open on the next step.
  - Opening it when the room is cozy: your pet says `room_open`.
  - A dim layer over the pets page behind it; tap outside, ✕ or the pill again to close. The pill
    is lit pink while it's open. The card sits under the pill, right edges lined up, a little tail
    pointing at the pill, kept inside the window; 400 px wide. Numbers past a million turn short
    (10.2M) so the card never widens.
- **The drawing** (`HouseDrawing`, 260 x 220, the mockup's coordinates): the house shell (walls,
  wallpaper stripes, heart picture, chimney, grass, roof seam) plus one part per step id (plank,
  bunks, loft, attic, three, hammocks, drawers from the mockup; teapot and rug drawn new: a teapot
  on the loft floor with a pet under the lid, a rug hump on the attic floor with two pets peeking
  out). Built parts are solid with tiny pets (your real looks: a few from every count on the
  shelves, taken in turns, the same every time); the next step in pencil (dashed, empty, no pets;
  muted for coins, coral for wisps). Each endless step tucks one more tiny pet into a spot (roof,
  window, chimney, grass, ladder, on the plank...; 13 spots, then they stop showing); the next one
  shows as a dashed pet-sized outline. How it's drawn: an SVG built in code, turned into a picture at
  2x (`Image.load_svg_from_string`), tiny pets pasted in pixel-sharp in draw order (so blankets,
  hammocks, drawers and the teapot tuck them in); a new step's pets hop in on top for 0.7 s.
- **Wisps, in one small place (for the merge):** `GameState.wisps`, `wisps_seen`,
  `grant_wisps(n)`, grant() key `"wisps"`, `wisps_shown()`, reset in new game, saved.
  `UiTheme.WISP` (candy floss coral ff9e7d, a const, not a theme role) and icons "wisp" (doodle +
  pixel, the mockup's candy floss puff) and "shelf". **If the dungeon lane has wisps, keep theirs and
  drop these** (the room only needs `wisps`, `wisps_shown()` and subtracting on a buy).
- tools/balance.gd: the room table is one row per step (holds, price at 4 capsule values or wisps).

## Files

- data/herd.json: "room" is `{ start, cozy_at, old_save_margin, steps: [{ id, name, cap, capsules
  | wisps }], more: { id, name, grow, wisps_grow } }` (grow / round / capsules / cost_grow are gone).
- data/voice.json "ui": `room_open`, `room_poor_wisps`, `room_plank`, `room_bunks`, `room_loft`,
  `room_attic`, `room_three`, `room_hammocks`, `room_drawers`, `room_teapot`, `room_rug`.
- scripts/pets/herd.gd: `ROOM_TOP`, `room_step`, `room_cap`, `room_level_for`, `room_cost`,
  `room_currency`.
- scripts/game_state.gd: SAVE_VERSION 27, wisps block, `room_currency`, `room_next`, `room_split`,
  `buy_room` (one currency), grant "wisps", save/load/migrate, new game.
- scripts/ui/house_card.gd (new), scripts/ui/house_drawing.gd (new), scripts/ui/room_pill.gd (opens
  the card, the dim layer, lit while open), scripts/ui/ui_theme.gd (WISP, icons).
- scripts/dev/dev_driver.gd: `room <n>` now means steps built; new `wisps <n>`.
- tests/test_core.gd (`_test_room`, the price checks), tests/flows/house.flow (new),
  tests/flows/pets_shelves.flow ("more room" -> "our house"), tools/balance.gd.
- docs/design.md (the room), docs/architecture.md (RoomPill / HouseCard, prices, save v27).

## Save v27 (renumber at the merge)

- `room` = room steps built (was a level of 500 x 1.5^L). A v23-v26 save's level becomes the
  fewest steps that hold at least as much (`_migrate`: level 0 -> 0, 1 -> 1, 2 -> 3 (1,125 ->
  1,700), 5 -> 5 (a wisp step, for free), 10 -> 8 (28,850 -> 40,000)): nobody loses room.
- New `wisps` (int) and `wisps_seen` (bool). Saves before v23 keep their margin rule (now on steps).

## Review fixes (second pass)

- The house is drawn once per build (was three pictures): the refresh that `buy_room()`'s `changed`
  queues finds the fresh house already up. Opening the card keeps the old picture unless the steps
  or the tiny pets' looks changed (`_shown` = "steps|pencil step|hash of the looks"; the looks are
  worked out when the card opens or a step is built).
- The card refreshes at most once a frame (signals queue a deferred `_flush`), and remakes the step
  row / button boxes only when "wisp | poor" changes.
- `HouseDrawing._bake` makes both pictures (with and without the fresh step's pets) in one pass,
  splits the SVG only at pets a later shape covers (`_pet(..., under = true)`: blankets, hammocks,
  drawer front, teapot, rug; the loft pets under the teapot, the attic pet under the rug), pastes
  every other pet in one go just before the roof seam (an op `["top"]`), and blends later pieces
  only where they drew. Checked pixel for pixel against the old way: same picture. On the Xvfb
  test screen: all 9 steps ~20 ms (was ~21-32), a fresh step ~16 ms (was ~33 plus the two extra
  draws).
- Hop-in pets are made at 2x like the baked ones and hop in whole pixels.
- A step in data/herd.json with no drawing of its own still shows: it takes a tuck spot from the
  far end of TUCKS (in pencil: the dashed pet outline).
- tests: `_test_room` checks rules, not placeholders (at least one coin step, coin steps before
  wisp steps, every step and the endless one has a name and a `room_<id>` line; the game part uses
  the real coin step count and prices). Checked with an extra coin step added: still passes.
- `UiTheme.full_num(n)` (1,234,567) is the thousands formatter now; `ExpandedView._thousands` just
  calls it (other files still use it; left alone to keep the merge small).
- GameState: `grant_wisps` / `wisps_shown` moved down next to `buy_room` (only the two vars stay
  in the variable block), so they're easy to drop when the dungeon lane's wisps merge.

## Flows and dev steps

- `python3 tools/play.py house` (DESK_PETS_LANE=house): from rich, 462 plain pets, 50 on the coin
  hunt; the card ("our house", "a second plank", no "squeeze in"), build it (sparkles, "bunk
  beds"), `room 4` ("everyone's moved in", no wisp steps), `wisps 500` ("beds three high",
  "squeeze in"), squeeze in ("hammocks"), `wisps 0` + tap (the poor wisps line), `room 9` with 60k
  pets ("one more squeeze"), `room 16` (tucked pets, short numbers), coins 0 + tap "900" (the poor
  coins line), close. `expect fits` after every shot. Shots: card, built, bunks_next, moved_in,
  squeeze, squeezed, poor_wisps, all_listed, endless, poor, closed.
- pets_shelves and fits flows pass.
- Dev steps: `room <steps>`, `wisps <n>`.

## Text to add

**docs/dev-plan.md** (under the room / C-phase items):
> - HOUSE (built, lane house): room upgrades on the house card (look A, the dollhouse). 4 coin steps
>   (capsules x coin value), then wisp squeeze-in steps (hidden until wisps), then endless "one more
>   squeeze". Save v27 (renumbered at the merge). Placeholders: sizes and prices wait for the pace sim.
>   Open: wisps come from the dungeon lane (this lane has a stand-in `wisps` field + grant).

**CLAUDE.md "where we left off"**:
> - HOUSE (2026-09-29): room upgrades = the house card (look A, the dollhouse), opened from the room
>   pill: one cut-away house (scripts/ui/house_drawing.gd, an SVG made in code + pixel pets) that
>   grows a step at a time, next step in pencil, chips for pets on the shelves / on jobs, "next up"
>   row with "build it" (coins = capsules x coin value) or "squeeze in" (wisps). Steps in
>   data/herd.json "room" steps + "more" (endless, each tucks one more pet in); each step ONE
>   currency; wisp steps hidden until wisps show up. GameState.room = steps built, room_next /
>   room_split / buy_room, wisps + wisps_seen + grant_wisps (save v27, old room levels keep their
>   room). Dev steps `room <steps>`, `wisps <n>`; flow house.

**docs/design.md / docs/architecture.md**: already edited in this lane (the room paragraph; the
RoomPill / HouseCard line, the prices line, a "Save v27" paragraph).

## Questions for Emilia (what I picked)

1. After the attic (2,500) the room waits for wisps, which come late (dungeon). Crowds of thousands
   on jobs will hit that; new homes and the sorting rule are the way out. OK, or more coin steps?
   [4 coin steps, as in the mockup]
2. Endless steps after "under the rug": [named "one more squeeze", x2 room, x4 wisps each; each
   tucks one more tiny pet into the house (13 spots, then the picture stops changing)]. x4 wisps
   grows very fast (step 21 costs ~258B wisps): the pace sim should set it.
3. Wisp colour/icon until the dungeon lane merges: [coral ff9e7d + the mockup's candy floss puff].
4. No wisps chip in the top bar here (the dungeon lane owns wisps and their chip); the card only
   shows the price and goes muted when you're short. OK?
5. Teapot and rug had no drawing in the mockup: I drew a teapot on the loft floor (a pet under the
   lid) and a rug hump on the attic floor (two pets peeking out). Fine, or somewhere else?
