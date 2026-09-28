# CARE (care A): care as buffs

From docs/picks.md "Brainstorm 3 picks", care A. Build plan, short.

## What changes

1. **Freeze while closed.** `load_game` stops draining food and mood for time away. `_process`
   still drains while the game runs (full game, corner panel or pet out on the desktop). A frame
   gap over 5 s (the computer slept) counts as closed: no drain, like the errands already do.
2. **No coin trickle.** Remove `COIN_INTERVAL`, `_coin_timer` and the +1 coin every 10 s in
   `_process`, and the offline `coins += ...` line in `load_game`. Coins come from the machine,
   errands, adventures and rummaging.
3. **Kitchen offline meals.** No drain while closed any more, so the errands catch-up meals only
   top food/mood up to 70 from wherever they were saved (`Jobs.feed` already never goes past
   `meal_upto`). Only the comment and order note in `load_game` change.
4. **Buffs.** Food above 70 = "full tummy": coins x1.2. Mood above 70 = "happy": luck x1.1.
   Strictly above, so the kitchen (up to 70) never gives them by itself. Snacks (and pats for
   mood) do.
   - New boost source `care` (data/boosts.json `sources` gets "care" after "kitchen"). Parts
     `{ source: "care", id: "full_tummy", x: 1.2 }` on `coins`, `{ source: "care", id: "happy",
     x: 1.1 }` on `luck`. The B2 receipt will print them from their names in data/care.json.
   - Cache: `boost()` caches totals, so GameState keeps `_care_on := [full, happy]`. After every
     drain tick, snack, pat and kitchen meal, `_check_care()` compares; on a flip it erases
     `_boosts["coins"]` and `_boosts["luck"]` and emits `changed`.
5. **Snacks cost capsules.** Feed price = `care.snack.capsules` x `Machine.coin_value` (rounded,
   at least 1). The button keeps its word "feed", shows the price with the coin icon
   (`UiTheme.num`) and updates as the machine grows. Refuses when food >= 99 or you can't pay.
6. **Empty bowl = no bonus.** The floor stays at 20 (bars never empty). Guilt check done so far:
   data/voice.json has no hungry/sad/lonely lines, no pet art reads food or mood, the tutorial
   says nothing. I re-check desktop_pet.gd, pet_view.gd and the postcard while building, and
   remove anything found. The kitchen's "hungry pets cook best!" is about the `hungry` trait:
   kept.

## Data: data/care.json (new, loaded by Catalog as `catalog.care`)

```json
{
  "_note": "...",
  "floor": 20,
  "drain_hours": { "food": 4, "mood": 6 },
  "buffs": [
    { "id": "full_tummy", "name": "full tummy", "stat": "food", "above": 70, "kind": "coins", "x": 1.2 },
    { "id": "happy", "name": "happy", "stat": "mood", "above": 70, "kind": "luck", "x": 1.1 }
  ],
  "snack": { "capsules": 3, "food": 30, "mood": 5 },
  "pat": 8,
  "tick": 70
}
```

`STAT_FLOOR`, `HUNGER_DECAY`, `HAPPY_DECAY`, `FEED_COST` in game_state.gd go away and read from
this. errands.json kitchen `meal_upto` stays 70 (a test keeps it <= the full tummy line).

## Code

- `scripts/pets/care.gd` (new, `class_name Care`, static, no state): `parts(catalog, food, mood,
  kind)`, `snack_price(catalog, machine_state)`, `drain(catalog, food, mood, seconds)` ->
  `{food, mood}`, `on(catalog, food, mood)` -> which buffs are on.
- `scripts/core/catalog.gd`: `var care`, `_load("care.json")`.
- `scripts/game_state.gd`: `_process` drain via Care (skip gaps > 5 s), trickle removed,
  `boost_parts` appends `Care.parts`, `_check_care()`, `feed()` pays `snack_price`, `pat()` reads
  `care.pat`, `load_game` drops the away drain and the away coins, `snack_price()` helper for
  the UI.
- `scripts/ui/ui_theme.gd`: `bar(color, tick := -1.0)` draws a small tick at that value (a thin
  2 px mark in the seam colour over the bar). Home card and corner panel pass `care.tick`.
- `scripts/ui/home_tab.gd`, `scripts/ui/compact_view.gd`: feed price from `snack_price()`,
  ticks on both bars. Above the line the bar's fill gets a brighter tone and a tiny sparkle at
  its right end (no text); the bar's tooltip is the buff's name ("full tummy", "happy"), no
  numbers (the receipt shows those later).
- `data/boosts.json` note, `tools/balance.gd` kitchen line (reads care.json drain), README
  "coins trickle in" line, docs/design.md Care + Economy lines.

## UI sketch (home card, 200 px wide, same size as now)

```
 Mochi
 opening a box
 food  [#########|##   ]*     <- tick at 70, sparkle when above
 mood  [#######  |     ]
 [ feed 3 (coin) ] [ pat ]
```

## Save

No new fields (hunger/happiness are already saved). **No SAVE_VERSION bump.**

## Dev step + flow

- Dev step `care <food> <mood>`: sets both (clamped floor..100), runs `_check_care()`.
- `tests/flows/care.flow`: from after_tutorial, view full, tab home, expect fits, `care 40 40`,
  shot plain, `boosts` (no care parts), `coins 100`, click feed*, shot fed (food 70, below the
  tick), click feed*, shot full (above the tick, sparkle), `care 90 90`, `boosts` (log has
  care full_tummy x1.200 and care happy x1.100), view compact, shot corner, expect fits.

## Tests (tests/test_core.gd, `_test_care`)

- Care.parts: food 71 gives coins x1.2, food 70 gives none, mood 71 gives luck x1.1, other
  kinds get nothing; every buff's kind is a boost kind and "care" is a source.
- GameState: boost("coins") goes up when food crosses 70 and back down when it drains under
  (cache cleared); feed spends 3 x coin_value and raises food; refuses when full or broke;
  price follows a bigger coin_value.
- No trickle: `_process(60)` with no errands leaves coins alone; a 10 s frame gap drains nothing.
- Load: a save an hour old with food 90 / mood 90 loads with 90 / 90 and no extra coins.
- Kitchen `meal_upto` <= the full tummy line (the kitchen alone never gives the buff).
- balance.gd still runs.

## Questions for Emilia (smallest safe pick taken)

- Pats are free and unlimited (+8 mood), so "happy" is 4 taps away any time. Kept as is; a pat
  cooldown or smaller pats later?
- Buff tooltip shows only the name, no "x1.2" (the receipt will). OK?
- Snack price 3 capsules (3 coins at the start, like the old feed 3).
