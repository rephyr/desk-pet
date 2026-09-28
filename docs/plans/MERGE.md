# MERGE: lanes/b1 (box tiers) into lanes/wish (test + A4 book)

One merge: `git merge --no-ff lanes/b1` (4 commits: box tiers sunny/sunset/midnight, machine odds,
play.py lane name). Merge base 9e57dd0; this branch is 13 commits ahead (A3 errand jobs, A4 book
stickers, play.py lanes).

## Conflicts (trial `git merge-tree`)

| file | ours | theirs | resolution |
|---|---|---|---|
| scripts/game_state.gd (top) | `static var testing`, SAVE_VERSION 24 | SAVE_VERSION 23, `WORKER_BOXES_MAX` | keep `testing` + `WORKER_BOXES_MAX`, SAVE_VERSION 25 |
| scripts/dev/dev_driver.gd (docs + match) | `book <page> [left]`, `stickers off` | `tiers all \| off` | keep all three steps |
| scripts/ui/unlock_popup.gd | `_sticker_showing`, `_quiet_stickers` | `static var up` | keep all; `_show` sets `up = true` and `_sticker_showing`; `_close` clears `up` (b1 already does) |
| docs/architecture.md (save notes) | v23 scout_notes, v24 stickers | v23 box tiers | one chain: v23 scout_notes, v24 stickers, v25 box tiers |

Everything else auto-merges (adventures.json lucky -> sunset, catalog.gd, collection.gd, jobs.gd,
machine_tab.gd, expanded_view.gd, test_core.gd, balance.gd, play.py, design.md, unlocks.json,
voice.json).

## Save chain (one line, every old save loads)

- v23 = scout_notes (A3), v24 = stickers (A4), v25 = box tiers (B1: boxes_bought, boxes_greeted).
- None of the three needs a version-gated step in `_migrate`: all read missing fields with defaults,
  and `BoxShop.fix_retired` runs on every load whatever the version. So the only code change is
  SAVE_VERSION 25 and the `_migrate` comment "v23 added box tiers" -> "v25 added box tiers".
- Tests: b1's lucky-box test loads a `"version": 24` save (still < 25, fine); the book test loads a
  v23 save (fine). Add one test: a v22 save with a lucky box + a full book page loads to v25 with
  sunset boxes, the sticker, scout_notes 0.

## Cross-feature checks (things neither side knew about)

- Book luck sticker goes through `toy_boost("luck")`: b1's `machine_odds` calls toy_boost, so the
  prize card shows the sticker's luck. Check with a test (odds with the eyes sticker > without).
- Book "finishes" page needs every finish of blob; with b1 the sunny box no longer rolls glitch or
  prismatic (sunset has glitch, only midnight has prismatic). And parts with `from` only come from
  better boxes, so part pages need sunset/midnight too. Not a bug (pages are collect-everything),
  but a pacing change: note as a question for Emilia. Check tools/balance.gd book numbers still pass.
- A3 job rewards that hand out parts: make sure they go through `parts_in(..., COMMON_BOX)` like
  b1's `_uncommon_part` (grep `parts_of_tier(` after the merge; any other job/rummage part roll
  that bypasses `from` would leak better boxes' looks early).
- `auto_open_pack` now returns the best of 2-3 pets; the book fills from `collection.add`, so every
  pet in a sunset box counts for stickers. No change needed, test only.
- play.py: both sides added lane handling; make sure the merged file has one docstring line and one
  profile suffix (trial merge looks right: line 34-35 and the per-lane display).

## Docs

- docs/architecture.md: the save chain above; keep both sections (Book, BoxShop).
- docs/design.md: auto-merged; read it once for doubled or clashing lines.
- docs/plans/MERGE-done.md: what merged, conflicts and how, save renumber (b1's v23 -> v25), test
  and flow results, questions for Emilia, text for dev-plan / CLAUDE.md.

## Run after merging

1. `godot --headless -s tests/test_core.gd -- --profile=test-wish`
2. `godot --headless -s tools/balance.gd -- --profile=test-wish`
3. Flows (DESK_PETS_LANE=wish): fits, tutorial, boxes, box_tiers, machine_odds, unlock_popup,
   pet_box, book, errand_jobs, errand_tools, workers, errands_crowd.
4. Look at box_tiers + book shots (3-tier shop with book stickers open; sticker card vs a new tier
   arriving: `UnlockPopup.up` should make the tier greeting wait for the sticker card).
5. Fix anything broken, commit: "merge box tiers" (plus small fix commits), no push.

## Questions for Emilia (smallest safe choice taken)

- The glitter jar (finishes) page now needs a midnight box for prismatic, and part pages need the
  better boxes' new looks. Kept as is (the book is a long-term goal); say if a page should only
  count what the sunny box can give.
