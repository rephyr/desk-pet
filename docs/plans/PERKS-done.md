# PERKS done: the wisps perk tree on the well wall

Built from docs/picks.md (Brainstorm 3 "wisps" perks + Look picks round 3) and lanes/mockups2
`well-additions.html` Look A (on the walls). Plan: docs/plans/PERKS.md.

## What was built

- Coral things on nails down the left lane of the well's soil (x 40), one per landing, joined by a
  coral thread: solid into a thing that's bought, dashed chalk into one that isn't; from the last
  nail on to the 2 tips. The bow hangs on the well's left roof post: the entrance, the first buy.
- A chain: a link can be bought once the one above has at least 1 level. Unbought = dashed outline,
  the next buyable one a bit brighter. Nails deeper than `dungeon.deep` stay fully hidden (and the
  thread to them). The thimble and the ribbon also wait for feature:plushie.
- Tap a nail: its card takes the "last time" slot under the orders card (name + ✕, the thing big
  on its nail, level pips or a tip's "lv N", what it does now → next as a number, "hang it up" /
  "one more" with a lantern + wisps price, disabled when short, "all done!" at max, no button while
  the one above isn't bought). ✕ brings "last time" back. The picked nail gets a dashed pink ring
  and the well scrolls it into view; a buy wiggles the thing on its nail.
- Once every link has a level, the lucky coin (coins) and the rattle (pets/sec) hang at the bottom
  (the well scrolls to them the moment they appear): endless, +4% a level, price x3 a level, capped.
- Only wisps buy perks; nothing in data/perks.json has a coin price.
- Voice: `perk_hang`, `perk_entrance`, `perk_tip` (buys), `perk_nail` (a run showed a new nail).
- The music box: on load, if your pet leads the army, it finishes the run that was out and sends the
  same army again back to back from the save time for up to its hours (real runs: losses, firsts),
  at most `away_runs_max` runs (data/perks.json, 500), each worked out quietly (no signals, save,
  refold or unlock check per run; those happen once after); a save with no saved_at plays nothing; wisps go into the idle log ("while you were busy: ... N wisps!") and the dungeon
  news. 0 h (no music box) = the old behaviour.

## The chain (data/perks.json; every number a placeholder)

| # | id | name | floor | does |
|---|---|---|---|---|
| 0 | entrance | the entrance (bow) | 0 | count `entrance`: dungeon.json entrance.start (300) + 0 / 300 / 900 / 2.1k / 4.5k = 300 .. 4.8k |
| 1 | flag | the little flag | 3 | kind `front` x1.2 .. x2 |
| 2 | bell | the dinner bell | 6 | kind `herd_power` x1.15 .. x1.45 (everyone walking behind) |
| 3 | spool | the spool | 10 | kind `lanterns` x1.25 .. x2.5 (well + sewing room pay) |
| 4 | nightlight | the nightlight | 13 | kind `cellar` x1.3 .. x2 |
| 5 | lunchbox | the lunchbox | 17 | kind `pets` x1.25 .. x2 (box opening) |
| 6 | scarf | the woolly scarf | 20 | kind `stairs` x1.3 .. x2 (stairs + sewing rooms) |
| 7 | pinwheel | the pinwheel | 24 | count `front_row`: dungeon.json front_row (20) + 0 / 2 / 4 cards |
| 8 | musicbox | the music box | 28 | count `away_hours`: 0 / 1 / 2 / 4 / 8 h |
| 9 | star | the paper star | 33 | kind `power` x1.25 / x1.5 (shared with knacks) |
| 10 | thimble | the thimble | 36 | count `holds`: +1 / +2 (needs feature:plushie) |
| 11 | ribbon | the ribbon | 40 | count `nudges`: +1 / +2 per pet that hops in (needs feature:plushie) |
| tip | coin | the lucky coin | bottom | kind `coins`, +4% a level, 20k x 3^level |
| tip | rattle | the rattle | bottom | kind `pets`, +4% a level, 20k x 3^level |

Data shape: `{ chain: [{ id, name, thing, floor, what, fmt (num|x|cards|hours|plus), kind | count,
needs?, steps: [value at level 0..max], price: [next level's price] }], tips: [{ id, name, thing,
what, kind, each, base, grow }], away_runs_max, price_max }`. A count link's steps are ADDED to the
count's base (`Perks.count_base`: entrance / front_row from data/dungeon.json `entrance.start` /
`front_row`, the rest 0), so each number lives in one file; the nail card shows the whole count
(`Perks.card_value`). The SVG art of the things is UI (`PerkNail.THINGS`,
the mockup's paths + a new thimble and ribbon).

## Files

- New: `data/perks.json`, `scripts/dungeon/perks.gd` (`Perks`, pure rules), `scripts/ui/perk_nail.gd`
  (`PerkNail`), `tests/flows/perks.flow`, this file.
- `scripts/core/catalog.gd` (loads perks.json), `data/boosts.json` (source `perks`; kinds `front`,
  `herd_power`, `cellar`, `stairs`, `lanterns`, `pets`), `data/voice.json` (4 lines), `data/dungeon.json`
  (note).
- `scripts/dungeon/dungeon.gd`: `entrance(catalog, level)` = `Perks.count_at("entrance", level)`; army
  extras `front_n`, `front_x`, `behind_x`, `band_x` ({ rope | doors | stairs | room: x }) in `_power`
  (`band_kind(kind)`), `front_n(catalog, army)`, `pay(..., pay_x)`, orders `pay_x`; the `entrance`
  field left the dungeon state. `scripts/dungeon/sewing.gd`: `pay(..., boost)`, orders `pay_x`.
- `scripts/machine/plushie.gd`: `holds_max / can_hold / toggle_hold(..., extra := 0)`,
  `next_pet(..., extra_nudges := 0)`. `scripts/ui/plushie_machine.gd` passes `GameState.perk_holds()`.
- `scripts/game_state.gd`: `perks`, `perk_level`, `perks_shown`,
  `perk_price`, `perk_available`, `buy_perk`, `debug_perk`, `perk_count`, `front_row_size`,
  `perk_holds`, `perk_nudges`, `perk_away_hours`, `_army_while_away` (quiet runs: `send_army(quiet)`,
  `_finish_dungeon_run(quiet)`, `_finish_room_run(quiet)`, `_home_again()` once after);
  `boost_parts` + `Perks.parts`; `_army_rules` fills the army extras; `send_army` / `send_to_room`
  pass `pay_x`; `boost("pets")` in `_open_in_background` and the workers' box tables; dungeon news
  `nail`; save/load/migration.
- `scripts/ui/pack_job.gd` (pets boost on its rest), `scripts/adventure/pet_voice.gd` (wisps in the
  idle summary).
- `scripts/ui/well_column.gd`: nails, thread, tips, `nail_pressed(id)`, `set_picked`, `nail`, `pop`,
  `nail_at`; the well's middle moved to 0.55 of the column; pebbles skip the lane.
- `scripts/ui/dungeon_view.gd`: well panel 224 -> 236, page gaps 12 -> 10, picker h gap 6 -> 5,
  `pick_nail`, `_drop_nail` (clears the card and the nail's ring when the tab comes back, the sewing
  room opens or the nail stops showing), `_nail_card`, `_show_nail`, perk voice; FrontRow's front_n from `front_row_size()`.
  `scripts/ui/front_row.gd`: GAP.x 4 -> 3 (so the wider well fits; FrontRow grows a 4th row with
  the pinwheel and still fits).
- `tests/test_core.gd`: `_test_perks`, `_test_perks_game`, the save chain check now says v28.
- `tools/balance.gd`: a perks table (prices, the first army deep enough, hours of its runs).
- `docs/design.md` (perk tree bullet in the old well section), `docs/architecture.md` (v28 paragraph).

## Save bump

v27 -> **v28** (renumber at the merge). New top-level `perks: { id: level }` (only levels > 0; links
clamped to their max, tips any level, unknown ids dropped). Migration `version < 28`: a
`dungeon.entrance` > 0 moves to `perks.entrance`, and `dungeon.entrance` is dropped.

## Dev steps

`perk <id> [level]` (for free), `buy-perk <id>` (the real buy with wisps), `click PerkNail#n` (n in
top-left-first order: the bow is 1, then down the lane, tips last). `wisps`, `deep`, `boosts` (logs
the perks' parts) already existed.

## Checks

- `godot --headless -s tests/test_core.gd -- --profile=test-sewing`: ALL PASSED (4173 checks).
- `godot --headless -s tools/balance.gd -- --profile=test-sewing`: runs, perks table printed (the
  whole chain is ~100 h of runs at the table's armies, no perks counted in).
- Flows: perks (new, 15 shots; also checks the pinwheel card reads "22 cards → 24 cards" and that
  the card and its ring are gone after leaving the tab and coming back, `expect fits` on every screen), fits, dungeon, sewing, plushie,
  automation, workers: all PASSED. The dungeon flow's card picker needed its gap trimmed by 1 px.

## Text to add

**docs/dev-plan.md** (the PERKS step): "Done (lane sewing, PERKS): the wisps perk tree on the well
wall, Look A. 12 links on nails down the left lane (the bow = the entrance first) + 2 endless tips
(the lucky coin, the rattle), a chain, hidden below the deepest floor, the thimble and ribbon wait for
the plushie machine. data/perks.json, Perks, PerkNail, save v28 (renumber), flow perks."

**CLAUDE.md "where we left off"**:
"- PERKS (lane sewing): the wisps perk tree on the well wall (well-additions Look A): coral things on
  nails down the left lane of the dungeon column, joined by a coral thread (solid to the last bought,
  dashed after); the bow on the roof post = the entrance (first buy); a chain (each needs the one
  above); nails below the deepest floor stay hidden; tap one = its card where 'last time' sits.
  data/perks.json (entrance, little flag, dinner bell, spool, nightlight, lunchbox, woolly scarf,
  pinwheel, music box, paper star, thimble + ribbon hidden until the plushie machine; tips lucky coin
  + rattle once the chain is done), scripts/dungeon/perks.gd (Perks), scripts/ui/perk_nail.gd
  (PerkNail), GameState.perks / buy_perk / perks_shown / front_row_size / perk_holds / perk_nudges,
  boost source 'perks' (kinds front, herd_power, cellar, stairs, lanterns, pets), the music box runs
  the army while away (_army_while_away). Save v28 (perks; dungeon.entrance moved in). Dev steps
  perk / buy-perk / click PerkNail#n. Flow: perks."

**docs/design.md / docs/architecture.md**: already edited in this lane (see Files).

## Questions for Emilia (smallest safe pick meanwhile)

1. "The chain is done" (the tips show) = every link bought once, not maxed. OK?
2. The plushie perks (thimble, ribbon) are the last links, so the tips also wait for the plushie
   machine. OK, or a side branch?
3. The music box runs real army runs while you're away (pets can be lost, floor firsts can happen),
   not "wisps at the last run's rate with no losses". OK?
4. The sewing rooms count as "the stairs" for the woolly scarf. OK?
5. Changed from the mockup: the lunchbox is pets/sec (mockup: "rare ones"), the music box is hours
   away (mockup: "wisps from 20 down"), the paper star is army power (mockup: the stairs again), the
   spool is lanterns. The thimble and the ribbon (names + drawings) are new.
6. The bow shows as soon as the dungeon page is there. OK?
7. The B2 receipt isn't on this branch yet: the perks give boost parts with source "perks", so they
   show on it once it's merged (coins and power are the shared kinds; front/herd/cellar/stairs/
   lanterns/pets are perks-only kinds and could stay off the receipt).
8. The tips' price grows x3 a level from 20k (the balance table: lv 6 = 14.6M). Too steep to feel
   endless, or right as a sink?
