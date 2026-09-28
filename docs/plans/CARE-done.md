# CARE (care A) done: care as buffs

Plan: docs/plans/CARE.md. Built on lane `care`, not committed yet at the time of writing.

## What was built

- Food and mood only drain while the game is open (`GameState._process`, via `Care.drain`). A frame
  gap over 5 s (`GameState.FRAME_GAP`, the computer slept) drains nothing. `load_game` no longer
  drains anything for time closed.
- The passive coin trickle is gone (live: `COIN_INTERVAL` / `_coin_timer`; offline: the
  `coins += ... / COIN_INTERVAL` line in `load_game`).
- Kitchen offline meals: unchanged code (`Jobs.feed` stops at `meal_upto` 70); since food no longer
  drains while closed, the meals made while away top it up to 70 from where it was saved.
- Buffs: food above 70 (strictly) = "full tummy", coins x1.2; mood above 70 = "happy", luck x1.1.
  Boost parts `{ source: "care", id: "full_tummy" | "happy", x }` appended in
  `GameState.boost_parts` (source "care" added to data/boosts.json "sources" after "kitchen").
  `GameState._check_care()` runs after every drain tick, snack, pat, kitchen meal, the `care` dev
  step and the load; when a buff turns on or off it erases the kept coins and luck totals and
  emits `changed` (not while loading).
- Snacks cost capsules: `GameState.snack_price()` = `Care.snack_price` = round(snack.capsules x
  `Machine.coin_value`), at least 1. Feeding is refused at food >= 99 or when you can't pay.
  The feed button reads "feed <price>" with the coin icon and updates on `changed` (a machine
  upgrade emits it).
- New games (and `debug_new_game`) start at food 70 / mood 70 (was 80): on the tick, no buff until
  you feed or pat, so the tutorial pacing is unchanged.
- Bars: `UiTheme.bar(color, tick)` draws a small light tick at 70; `UiTheme.light_bar(bar, lit, tip)`
  gives a brighter fill and a tiny gold sparkle with a dark rim at the fill's end, and the buff's
  name as tooltip ("full tummy", "happy"), no numbers. `HomeTab.show_care(food, mood)` drives both
  the home card and the corner panel (`CompactView`).
- Guilt check: data/voice.json, data/tutorial.json, desktop_pet.gd, pet_view.gd, postcard.gd,
  pet_bubble.gd and spine.gd have nothing about hunger, sadness or loneliness; no art reads food or
  mood. Nothing to remove. The kitchen's "hungry pets cook best!" is about the `hungry` trait (kept).
  The floor stays at 20, so bars never look empty.

## Files

- new: `data/care.json`, `scripts/pets/care.gd` (static `Care`: `floor_value`, `tick`, `drain`,
  `buff_of`, `on`, `on_ids`, `parts`, `snack_price`), `tests/flows/care.flow`
- `scripts/core/catalog.gd` (`catalog.care`)
- `scripts/game_state.gd` (removed `STAT_FLOOR`, `HUNGER_DECAY`, `HAPPY_DECAY`, `COIN_INTERVAL`,
  `FEED_COST`, `_coin_timer`; added `FRAME_GAP`, `_care_on`, `snack_price`, `set_care`,
  `_check_care`; `feed`/`pat` read care.json; `boost_parts` adds `Care.parts`; load drain removed)
- `scripts/ui/ui_theme.gd` (`bar(color, tick)`, `light_bar`, `_bar_marks`)
- `scripts/ui/home_tab.gd` (`feed_text`, `show_care`), `scripts/ui/compact_view.gd`
- `scripts/dev/dev_driver.gd` (step `care <food> <mood>`)
- `data/boosts.json` (source "care", note), `tools/balance.gd` (kitchen line reads care.json),
  `README.md` (care / earn lines), `docs/design.md`, `docs/architecture.md`
- `tests/test_core.gd` (`_test_care`)

## Data shape (data/care.json)

```json
{ "floor": 20, "drain_hours": { "food": 4, "mood": 6 },
  "buffs": [
    { "id": "full_tummy", "name": "full tummy", "stat": "food", "above": 70, "kind": "coins", "x": 1.2 },
    { "id": "happy", "name": "happy", "stat": "mood", "above": 70, "kind": "luck", "x": 1.1 } ],
  "snack": { "capsules": 3, "food": 30, "mood": 5 }, "pat": 8, "tick": 70 }
```

## Save

No new fields, **no SAVE_VERSION bump** (still 24 on this lane). Old saves load their food and mood
as saved (the test saves sit at 79.9, so flows from them start with a full tummy and happy).

## Checks

- `godot --headless -s tests/test_core.gd`: ALL PASSED (3732 checks).
- `godot --headless -s tools/balance.gd`: runs; kitchen line now "food an hour vs 25 an hour lost to
  hunger while open, meals stop at 70 (full tummy above 70)".
- Flows passed: care (new), fits, knacks, book, errands, errand_jobs, errand_tools, machine, rummage.

## Dev step

`care <food> <mood>`: sets both (clamped floor..100) and runs `_check_care()`.

## Text to add

### docs/design.md (already edited in this lane)

Care section: the old "well fed = +50% coins for 2 hours" line is replaced by the built rules
(freeze while closed, full tummy / happy, tick at 70, snack price, pats). Economy: "no passive
trickle any more". Kitchen: note that 70 is the full tummy line and meals top up from the saved value.

### docs/architecture.md (already edited in this lane)

A `Care` bullet after `Book`, and `Care.parts` in the `boost_parts` source list.

### docs/dev-plan.md

Mark "care A: care as buffs" done (2026-09-29): food/mood freeze while closed, full tummy (coins
x1.2) / happy (luck x1.1) above 70 as `care` boost parts, kitchen keeps 70, snacks 3 capsules x
coin_value, coin trickle removed. data/care.json, scripts/pets/care.gd, flow care. No save bump.

### CLAUDE.md "where we left off"

- Care A (2026-09-29): food and mood only drain while the game is open (frame gaps over 5 s and
  time closed drain nothing); above 70 food = "full tummy" coins x1.2, above 70 mood = "happy" luck
  x1.1, boost parts of source `care` (data/care.json, scripts/pets/care.gd `Care`,
  GameState._check_care / snack_price / set_care). The bars have a tick at 70 (the kitchen's line)
  and light up with a sparkle above it (UiTheme.bar(color, tick), light_bar, HomeTab.show_care).
  Snack = 3 capsules x Machine.coin_value. The passive coin trickle is gone (live and offline). New
  games start at 70/70. No save bump. Dev step `care <food> <mood>`; flow care.

## Questions for Emilia (smallest safe option picked)

- Pats are free and unlimited (+8 mood each), so "happy" is always a few taps away. Keep, or add a
  pat cooldown / smaller pats?
- The buff tooltip shows only the name ("full tummy"), not "x1.2" (the receipt will show numbers). OK?
- A snack costs 3 capsules (3 coins at the start, like the old "feed 3"). OK?
- New games now start at food 70 / mood 70 (was 80) so there's no buff until you feed or pat, and
  the tutorial pacing stays the same. OK, or start above the line?
- Since food no longer drains while closed, a pet you left fed stays fed, so errands' offline coins
  are x1.2 too. Intended?
