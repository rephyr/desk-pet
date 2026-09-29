# Pace report (A1), re-run on the merged game, 2026-09-29

The numbers come from `tools/pace.gd`. It plays pretend players through a fresh game using the
game's real GameState, rules and data:

    godot --headless -s tools/pace.gd -- --profile=test-sim --minutes=240 --runs=5
    (--style=casual, --treats, --tweak=jobs/coin_hunt/tools/noses/grow=1.5 to try a number)

This is the merged game (every lane up to save v40) with the A1 balance picks applied:

- errands tweak "C":
  - lemons / noses / bigger_jar grow 1.5
  - paws + sign speed 0.04
  - pockets big 0.05
  - snack all_speed 0.03
  - coin hunt + lemonade goals x1.25 / 1.25 / 1.5
- machine job seconds 48 -> 15
- automation prices from the old table (about x100)
- auto_adventures trips 60 -> 30
- garden -> pond spot 0.3 -> 0.6

One more change since the first report: errand tools and boxes are now **priced in capsules**
(PRICES), and the kitchen multiplies instead of adding. The kitchen was tuned to `most` 0.5,
`half` 1 so one cook reaches its cap (it's capped at what the cook would add on a real job, so
it can't lift errands by much).

**Every number under "Suggested" is a suggestion. Nothing past the picks above was changed.**

## The pretend player

- **steady** (the main run): pulls the lever nonstop and keeps one party out. The party goes
  first where a find is waiting, then where the bit the machine needs is, then somewhere new,
  then where coins are best.
- It answers events carefully and lost **0 pets**. Every other pet works errands. It buys the
  next repair or gate as soon as it can, and anything else that pays back within an hour. It
  spends xp on the cheapest gear. Once the boxes tab opens it buys 50 boxes a minute.
- It never buys room steps, so pets stop at about 525 (the room holds 500).
- **casual**: 1 pull in 4, and it checks in every 5 minutes.
- Not counted: toys (they run on real time), trail pickups, time away. Treats only count with
  `--treats`.

## The curve (steady, median of 5 players)

| minute | what happens |
|---|---|
| 0-1 | first pet, tape, oil, second pet, first trip |
| 3.6 | unstick the flap; the meadow **and the pond** open (the pond was 30 before; range now 4-35) |
| 10 | second chute |
| 16 | **errands** (basket) and the lemonade stand, the same minute |
| 25 | the cart (parties of 3; range 24-143) |
| 44 | the kitchen (coin hunt lv 25; was 19) |
| 46 | new glass, beyond the fence (range 40-81) |
| 51 | trip 10 |
| 61 | the cushion, the well, the orchard, the edge |
| 81 | **the savings jar** (lemonade lv 10; was 23, range now 33-138) |
| 112 | rewire the lights |
| 146 | **better drops**: boxes and toys; 100 pets a minute later |
| 160 | **automation tab**: both jobs, both "teach the others" and the first workers, all in the same minute |
| 168 | run adventures (trip 30), taught and staffed the same minute |
| 191 | trip 40 (parts) |
| 236 | trip 60 (4 players of 5) |
| never in 4 h | **scouting** (savings jar lv 10) |

Gear still comes steadily: boots lv 1 at 8 min, most gear lv 3 by about 2.5 h.

**Casual** (3 players) is much slower than before:
- second chute at 60 min
- errands at 105 (range 80-220)
- kitchen at 113
- new glass at 220
- no lights and no better drops within 4 h

## Coins a minute (steady, average of 5)

| min | lever | errands | trips | your pet's crank | workers |
|---|---|---|---|---|---|
| 30 | 8.8k | 7.8k | 56 | - | - |
| 60 | 527k | 772k | 32 | - | - |
| 90 | 11.3M | 13.4M | 125 | - | - |
| 120 | 29.6M | 7.3B | 253 | 283k | 209k |
| 150 | 71.2M | 14.4B | 262 | 807k | 649k |
| 240 | 124M | 37.1B | 2.1k | 2.4M | 687k |

(120 and 150 already include players who got boxes and automation early, from minute 95 on.)

Rummaging and the passive coin stay at about 7 coins a minute all game.

## What's badly off

1. **Before boxes, errands are a little under target: 0.4-1.5x the lever** (it asked for 1-3x):
   0.9x at minute 30, 1.5x at 60, 0.4x at 80, 1.2x at 90. Errands lag each time the machine
   jumps (new glass, the lights), because tools priced in capsules jump with it. Tweak "C" was
   tried with coin prices. With capsule prices as well, the two nerfs stack.
2. **After better drops, errands earn 100-300x the lever.** Pets go from about 15 to 500 within
   minutes. A crew of 500 works 144x as fast as one pet (crew ^ 0.8). Boxes cost 50 capsules
   (a few million coins), but players have banked 1-80B by then, so the price barely matters.
   Only the room (500) stops the flood.
3. **Automation is still bought the minute it opens** (median 160). The x100 prices assumed
   errands at 1-3x the lever. Players bank about 540B by then, and all of it costs about 3B.
   The income is about right:
   - **your pet's crank: 1-2% of the lever** (1.1% at 150 min, 1.9% at 240), as picked
   - **workers: 0.5-1%**
4. **Scouting never opens in 4 hours, and the savings jar is late** (81 min, was 23). Lemonade lv 10
   now takes 65 minutes after the stand opens, because lemons grow 1.5 and are priced in capsules.
   The jar pays one lump every 30 minutes, so the player's "pays back within an hour" rule
   rarely buys it (2 levels of bigger jar in 4 h).
5. **Bits are still the only gate on the tree.** Coins never waited on a repair. Waiting on bits:
   - new glass: 42 min. The pond now opens at minute 4, but the party chases finds first (the
     cart at 25).
   - the lights: 55 min
   - better drops: 29 min
6. **Casual players see very little in 4 hours.** Errands come at about 105 min, and new glass
   at 220.

## Suggested numbers (not applied)

- **For point 2, pick one:**
  - errands `crew_power` 0.8 -> 0.6 (500 pets = 41x one, not 144x)
  - starter box 50 -> 500 capsules
  - or leave the room as the cap: it already stops the flood at 500
- **For point 3:** once point 2 is fixed, the automation prices can stay. If the flood stays,
  multiply them by the banked coins' growth instead (about x100 again). That's a guess; re-run
  after point 2.
- **For points 1 and 4:**
  - lemons and bigger_jar `grow` 1.5 -> 1.3: they're priced in capsules now, so they drift less
  - scouting at savings jar lv 5 instead of 10
  - noses can stay at 1.5
- **For point 5:** new glass `bits` glass 2 -> 1, as the first report said.
- **The sim itself:** teach it to buy room steps (data/herd.json "room"), so the box flood after
  better drops shows up at its real size.

## Questions for Emilia (the sim's picks until you answer)

1. Errands after better drops: should a huge crew out-earn the lever by miles (it's the idle
   layer), or stay close? The sim assumes close.
2. Boxes when they open: a higher price in capsules, or a lower crew power?
3. Is a casual player (1 pull in 4, checking every 5 min) meant to reach new glass in under
   2 hours? Right now it takes 3.5 hours.
