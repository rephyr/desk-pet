# PERKS plan: the wisps perk tree on the well wall

From docs/picks.md (Brainstorm 3 "wisps" + "Look picks, round 3" well additions) and the mockup
lanes/mockups2 `well-additions.html` Look A (things on nails down the left soil lane). All numbers
are placeholders in data.

## What it is

- Coral things hang on nails down the left lane of the well column, one nail on a landing each,
  joined by a coral thread: solid down to the last one bought, dashed chalk after.
- The top nail is the bow on the well's roof post = the entrance (the first buy).
- A chain: a thing can be bought once the one above has at least 1 level. Unbought = dashed
  outline (the next buyable one a bit brighter). Nails below `dungeon.deep` stay fully hidden,
  and so do the thread bits to them.
- Tap a nail: its card takes the "last time" slot under the orders card (✕ puts last time back).
- The 2 endless tips hang at the bottom of the column once every chain link has at least 1 level.
- Only wisps buy perks. Nothing here has a coin price.

## The chain (data/perks.json)

| # | id | name | thing | floor | does | levels |
|---|---|---|---|---|---|---|
| 0 | entrance | the entrance | bow (roof post) | 0 | fits 300 / 600 / 1.2k / 2.4k / 4.8k | 4 |
| 1 | flag | the little flag | flag | 3 | front row power x1.2 .. x2 (kind `front`) | 5 |
| 2 | bell | the dinner bell | bell | 6 | herd pets' power x1.15 .. x1.45 (kind `herd_power`) | 3 |
| 3 | spool | the spool | spool | 10 | lanterns (dungeon + sewing room pay) x1.25 .. x2.5 (kind `lanterns`) | 5 |
| 4 | nightlight | the nightlight | moon | 13 | power in the cellar x1.3 .. x2 (kind `cellar`) | 3 |
| 5 | lunchbox | the lunchbox | lunch | 17 | pets/sec: box opening x1.25 .. x2 (kind `pets`) | 3 |
| 6 | scarf | the woolly scarf | scarf | 20 | power on the stairs + sewing rooms x1.3 .. x2 (kind `stairs`) | 3 |
| 7 | pinwheel | the pinwheel | pinwheel | 24 | front row 20 / 22 / 24 cards (count) | 2 |
| 8 | musicbox | the music box | musicbox | 28 | while you're away, wisps only: 0 / 1 / 2 / 4 / 8 h (count) | 4 |
| 9 | star | the paper star | star | 33 | army power x1.25 / x1.5 (kind `power`, shared with knacks) | 2 |
| 10 | thimble | the thimble | thimble | 36 | plushie holds +1 / +2 (count; hidden until feature:plushie) | 2 |
| 11 | ribbon | the ribbon | ribbon | 40 | +1 / +2 nudges per pet that hops in (count; hidden until feature:plushie) | 2 |

Tips (open when the chain is done, endless, +4% a level, price base x 3^level, capped):
lucky coin (coin, kind `coins`), rattle (rattle, kind `pets`).

Plushie perks sit at the chain's end so a hidden link never blocks the ones below it (the machine
opens from the sewing room's last room, ~floor 33 strength).

## Data shape

```json
{ "_note": "...",
  "chain": [
    { "id": "entrance", "name": "the entrance", "thing": "bow", "floor": 0, "what": "fits",
      "count": "entrance", "steps": [300, 600, 1200, 2400, 4800], "price": [100, 600, 1800, 5400] },
    { "id": "flag", "name": "the little flag", "thing": "flag", "floor": 3, "what": "front row",
      "kind": "front", "steps": [1, 1.2, 1.4, 1.6, 1.8, 2], "price": [150, 300, 700, 1500, 3200] },
    { "id": "thimble", "...": "...", "count": "holds", "needs": "feature:plushie", "steps": [0, 1, 2] }
  ],
  "tips": [ { "id": "coin", "name": "the lucky coin", "thing": "coin", "what": "coins", "kind": "coins",
              "each": 0.04, "base": 5000, "grow": 3 }, { "id": "rattle", "...": "pets" } ],
  "price_max": 4000000000000000000 }
```
`steps[level]` is what it does now (index 0 = nothing bought), `price[level]` the next level.
`kind` = a boost kind (multiplier), `count` = a number the game reads instead (entrance,
front_row, holds, nudges, away_hours). `needs` = an unlock id. The SVG art of each thing is UI
(PerkNail.THINGS, paths from the mockup + thimble and ribbon new), not data.

## Code

- **New `scripts/dungeon/perks.gd` (`Perks`, pure):** `level`, `perk`, `shown(catalog, state,
  deep, is_open)`, `available`, `maxed`, `price` (float maths, capped), `value` / `next_value`,
  `chain_done`, `count(catalog, state, name, default)`, `parts(catalog, state, kind)` ->
  `Boosts.part("perks", id, x)` (tips: 1 + each x level), `buy(catalog, state, id, wisps)` -> cost
  or -1, `clean`.
- **data/boosts.json:** source `perks`; new kinds `front` (front row), `herd_power` (the herd),
  `cellar` (in the cellar), `stairs` (on the stairs), `lanterns` (lanterns), `pets` (pets a second).
- **GameState:** `var perks := {}` (id -> level), signal `perks_changed`, `perk_level`,
  `perk_price`, `perk_can_buy`, `buy_perk(id)` (spends wisps, `_boosts_changed()`, emits
  perks_changed + dungeon_changed, saves), `perks_shown()`, `perk_count(name)`.
  `boost_parts` appends `Perks.parts(...)`.
- **Where the numbers land:**
  - entrance: `Dungeon.entrance(catalog, level)` reads the perk's steps (every `dungeon.entrance`
    read becomes `perk_level("entrance")`).
  - front row size: `Dungeon` / `army_best` / `sew_front` / DungeonView / FrontRow read
    `rules.front_n` / `GameState.front_row_size()` (data front_row + pinwheel) instead of the
    data number. FrontRow gets a 4th row past 20 cards (check fits).
  - `_army_rules` adds `front_x` (boost front), `herd_x` (boost herd_power), `band_x { cellar,
    below }` (boost cellar / stairs), `pay_x` (boost lanterns); `Dungeon._power` multiplies front
    cards, herd pets and the floor's band (rooms count as `below`); `pay` x pay_x (also rooms).
  - pets: `_open_in_background` timer, PackJob's rest, and the workers' box tables x boost("pets").
  - holds / nudges: `Plushie.holds_max(..., extra)` (and can_hold / toggle_hold pass it),
    `Plushie.next_pet(..., extra_nudges)`; GameState passes the perk counts; the shop's hold price
    still only counts bought holds.
  - away hours: on load, if your pet leads the army, `_army_while_away(min(closed, hours))`
    finishes the run that was out and sends the same army again back to back (honest runs with
    losses and orders, at most ~500 runs), wisps summed into the idle log and dungeon_news.
    0 h (no music box) = today's behaviour.
- **UI:**
  - `scripts/ui/perk_nail.gd` (`PerkNail`, like SewDoor): nail head, string, the thing as an SVG
    texture (solid coral bought / dashed outline / brighter dashed next), selected ring, a sparkle
    wiggle after a buy, tips show "lv N" under them; `pressed(id)`.
  - `WellColumn`: the well panel grows 224 -> 236 and `cx` moves right (like the mockup's 128/232)
    so the lane (x ~ 18..58) is clear; pebbles skip the lane; thread drawn in `_draw`
    (coral solid / dashed chalk, quadratic like the mockup); the bow nail on the roof post; nails
    at `y(f) - 20`; tips at the column's bottom; `nail_pressed(id)` signal.
  - `DungeonView._build_side`: a picked nail's card instead of "last time": title + ✕, big thing
    (48 px), pips (or "lv N" for tips), effect as "fits 300 → 600" / "front row x1.20 → x1.40",
    button "hang it up" (first) / "one more" with lantern + price, disabled when short, "all
    done!" at max; no button while the one above is unbought. Nothing else (no hint text).
  - voice.json: `perk_hang` ("so pretty! it glows a little!"), `perk_entrance` ("the entrance got
    bigger! everyone fits now!"), `perk_tip` ("another one! it jingles!"), `perk_nail` (a run shows
    a new nail: "ooh, a new nail down here! something could hang on it.").

## Save: v27 -> v28 (renumber at the merge)

Top-level `perks: { id: level }` (only levels > 0). Migration `version < 28`: `perks.entrance =
dungeon.entrance` when it's > 0, then `dungeon.entrance` is dropped (Dungeon.fresh/clean stop
keeping it). Loading keeps only known ids, clamps each to its max; tips any level. The "save chain
ends at v27" test moves to v28.

## Dev steps

`perk <id> [level]` (sets a level for free), `buy-perk <id>` (the real buy, costs wisps),
`click PerkNail#n` taps a nail (n in shown order), `wisps <n>` and `deep <n>` already exist,
`boosts` logs the perks' parts.

## Flow `tests/flows/perks.flow`

From rich, dungeon open, an army: only the bow shows (deep 0) -> `wisps 200`, tap the bow, card
"the entrance", "fits 300 → 600", hang it up -> the entrance meter says / 600 -> `deep 12`: nails
down to floor 10 (flag, bell, spool; nightlight hidden) -> buy the flag, the thread is solid to it,
dashed after -> tap the spool (no button: the bell isn't bought) -> `deep 40` + `perk` the chain
to the star: the thimble and ribbon stay hidden -> `open-plushie`: they show -> buy them -> the
tips show at the bottom, tap the lucky coin, one more -> `boosts` (coins has a perks part) ->
✕ brings last time back. `expect fits` + a shot at every screen (bow, entrance_card, bought,
nails_10, chain, no_plushie, plushie, tips, tip_card). Also re-run fits, dungeon, sewing, plushie,
automation, workers.

## Tests (tests/test_core.gd)

- `_test_perks` (pure): shown by depth and needs, chain availability, prices and the cap, values
  per level, buy spends and refuses (short, locked, maxed), chain_done opens tips, tip price x3
  and +4%, parts per kind, counts, clean clamps.
- `_test_perks_game`: v27 save with `dungeon.entrance` 2 loads as perks.entrance 2 (entrance
  1200); buy_perk spends wisps and changes boost("front") / army power / pay; pinwheel -> army_best
  takes 22; thimble and ribbon change holds_max and nudges; lunchbox + rattle speed box opening;
  the music box: a save closed 2 h ago with your pet leading brings back several runs' wisps and
  losses, 0 h brings one; save round trip; save chain at v28.
- `tools/balance.gd`: a perks table (wisps an hour at a few depths from the dungeon table, hours
  to each buy) so prices can be tuned.

## Questions for Emilia (smallest safe pick meanwhile)

1. "The chain is done" = every link bought at least once (not maxed). OK?
2. The plushie perks (thimble, ribbon) go last in the chain, so the tips wait for the plushie
   machine. OK, or should they be a side branch?
3. The music box: while the game is closed your pet keeps leading the army (real runs, pets can be
   lost) for up to its hours. OK, or pay wisps at the last run's rate with no losses?
4. The sewing rooms count as "the stairs" for the woolly scarf. OK?
5. The lunchbox (mockup: "rare ones") is pets/sec here, so pets/sec is in the chain; the
   mockup's "wisps from 20 down" became the music box's away hours. Names past the mockup
   (thimble, ribbon) and all numbers are placeholders.
6. The bow shows as soon as the dungeon page is there (the entrance is floor 0, always reached).
