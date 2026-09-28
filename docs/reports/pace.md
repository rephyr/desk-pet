# Pace report (A1), 2026-09-28

The numbers come from `tools/pace.gd`. It plays pretend players through a fresh game using the
game's real GameState, rules and data, so it can be run again after the merge:

    godot --headless -s tools/pace.gd -- --profile=test-sim --minutes=240 --runs=5
    (--style=casual, --treats, --tweak=jobs/coin_hunt/tools/noses/grow=1.5 to try a number)

**Nothing in data/ was changed.** Every number below is a suggestion.

## The pretend player

- **steady** (the main run): pulls the lever nonstop and keeps one party out. The party goes
  first where a find is waiting, then where the bit the machine needs is, then somewhere new,
  then where coins are best.
- It answers events carefully and lost **0 pets**. Every other pet works errands. It buys the
  next repair or gate as soon as it can, and anything else that pays back within an hour. It
  spends xp on the cheapest gear. Once the boxes tab opens it buys 50 boxes a minute (the sim
  stops at 3000 pets).
- **casual**: 1 pull in 4, and it checks in every 5 minutes.
- Not counted: toys (they run on real time), trail pickups, time away. Treats only count with
  `--treats`.

## The curve (steady, median of 5 players)

| minute | what happens |
|---|---|
| 0-1 | first pet, tape, oil, second pet, first trip |
| 3.5 | unstick the flap; the meadow opens |
| 10 | second chute (in the casual run: 55) |
| 16 | **errands** (basket) and the lemonade stand, both in the same minute |
| 19 / 23 / 75 | kitchen / savings jar / scouting |
| 47 | new glass, beyond the fence (casual: ~200) |
| 58 | the cart (parties of 3) |
| 101 | rewire the lights |
| 132 | **better drops**: boxes, toys, 1000 pets 20 min later |
| 147 | **automation tab**: every job, tool and first worker bought in the same minute |
| 216 | trip 40 (parts) |
| never in 4 h | trip 60 (the adventures job never opens) |

Gear levels come steadily: boots lv 1 at 8 min, most gear lv 3 by about 2.5 h. Gear looks fine.

The casual run is 4-5x slower: new glass at about 200 min, and no better drops within 4 h.

## Coins a minute (steady, average of 5)

| min | lever | errands | trips | your pet's crank | workers |
|---|---|---|---|---|---|
| 30 | 8.2k | 93k | 34 | - | - |
| 60 | 1.7M | 78M | 33 | - | - |
| 100 | 11M | 508M | 201 | - | - |
| 150 | 84M | 1.3T | 216 | 386k | 216k |
| 240 | 100M | 7.3T | 1.5k | 626k | 278k |

Rummaging and the passive coin stay at about 6 and 5 coins a minute all game.

## What's badly off

1. **Errands earn 10-50x the lever from minute 30 on.** The errands note says "well under
   pulling". Two things cause it:
   - **The multipliers stack.** Uncapped +1 capsule a level (noses, lemons), goals x12 on the
     coin hunt and the lemonade stand, +200% speed from paws, x3 from pockets, all multiplied
     together.
   - **Tools cost coins but pay in capsules.** A capsule's value goes x2500 over the tree
     (75 -> 193k), so every tool gets 2500x cheaper as you go.

   The player buys about 140 levels of noses.
2. **Coins aren't a gate anywhere after minute 1.** The whole machine tree costs 5.9M, while
   players hold 1.2B at minute 60. Every repair waited 0 minutes on coins. **Bits are the only
   gate**: new glass waited 44 min on bits, the lights 50, better drops 33.
3. **The pond opens late** (median 30 min, range 3-78). Garden -> pond has a spot chance of 0.3,
   and the pond is the only early place with glass. That's most of the 44 minutes new glass waits.
   tools/machine_pace.gd assumes a bit every 150 s (new glass at 9 min); the real game is about
   5x slower.
4. **Boxes cost 50 coins when they open.** Players have billions by then, so buying is limited
   only by how fast you can click (the sim stops at 3000 pets). With crew ^ 0.8 that turns
   errands into trillions. A box price of 20M didn't stop it either (tried with `--tweak`).
5. **Automation costs nothing when it opens.** Every job, tool and first worker is bought the
   same minute (median 147). Its income is also tiny:
   - your pet's crank makes about 0.5% of the lever
   - about 20 workers make about 0.3%
6. **The adventures job (60 trips) doesn't open in 4 hours.** One party makes about 11 trips an
   hour. With `--treats` (every treat tossed) it's 2.5x faster: trip 60 at about 119 min, better
   drops at 74 min.

## Suggested numbers

### data/automation.json

The lever alone makes about 90M a minute when the tab opens. The prices below are that times a
few minutes, so they only make sense once errands are fixed. Otherwise any price here is paid in
under a second.

| what | now | suggested |
|---|---|---|
| machine job `coins` | 1.5M | 150M |
| machine job `seconds` | 48 | 15 (crank lv 10 then makes about 2% of the lever, more worth it with the stool) |
| crank | 150k x1.35 | 15M x1.35 |
| stool | 1M x1.9 | 100M x1.9 |
| teach the others (machine) | 3M | 400M |
| machine spot | 800k x1.12 | 10M x1.08 (a common worker pays back in about 40 min, ~60-80 spots) |
| grease | 600k x1.4 | 30M x1.4 |
| adventures job | 4M | 300M |
| teach the others (adventures) | 6M | 600M |
| party spot | 2M x1.3 | 150M x1.3 |
| boxes job | 6M | 300M |
| teach the others (boxes) | 8M | 800M |
| table | 1.5M x1.15 | 20M x1.15 |
| cutters | 1.2M x1.4 | 60M x1.4 |

### Everything else

- **unlocks.json** `auto_adventures` trips 60 -> **30** (steady players have about 30 by the
  time the tab opens).
- **adventures.json** garden -> pond `spot` 0.3 -> **0.6**, or new glass `bits` glass 2 -> 1.
- **errands.json**, tried as `--tweak` "C" (3 players):
  - lemons / noses / bigger_jar `grow` -> 1.5
  - paws and sign `speed` 0.08 -> 0.04
  - pockets `big` 0.1 -> 0.05
  - snack `all_speed` 0.05 -> 0.03
  - coin hunt goals x -> 1.25 / 1.25 / 1.5
  - lemonade goals x -> 1.25 / 1.25 / 1.5

  **Result:** before boxes, errands dropped from 10-50x the lever to **1-3x**, and every job
  still opens (kitchen 30 min, jar 35, scouting 61). Capping the tools at 10 levels (tried too)
  stops the coin hunt at lv 23, and the kitchen never opens: keep the goal levels reachable.
- **A code idea for later, if you agree:** price errand tools, and maybe boxes, in capsules
  (the cost times `Machine.coin_value`), the way their pay already is. That fixes the drift in
  point 1 and the box flood in point 4 for good. It would be its own step.
- **boxes.json** starter 50: no single number works while crews pay crew ^ 0.8 (see the
  questions).

## Questions for Emilia (the sim's picks until you answer)

1. Should errands out-earn the lever? Right now they do by miles. The sim assumes "well under",
   as the errands note says.
2. How much should your pet's crank matter? About 1-2% of the lever (the suggestion above), or is
   it only for time away?
3. Boxes when they open: should they cost capsules' worth (a code change), or should pets on
   errands help less at big crews (`crew_power` 0.8 -> 0.6)?
4. The pretend player: is "nonstop lever, no treats, careful answers" the player you have in
   mind? (`--treats` shows the fast bound.)
5. The early game is taken as 4 hours. Toys are left out.
