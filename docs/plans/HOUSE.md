# HOUSE: room upgrades, the dollhouse card: build plan

Sources: picks.md "Brainstorm 3 picks" (room upgrades: the house card) + "Look picks, round 3"
(the room house, look A the dollhouse), mockup lanes/mockups2 design/mockups/screens/room-house.html
look A. Builds on the room that's already here (C1/C3: RoomPill, Herd.room_cap, GameState.room,
save v26 on this branch).

## What changes

Today the room is an endless level number (500 x 1.5^L, coins x 1.8^L) and the pill opens a tiny
"more room" card. It becomes a list of named steps: 4 coin steps (a second plank, bunk beds, a
loft, the attic), then wisp "squeeze in" steps that keep going. Each step is ONE currency. Every
plain pet counts toward the room, pets on jobs too (already true: `Collection.plain_count()`
includes herd counts out on errands / worker spots / away).

## Data (data/herd.json "room", placeholders, the pace sim tunes later)

```json
"room": {
  "start": 500, "cozy_at": 0.9, "old_save_margin": 0.1,
  "steps": [
    { "id": "plank",    "name": "a second plank",      "cap": 750,   "capsules": 500 },
    { "id": "bunks",    "name": "bunk beds",           "cap": 1100,  "capsules": 900 },
    { "id": "loft",     "name": "a loft",              "cap": 1700,  "capsules": 1620 },
    { "id": "attic",    "name": "the attic",           "cap": 2500,  "capsules": 2920 },
    { "id": "three",    "name": "beds three high",     "cap": 5000,  "wisps": 60 },
    { "id": "hammocks", "name": "hammocks",            "cap": 10000, "wisps": 240 },
    { "id": "drawers",  "name": "pets in the drawers", "cap": 20000, "wisps": 960 },
    { "id": "teapot",   "name": "pets in the teapot",  "cap": 40000, "wisps": 3840 },
    { "id": "rug",      "name": "under the rug",       "cap": 80000, "wisps": 15360 }
  ],
  "more": { "name": "one more squeeze", "grow": 2.0, "wisps_grow": 4.0 }
}
```

- Coin steps: `capsules` x `Machine.coin_value` now (like errand tools / boxes). First step stays
  500 capsules = 10 starter boxes (existing test).
- After the last listed step, `more` steps keep going forever: cap x2, wisps x4 each (cap clamped
  at 1e15, price at Jobs.MAX_PRICE).
- Step lines in data/voice.json "ui": `room_<id>` per step (from the mockup: "bunk beds!! i call
  top bunk!"...), `room_more` for tail steps (exists), `room_poor` (exists), `room_poor_wisps` new.
  Card opening line `room_open` only when the room is cozy/full.

## Code

- **Herd** (scripts/pets/herd.gd): `room_step(catalog, i) -> Dictionary` (listed or synthesised
  tail step: id, name, cap, and `capsules` or `wisps`), `room_cap(catalog, level)` = start at 0,
  else step(level-1).cap; `room_level_for` unchanged logic; `room_cost(catalog, level, value)`
  (coins for a coin step, wisps for a wisp step), `room_currency(catalog, level)` "coins"/"wisps".
- **GameState**: `room` now means steps built. `room_next()` = the next step, or {} when it's a
  wisp step and wisps haven't shown up yet (hidden until earned). `room_price()`,
  `buy_room()` pays in that step's one currency. `room_split() -> [shelves, jobs]`: plain pets at
  home vs out working (herd used by jobs / wherd / away + plain cards on jobs/workers); sums to
  `plain_count()`.
- **Wisps (one small place, for the merge)**: `var wisps := 0`, `var wisps_seen := false`,
  `grant_wisps(n)` (sets wisps_seen), `"wisps"` key in `grant()`, `wisps_shown()`. If another lane
  already has these, the merge keeps theirs and drops mine. `UiTheme.WISP := Color("ff9e7d")`
  (candy floss coral, not a theme role yet) + a "wisp" icon (doodle + pixel), and a "shelf" icon.
- **HouseDrawing** (new, scripts/ui/house_drawing.gd, Control 260x220, `_draw`, nearest filter):
  the shell (walls, roof seam, grass, heart picture, chimney) + one part per step id drawn from the
  mockup's coordinates. Modes per part: built (solid), next (pencil: dashed MUTED lines, WISP for a
  wisp step, no pets, no fills), fresh (sparkles + pets hop in). Tiny pets are 16x18 looks from
  `GameState.herd_faces` (your real shelves; cycled, the active pet if there are none). Tail steps
  tuck one more tiny pet into a seeded spot each (from a spot list), so the house keeps filling.
  Unknown step ids draw nothing extra.
- **HouseCard** (new, scripts/ui/house_card.gd, ~400 px wide sticker, replaces RoomPill's little
  card; RoomPill.toggle_card opens it). A dim layer behind it; tap outside or the x closes it.

```
+-------------------------------------------------+
| [house] our house               1,204 / 1,700  x|
| +---------------------------------------------+ |
| | [shelf] 618      /\  cut-away house         | |
| | [basket] 586    /  \  built parts solid,    | |
| |                |....| next step in pencil   | |
| +---------------------------------------------+ |
| .-----------------------------------------------.|
| : bunk beds                 [build it  (c)900 ]  :|
| : [house] 750 > 1,100                            :|
| '-----------------------------------------------'|
+-------------------------------------------------+
```

  - Head: house icon, "our house", count (pink when cozy), x.
  - Well: DEEP box 232 high, the drawing centred, chips top-left: shelves count, jobs count.
  - Next row (dashed; coral dashes for a wisp step): step name, "750 > 1,100" with a house icon,
    button "build it" + coin + price, or "squeeze in" + wisp + price. Short on money: the button
    stays tappable and your pet says `room_poor` / `room_poor_wisps` (as today).
  - Nothing next (coin steps done, no wisps yet): "everyone's moved in" row in mint with
    "500 > 2,500" (from the mockup's done state).
  - After a buy: the pencil part turns solid with sparkles, your pet says the step's line, the
    card stays open on the new next step (the mockup keeps it open).
  - Under the pill, right edges lined up, clamped inside the window.

## Save: v26 -> v27 (the merge renumbers)

- New fields `wisps`, `wisps_seen`.
- `room` changes meaning (level of the 1.5x formula -> steps built). Load: a v23-v26 save gets
  `room = Herd.room_level_for(catalog, old_cap(room))` with old_cap = the v26 formula (500 x 1.5^L,
  round 50), so nobody loses room (a big old room can land on a wisp step: kept, for free). Saves
  before v23 keep their margin rule, now on the new steps.

## Dev steps + flows

- `room <level>` stays (steps built). New `wisps <n>` (grant n wisps).
- New flow tests/flows/house.flow: from new, `herd common normal 400`, some pets on a job
  (`job coin_hunt 50`), collection tab, click RoomPill#1, expect "our house" / "a second plank",
  expect fits, shot; coins, click "build it", expect "bunk beds", shot (sparkles); `room 4`, reopen,
  expect "everyone's moved in*", no-text "squeeze in", shot; `wisps 500`, expect "beds three high"
  + "squeeze in", click it, shot; `room 12` (tail), shot; coins 0 + click the price, wait text for
  the poor line; expect fits after every shot.
- pets_shelves.flow: "more room" -> "our house" (the price clicks stay).

## Tests (tests/test_core.gd)

- Steps: caps grow, coin steps priced in capsules (8x on a repaired machine, first = 10 starter
  boxes), wisp steps priced in wisps, one currency per step, tail keeps going (level 30, 100: cap
  grows, price > 0, no overflow), `room_level_for(5000)` still right.
- Hidden until earned: `room_next()` is empty after the attic until `wisps_seen`.
- `buy_room` on a wisp step takes wisps only, coins untouched; short = false.
- `room_split` sums to `plain_count` and counts herd pets on a job as jobs.
- Migration: v26 saves with room 0, 1, 2, 5, 10 load with cap >= their old cap; wisps round-trip.
- tools/balance.gd room table: one row per step (cap, currency, price at 4 capsule values).

## Done-notes

docs/plans/HOUSE-done.md with files, data shape, the save bump, flows, dev steps and the text for
design.md / architecture.md / dev plan / CLAUDE.md.

## Questions for Emilia (smallest safe pick in brackets)

1. After the attic (2,500) the room waits for wisps, which come late (dungeon). Mid-game crowds
   of thousands on jobs will hit it; new homes / the sorting rule are the outlet. OK, or more coin
   steps? [4 coin steps, as in the mockup; the pace sim sets sizes]
2. What do endless steps after "under the rug" look like? [named "one more squeeze", each tucks
   one more tiny pet somewhere in the house]
3. Wisp colour/icon come from the dungeon lane later [coral ff9e7d + the mockup's candy floss
   puff, until the merge].
