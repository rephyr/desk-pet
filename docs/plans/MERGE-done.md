# MERGE done: lanes/plushie (F1) + lanes/c1-c3 (C3) into the sewing lane (E1 dungeon)

One branch now has the E1 dungeon (on the herd + knacks), the F1 plushie machine and C3 new homes +
the sorting rule, working together. E3 can open the plushie machine (`find:plushie_machine`, its
`given_by` note in data/unlocks.json) and add keep lines to the sorting rule.

1. `git merge --no-ff lanes/plushie` (committed: "merge the plushie machine into the sewing lane")
2. `git merge --no-ff lanes/c1-c3` (resolved and staged, commit pending)

## Save chain

All three lanes bumped 23 -> 24. One chain now, SAVE_VERSION = 26:

| version | what | code |
|---|---|---|
| v24 | E1 dungeon: `dungeon`, `wisps`; the well line becomes bands, rumours/parties about bands move | `migrate` `if version < 24` (unchanged) |
| v25 | F1 plushie: `plushie`, pet `buttons`, bag keys `slot:id@n` (wisps is the same field as v24's) | none needed: old saves load an empty machine (comments in game_state.gd / pet.gd say v25) |
| v26 | C3 new homes: `new_homes`, per-job `join` + `automation.wjoin` (from `jobs_auto`), a full room opens the stall | `load_game`: both `from_version < 24` checks became `< 26` |

`wisps` is ONE save field (both lanes added it for the same currency): read once in `load_game`,
saved once. The dungeon pays it through `grant_wisps`, plushie misses puff it, the plushie shop
spends it. v24 saves from any single lane only ever lived in test profiles (main is also at 24):
the final merge to main renumbers again (this merge's v24/v25/v26 become main+1..main+3).

## Conflicts and how they were kept

Plushie merge: themes.json `wisp` (kept the dungeon lane's near-identical colours), unlocks.json
(note text gets `floor`, `learns`, `button_gift`, `given_by`; unlocks dungeon, lead_army, plushie;
finds deep_rope, little_key, plushie_machine), catalog.gd (`dungeon` + `plushie`), ui_theme.gd (one
WISP), game_state.gd (all signals; unlock apply does `learns` AND `button_gift`; both sections;
`_dungeon_first` kept; one `wisps` var/save key/load line), dev_driver.gd (both step sets, one
`wisps` step: the dungeon's, which also emits dungeon_changed), test_core.gd (both suites; the
"something gives this find" check accepts machine / dungeon floor / `given_by`; the knack test keeps
the dungeon gate and the buttons check).

c1-c3 merge: unlocks.json (note gets C3's new_homes/sorting/room/homes_by_hand/quiet text; unlocks
new_homes + sorting added), architecture.md (both sections, renumbered), catalog.gd (+ `new_homes`),
dev_driver.gd (union), game_state.gd (signal `homes_paid`; the active pet swap keeps "your active
pet leads the army, it isn't in it" AND C3's `_place_new`; earn checks `floor` AND `room` /
`homes_by_hand`; workers use C3's `_add_workers` with `* knack_own(p, "automation")` kept, also in
`_place_new`'s machine pick), collection.gd (E1 `lose_plain` AND C3 `leave`; `always_card` = buttons
+ `_is_plain`), automation_tab.gd (both refresh key parts; box job keeps C3's pile text, army job
kept), collection_tab.gd (`_knacks_seen` AND `_homes_key`), night_sky.gd (both redraw hooks),
ui_theme.gd (knack + plushie icons AND `new_part`), test_core.gd (the overlapping new test
functions were rebuilt whole: _test_herd_knacks, _test_plushie, _test_plushie_game, _test_new_homes,
_test_new_homes_game).

## Cross-feature rules (a pet is in one place at a time)

- `plushie_keeper_uid()` (new): the keeper's uid while the machine is open.
- `sendable_pets`: `_out()` (away + army) and never the keeper.
- `_busy_uids`: `_out()` + pinned + party leaders + the keeper (auto-merged).
- `plushie_keepers`, `plushie_keeper`, `plushie_can_swap`: use `_out()`, so army pets can't be the keeper.
- `army_choices` / `army_best` / `set_army_card`: never the keeper.
- `army_power_of` goes through `knack_own(pet, "power")` -> `Knacks.sum_in`, which counts buttons:
  a buttoned pet is stronger down the well.
- Dungeon wisp payout uses `grant_wisps`.
- `homes_pick`: its busy set (`_busy_uids`) covers army cards and the keeper; its working count also
  leaves out `army_herd_keys()`, so the stall can't pull herd pets off the rope. Pets with buttons
  are `always_card`, never taken, never folded; the sorting rule only sees new pets from boxes.

## Checks

- `tests/test_core.gd`: ALL PASSED (3898 checks). New `_test_merged_lanes`: a v23 save loads at v26
  (cellar band, empty plushie machine, jobs_auto -> join, full room -> stall), saves at v26; the
  keeper is never sendable, never picked by army best or by hand; an army pet can't be the keeper;
  the stall never takes army cards, the keeper or the army's herd pets; the army can still go.
- `tools/balance.gd`: runs clean.
- Flows (all PASSED, `expect fits` everywhere): fits, tutorial, dungeon, knacks, plushie, new_homes,
  pets_shelves, errands, errands_crowd, automation, workers.
- Looked at: plushie mid_try, fits plushie (workbench), dungeon army + automation, new_homes
  stall_open + rule_on, fits pets_knacks. Nothing spills, all readable.

## Review fixes (after the merge)

- The pets page no longer rebuilds for the "sorted today" number: `_homes_state()` is only the rule
  + whether sorting is open; each ShelfPlank under the line keeps its number label and updates it
  itself on `GameState.changed` (`ShelfPlank._refresh_today`).
- SortingCard: on `changed` only the "sorted today" number ticks (`_tick`); the steppers rebuild on
  the new `GameState.homes_rule_changed` signal (emitted by `set_rule`), `new_game`,
  `collection.pets_added` and visibility. `Collection.finish_seen(id)` (a small set kept with
  `_seen`, rebuilt on load) replaces walking every book key in `GameState.rule_finishes()`.
- One "a count's pets become stars" helper: `Collection._herd_to_stars(key, n)` (stand-in
  palettes, stand_next, `_stars`), used by both `lose_plain` (E1) and `leave` (C3).
- `Collection.set_finish(pet, finish)` retallies the room count and `_plain_cards`; the dev
  `dress finish=<id>` step uses it. Tests: `finish_seen`, `set_finish` in `_test_new_homes`.
- Rerun after the fixes: test_core ALL PASSED (3901 checks), balance clean, flows new_homes,
  pets_shelves, fits, plushie, dungeon PASSED; looked at new_homes rule_on (the stepper rebuilds,
  only commons say "sorted today") and sorted (planks + card show "sorted today 8"), fits pets.

## Text to add

architecture.md, next to the new homes section: "`GameState.homes_rule_changed` fires when the
sorting rule changes; the sorting card rebuilds on it, the shelf planks update their 'sorted today'
number in place."

docs/design.md / docs/architecture.md: done in this branch (one-place-at-a-time paragraph in
architecture.md "Saving"; design.md: stall never takes buttons / army / keeper, keeper can't go down
the well, the plushie machine spends wisps, stars include the well and the plushie machine).

Dev plan (docs/dev-plan.md), under E1/F1/C3:
> Merged in the sewing lane (lanes/sewing): E1 dungeon + F1 plushie machine + C3 new homes/sorting,
> save v24/v25/v26 (renumber on the main merge). A pet is in one place at a time: the plushie keeper
> never goes on adventures or in the army, the stall never takes the army. E3 next on this branch.

CLAUDE.md "where we left off":
> - Sewing lane merge (2026-09-29): lanes/plushie (F1) and lanes/c1-c3 (C3) merged into the E1
>   dungeon lane. Save chain v24 dungeon, v25 plushie (no migration), v26 new homes (jobs_auto ->
>   per-job join, full room -> stall). `wisps` is one field (dungeon pays, plushie spends).
>   `GameState.plushie_keeper_uid()`; the keeper is out of sendable/army, army pets can't be keeper,
>   `homes_pick` skips army cards, army herd and the keeper. Test `_test_merged_lanes`.

## Questions for Emilia (smallest safe pick taken)

- Can the plushie keeper also go down the well in the army? [No: one place at a time.]
- Wisp colour: two nearly equal values. [Kept the dungeon lane's.]
- The keeper can still be put on errands / worker jobs (as in the plushie lane). OK? [Left as is.]


---

## Earlier merge on this branch

### MERGE done: B2 boost plumbing + D1 knacks into the C1 (herd) branch

`git merge lanes/b2-d1` in the dungeon worktree (branch lanes/dungeon, C1 the herd). Both sides
forked at dde1560. Conflicts in 6 files, all resolved keeping both sides.

#### Save

- SAVE_VERSION stays **23** (C1's v22 -> v23 herd migration). B2 and D1 made no save change (a
  run's `knacks` field is optional, old runs count as x1), so there is nothing to chain. When the
  lanes are renumbered, this branch's only bump is still C1's one (22 -> 23).

#### How the conflicts went

- `scripts/core/catalog.gd`: `herd`, `boosts` and `knacks` all load.
- `scripts/dev/dev_driver.gd`: both help blocks and every step (herd, room, fill-room, fav, shelf,
  give-box from C1; boosts, dress from D1).
- `tests/test_core.gd`: `_test_herd`, `_test_herd_game` and `_test_knacks` all run, plus
  `_test_herd_knacks` (where the two meet): a count's template counts no knacks, a card dressed
  with an errands knack is picked ahead of an equal count by put_on_job and sent home last by
  take_off_job, and workers_speed adds the knack share for cards only.
- `scripts/game_state.gd`:
  - signals `room_full` and `knacks_changed` both kept.
  - `job_rate`: C1's `size` (cards + herd) x B2's `boost("errands")`.
  - C1's `_pick` lambdas: put_on_job / take_off_job use D1's `_pet_speed`; put_workers /
    take_off_workers use `worker_speed x knack_own(.., "automation")` (same as `workers_speed`).
  - `workers_speed`: cards x `knack_own(pet, "automation")`; herd workers at template speed.
  - `knack_own` returns 1.0 for a pet with no uid: herd templates (uid "") never count knacks and
    never share one cache slot. Stand-ins (uid "h:...") are whole pets and count theirs.
  - no `toy_boost` calls left; `_knacks_changed()` is in debug_new_game (after
    collection.load_from, since uids start over at 1 there), load_game and _regate.
- `scripts/ui/pet_details.gd`: D1's badges + knack card, then C1's heart + make-active row.
- `scripts/ui/collection_tab.gd`: C1's bookcase and shelves; D1's grid code dropped. Kept
  `_knacks_seen` / `_knacks_key()`: on `knacks_changed` with a new key the tab `_mark_dirty()`s,
  so an open shelf rebuilds (badges + details).
- `scripts/ui/mini_card.gd`: `MiniCard.new(pet, width, knack := false)`; with `knack` it draws the
  best knack's badge (20 px, tilted 10 degrees) on the bottom-right corner (top-left is moon /
  new!, top-right the heart). `ShelfView` passes `true`; the cushion doesn't. The shelf's list
  already had a 10 px bottom / right margin, so the last row's badges aren't cut.
- `scripts/ui/knack_badge.gd`: comments point at MiniCard. PetCard is back to its pre-D1 self
  (the `knack` param and its corner badge went with the old grid): MiniCard is the only card
  that wears the corner badge.

#### Flows

- `tests/flows/knacks.flow`: after the second `tab collection`, `click MiniCard#1` (your active
  pet on the cushion opens its shelf, chosen); the last `click PetCard#2` is `click MiniCard#2`.
- `tests/flows/fits.flow`: D1's `click PetCard#1..3` are `click MiniCard#1..3` (in the open shelf).
- Ran and PASSED: test_core (3587 checks), balance, flows fits, tutorial, knacks, pets_shelves,
  long_pet, toys, errands_crowd, workers, automation.
- Screenshots looked at: knacks grid / all_badges / other_pet (shelf corner badges, details with
  badges + card + heart + make active, all inside 920x600), fits pets_knacks.

#### Text for the shared docs

docs/design.md and docs/architecture.md are updated here (knacks paragraph: shelf cards' corner,
herd counts x1; architecture: knacks_changed marks the pets tab dirty, templates at uid "").

Dev plan: B2 and D1 are merged into lanes/dungeon (C1) for E1; nothing new to tick.

CLAUDE.md "where we left off", add one line:
- lanes/dungeon now has C1 (herd) + B2 (boosts) + D1 (knacks) merged: shelf cards wear the best
  knack badge bottom-right; herd counts count no knacks (templates), stand-ins do. Save still v23.

#### Questions for Emilia

1. Herd counts have no looks, so their knacks stay x1 (cards and stand-ins count theirs). Should
   they count something, like an average share per rarity?
2. The best-knack badge shows on opened shelves only, not on the cushion cards. Want it there too?
