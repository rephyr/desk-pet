# Pace report (A1), third run: the balance fixes, 2026-09-29

The numbers come from `tools/pace.gd`: pretend players play a fresh game on the real GameState,
rules and data (save v40):

    godot --headless -s tools/pace.gd -- --profile=test-merge --minutes=240 --runs=5
    (--style=casual, --treats, --tweak=<path>=<value> to try a number,
     --why: errands job by job at the end, --trace: every trip, --pick=finds: the old party picks)

This run applies the fixes the second report asked for, plus the two numbers Emilia wanted the sim
to set (the room price and the pat cooldown). **Every number below is now in data/.**

## What changed, and why

| what | was | now | why |
|---|---|---|---|
| errands `crew_power` | 0.8 | **0.2** | the flood: 500 pets worked 144x one pet. Now 3 pets = 1.25x, 500 = 3.5x |
| teamwork, a level | +0.05 | +0.01 | three levels lifted a crew of 500 by 2.5x |
| coin hunt pay | 5 capsules | **20** | with a weak crew power, early errands sat at 0.3-0.5x the lever |
| lemonade pay | 3 capsules | **12** | same |
| coin hunt goals (lv 25 / 50 / 100) | x1.25 / 1.25 / 1.5 | x1.1 / 1.1 / 1.2 | goals stacked to x2.3 right after boxes |
| lemonade goals (lv 10 / 25 / 50) | x1.25 / 1.25 / 1.5 | x1.1 / 1.1 / 1.2 | same |
| lemonade tips (uncommon..mythic) | 1.5 / 2.5 / 4 / 8 / 15 | 1.15 / 1.3 / 1.5 / 2 / 3 | a crew of box pets averaged x4.9 tips |
| fancy cups | rare tips x2 | x1.5, "rare pets get even bigger tips" | same |
| sweeter lemons `grow` | 1.5 | 1.3 | the report's pick |
| kitchen `most` | 0.5 | 0.3 | the kitchen soaks up the leftover herd; +50% was too much |
| savings jar | 100 capsules, crew power 0.5 | **350**, crew power 0.05 | one pet in the jar still beats one on the coin hunt (a test says so), a crew doesn't |
| a bigger jar | 80 capsules, grow 1.5, +10 | 105, grow 1.3, +90 | the jar's tools pay back within the hour now, so the jar levels up |
| a wider slot | 120 capsules | 160 | same |
| scouting | jar lv 10 | jar lv 10 (kept) | with the jar fixed, lv 10 lands at ~78 min (lv 5 opened it at ~27 min in a trial) |
| new glass | 2 glass | **1 glass** | the report's pick |
| automation prices | | **x5, all of them** | teaching now takes 2-12 minutes of income (the whistle's tools too) |
| room steps | 500 / 900 / 1620 / 2920 capsules | **12500 / 17500 / 30000 / 40000** | about a sunny box per new bed (was about 2 beds a box) |
| pat cooldown | 30 s | **300 s** | see "the room and pats" |

Tests and flows that checked the old numbers were updated (test_core: the find's worth, the goals,
the gentle trickle, the jar prices, the first room step; flows: errand_tools, errand_jobs, house).

**The sim changed too** (so the curve isn't comparable minute for minute with the second report):
- It buys room steps when the new beds pay back within the hour, counting their boxes.
- Pats run on the sim's clock with the real cooldown.
- Where the party goes: one look at a place where something new could be, then the bit the next
  repair needs, then finds, then other bits. Before, it knew where every find was and chased the
  cart first (a solo casual trip takes 20-25 minutes, so that cost casual players an hour).
  `--pick=finds` brings back the old way.
- It sends a party after the check-in's buys, and casual players follow the tutorial through.

## The curve (steady, median of 5 players)

| minute | what happens |
|---|---|
| 0-1 | first pet, tape, oil, second pet, first trip |
| 3.6 | unstick the flap; the meadow and the pond |
| 10 | second chute |
| 16 | **errands** (basket) and the lemonade stand |
| 22-23 | the savings jar, the kitchen |
| 25 | the cart |
| **31** | **new glass**, beyond the fence (was 46; range 22-36) |
| 45-54 | the cushion, orchard, well, the edge |
| 64 | wheelbarrow, piggy bank |
| 73 | rewire the lights (was 112) |
| **78** | **scouting** (was never; range 43-133) |
| 79 | hay wagon |
| **113** | **better drops**: boxes and toys (was 147; range 105-120) |
| 124 | **automation tab** (tiny machine) |
| 127-128 | taught the machine, crank lv 3 |
| 131-140 | sunset globe home, nest shooed out, teach the others, first worker |
| 160-167 | run adventures, its workers |
| 173 | teach the others to open boxes |
| 190 | trip 40 (parts) |
| ~155 | the room is full (500) |
| 217 | first room step (4 players of 5), bunk beds at 235 (3 of 5) |
| 238 | trip 60 |

Pets: 10 at 63 min, 100 at 115, ~520 from 160 on (the room), 820 at 4 h. Nobody lost a pet.

**Automation waits** (after it shows up): teach the machine 2.5 min, crank levels under a minute,
teach the others 12 min, teach boxes 8 min, teach adventures 4 min, teach the others adventures
7 min, teach the others boxes 36 min. It's no longer all bought in the same minute.

## Coins a minute (steady, average of 5)

| min | lever | errands | errands / lever | pet crank | workers | trips |
|---|---|---|---|---|---|---|
| 30 | 13.9k | 8.5k | 0.6 | - | - | 26 |
| 60 | 723k | 1.2M | 1.7 | - | - | 97 |
| 90 | 20.9M | 19.8M | 0.9 | - | - | 322 |
| 100 | 34.9M | 19.6M | 0.6 | - | - | 561 |
| 120 | 75.6M | 125M | 1.7 | - | - | 450 |
| 150 | 111M | 237M | 2.1 | 1.9M | 7.8M | 488 |
| 180 | 119M | 315M | 2.6 | 1.7M | 20.6M | 1.4k |
| 210 | 115M | 332M | 2.9 | 2.2M | 43.4M | 883 |
| 240 | 120M | 384M | 3.2 | 1.8M | 51.7M | 1.6k |

(Was: 100-300x after better drops.) By job at 4 h: coin hunt 162M, lemonade 148M, the jar 75M.
Your pet's crank stays at 1.5-2% of the lever, as picked. Rummaging stays at ~7 a minute.

Spent per player in 4 h: errand tools 20.8B, automation 24.6B, boxes 4.8B, room 4.0B.

## Casual (1 pull in 4, checks in every 5 minutes; 15 players)

| minute | what happens |
|---|---|
| 3 | tutorial done (was 15: it now follows the tutorial through) |
| 23 | unstick the flap, the pond |
| 43 | errands, second chute (was 105) |
| 73 / 83 | the jar, the kitchen |
| **98** | **new glass** (was 220; range 68-158) |
| 171 | scouting (10 players of 15) |
| 188 | the lights (10 of 15) |

Casual errands earn 2-5x their (slow) lever. No casual player reaches better drops in 4 h.

## The room and pats

- **Room:** 12500 / 17500 / 30000 / 40000 capsules, about a sunny box (50) per new bed. Steady
  players fill the 500 around 2.5 h and buy the plank at ~3.5 h. At the old price the room never
  held anyone back (1.1B spent on it while banking trillions). The wisp steps stay as they were.
- **Pat cooldown: 300 s, no daily cap.** Mood drops 17 an hour, so a pat every half hour keeps the
  happy buff on. Both styles were happy 100% of the time with 9 pats in 4 h, whatever the
  cooldown under 30 min. The cooldown only sets how quickly a low mood comes back: from the floor
  to happy is 7 pats, 35 minutes at 300 s (3.5 minutes of clicking at 30 s). A daily cap would
  punish long sessions, and mood never drops while the game is closed anyway.

## What's still off

1. **Errands dip to ~0.6x right after the lights** (minutes 90-110): fever pays the lever only.
   They're also under 1x for the first 20 minutes after the basket, while there are 2-3 pets.
2. **Errands creep up with the herd:** 3.2x at 4 h with ~820 pets. A crew grows as crew^0.21, so
   a room of thousands (the wisp steps) will push them past 3x. Worth a re-run when wisps open.
3. **Workers reach ~40% of the lever by 4 h** (about 32 machine spots a player). Fine as the idle
   layer, or spot prices go up if they should stay small.
4. **Scouting's timing hangs on the jar's tools** paying back within the hour: steady 78 min, but
   43-133. Casual players get it at ~2 h 50, and 5 of 15 not at all.
5. **Casual trips are slow:** a solo pet waits at every stop until the next check-in, so a trip
   takes 20-25 minutes and casual players make ~12 trips in 4 h. Only 2 of 15 find the cart. This
   is the biggest thing between casual players and the lights.
6. **Bits are still the only tree gate**: coins never wait (new glass 27 min on bits, the lights
   42, better drops 43).
7. Not counted: toys, trail pickups, time away (treats only with `--treats`).
