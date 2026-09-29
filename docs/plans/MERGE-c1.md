# MERGE: B2 boost plumbing + D1 knacks into the C1 (herd) branch

`git merge lanes/b2-d1` in this worktree (lanes/dungeon). Both branches fork at dde1560.
play.py is the same commit on both sides (no conflict). A trial `git merge-tree` shows 6 files
with conflicts; the rest (docs, adventures/automation/errands/machine tabs, fits.flow) auto-merge.

## Save
- C1 is at SAVE_VERSION 23 (herd counts, wherd, room). B2 and D1 made no save change (a run's
  optional `knacks` field, old runs x1). So: keep 23 and C1's v22 -> v23 migration; nothing to
  chain. Noted in docs/plans/MERGE-done.md for the renumbering later.

## Conflicts and how each is resolved (keep both sides)
- `scripts/core/catalog.gd`: keep `herd` AND `boosts` + `knacks` (vars and `_load` lines).
- `scripts/dev/dev_driver.gd`: keep both help blocks and both match arms (herd, room, fill-room,
  fav, shelf, give-box + boosts, dress).
- `tests/test_core.gd`: call `_test_herd`, `_test_herd_game` and `_test_knacks`.
- `scripts/game_state.gd`:
  - signals: keep `room_full` and `knacks_changed`.
  - `job_rate`: C1's `size` (cards + herd) with B2's `* boost("errands")`; the herd sum uses
    `_pet_speed(Herd.template(...), job)`.
  - `put_on_job` / take-off: keep C1's `_pick` version, but its speed lambdas (2 places) use D1's
    `_pet_speed` (own errand knacks) instead of `Jobs.pet_speed`.
  - `workers_speed`: cards `* knack_own(pet, "automation")`; herd counts as C1 has them.
  - Rule picked for counts: a herd count works at its template's speed with NO knack share (a
    template has no look, just default parts). `knack_own` returns 1.0 for a pet with no uid
    (templates) so the per-uid cache can't mix templates up. Stand-ins (whole pets with rolled
    parts, e.g. on adventures) do count their knacks through `trip_knacks`. -> question below.
  - After the merge: grep that no `toy_boost` is left (D1 removed it; C1's calls auto-merge to
    `boost()`), and that D1's `_knacks_changed()` calls landed in C1's load/new-game paths.
- `scripts/ui/pet_details.gd`: doc comment names both (knack badges + the heart); keep D1's
  badges + knack card AND C1's fav + make-active button row.
- `scripts/ui/collection_tab.gd` (the real one): C1 replaced the grid with bookcase + shelves, so
  D1's grid code (_filtered, _select, _sorted, grid padding, PetCard(knack=true)) is dropped. Kept
  from D1: `_knacks_seen` + `_knacks_key()`, set in `_rebuild()`, and `knacks_changed` ->
  `_mark_dirty()` when the key changed (an open shelf rebuilds and its details redraw badges).
  C1's new_game (close_shelf) and room_full hooks stay; D1's pets_removed hook is dropped (C1
  already has one).

## UI sketch (knacks on the shelves)
- Details (right of an open shelf): badges row + knack card under the tags, fav + make active
  below, as both sides had it. Must fit 920x600; if not, the knack card gets tighter.
- The grid's "best knack on the card corner" moves to MiniCard: `MiniCard.new(pet, w, knack)`
  draws the best knack's badge (~20 px) on the BOTTOM-right corner (top-left = moon/new!,
  top-right = heart are taken). Only in an opened shelf (ShelfView), not on the cushion. Shelf
  flow gets a little bottom margin so the last row's badges don't clip.

## Flows / tests
- `tests/flows/knacks.flow`: PetCard clicks -> open the shelf from the cushion
  (`click MiniCard#1`, your active pet), then `click MiniCard#2` for "other pet".
- `tests/flows/fits.flow`: D1's `click PetCard#1..3` -> `click MiniCard#1..3` (a shelf is open there).
- Run: test_core, balance, flows fits, tutorial, pets_shelves, long_pet (C1), knacks, toys (D1),
  plus errands_crowd, workers, automation (boost + herd both touch these). Check shots of knacks
  (badges on shelf cards + details) and pets_shelves.
- Then commit the merge ("merge boosts and knacks into the herd"), write docs/plans/MERGE-done.md
  (what was resolved, save note, doc text for dev plan / CLAUDE.md).

## Questions for Emilia
- Herd counts have no looks: should their knacks count (e.g. an average share per rarity), or
  stay x1 as picked here? Cards and stand-ins count theirs.
- Best-knack badge on the cushion cards too, or only on an opened shelf (picked: shelf only)?
