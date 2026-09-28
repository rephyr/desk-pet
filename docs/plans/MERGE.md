# MERGE: lanes/plushie + lanes/c1-c3 into the sewing lane (E1 dungeon)

Goal: one branch with the E1 dungeon, the F1 plushie machine and C3 new homes + the sorting rule,
all working together, so E3 can open the plushie machine and add keep lines. No new features.

## Order

1. `git merge --no-ff lanes/plushie` (1 commit, same base 09c7f0a as us)
2. tests + balance, commit the merge
3. `git merge --no-ff lanes/c1-c3` (5 commits, older base 099ceb2: it has no knacks, no toy boosts)
4. tests + balance + flows, fix, commit

## Save chain (every lane bumped 23 -> 24)

| version | what | code |
|---|---|---|
| v24 | E1 dungeon (ours): well line becomes bands, rumours/parties moved | `migrate` `if version < 24` stays |
| v25 | F1 plushie: machine state, wisps, pet `buttons`, bag keys `slot:id@n` | comment only (old saves load an empty machine); comments in game_state/pet.gd say v25 |
| v26 | C3 new homes: `new_homes`, per-job `join` from `jobs_auto`, full room opens the stall | load_game `from_version < 24` -> `< 26` (both places) |

SAVE_VERSION = 26. `wisps` is ONE field (both lanes added it for the same currency): the dungeon
pays it, the plushie machine spends it. A v24 save from any lane loads (they only ever lived in
test profiles; main is also at 24, the final merge renumbers again). Written up in MERGE-done.md.

## Plushie merge: conflicts, keep both

- data/themes.json `wisp`: both added the same colour with tiny differences: keep ours.
- data/unlocks.json: note text gets both `floor` and `button_gift`/`given_by`; unlocks dungeon,
  lead_army AND plushie; finds deep_rope, little_key AND plushie_machine.
- catalog.gd: `dungeon` and `plushie`. ui_theme.gd: one WISP line, one comment.
- game_state.gd: both signals; unlock apply does `learns` and `button_gift`; dungeon section and
  plushie section both in; `_dungeon_first` kept.
- dev_driver.gd: both sets of steps (dungeon steps + plushie steps).
- tests: both test calls; feature list gets dungeon, lead_army, plushie; the "some event gives this
  find" check accepts machine OR dungeon floor OR `given_by`; knack test keeps the dungeon gate and
  the buttons check.

Cross-feature fixes (a pet is only in one place):
- `sendable_pets`: `_out()` (away + army) AND not the keeper.
- `_busy_uids`: `_out()` + pinned + party leaders + the keeper.
- `plushie_keepers`: `_out()` instead of `away()` (army pets can't be the keeper).
- `army_choices` / `army_best`: never the keeper.
- Check `army_power_of` goes through the knack path that counts buttons (a buttoned pet is
  stronger down the well). Dungeon wisp payout uses `grant_wisps`.

## c1-c3 merge: conflicts, keep both

- `jobs_auto` is gone (C3: "new pets join here" per job). Active pet swap keeps our "your active
  pet leads the army, it isn't in it" AND C3's `_place_new`.
- `_pick` for workers: C3's `_add_workers` refactor, keeping our `* knack_own(p, "automation")`.
- unlock earn: `floor` AND `room` / `homes_by_hand`; unlocks dungeon, lead_army, plushie, new_homes,
  sorting.
- collection.gd: our `lose_plain` (army losses) AND C3's `leave` (new homes); both write `fallen`
  / `fallen_n`. `always_card` = plushie's (buttons) with C3's `_is_plain`.
- automation_tab: both refresh key parts; box job keeps C3's pile text, army job kept.
- collection_tab: both `_knacks_seen` and `_homes_key`. night_sky: both redraw hooks.
- ui_theme icons: knack badges AND `new_part`. catalog: `new_homes` too. Signals: all.
- docs/architecture.md: both sections.
- tests + dev_driver: union.

Cross-feature fixes:
- New homes never take army pets: `homes_pick` busy set includes the army cards and the keeper;
  its "working" herd count also subtracts the army's herd (`_resting()` army_herd), so the stall
  can't pull pets off the rope.
- Hopper, army and stall all read `resting_cards()`: check none of them can grab the same pet.
- Pets with buttons are cards and never folded; the sorting rule only sees new pets from boxes, so
  buttons are safe. (E3 adds keep lines.)

## Checks

- `tests/test_core.gd`, `tools/balance.gd` (profile test-sewing)
- flows: fits, tutorial, dungeon, knacks, plushie, new_homes, pets_shelves, errands, automation,
  workers (the jobs_auto change touches these)
- new tests: a v23 save loads at 26 (dungeon bands, empty plushie, jobs_auto -> join); the keeper
  is never sendable, never in the army; `homes_pick` never counts army herd or army cards.
- look at shots of the workbench (plushie), adventures (dungeon), shelves stall.

## Done-notes

docs/plans/MERGE-done.md: save chain table, the cross-feature rules above, text for design.md /
architecture.md / dev plan / CLAUDE.md.

## Questions for Emilia (smallest safe pick in brackets)

- Can the plushie keeper also go down the well in the army? [no: one place at a time]
- Wisp colour: two nearly equal values [kept the dungeon lane's]
