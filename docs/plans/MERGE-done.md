# MERGE done: B2 boost plumbing + D1 knacks into the C1 (herd) branch

`git merge lanes/b2-d1` in the dungeon worktree (branch lanes/dungeon, C1 the herd). Both sides
forked at dde1560. Conflicts in 6 files, all resolved keeping both sides.

## Save

- SAVE_VERSION stays **23** (C1's v22 -> v23 herd migration). B2 and D1 made no save change (a
  run's `knacks` field is optional, old runs count as x1), so there is nothing to chain. When the
  lanes are renumbered, this branch's only bump is still C1's one (22 -> 23).

## How the conflicts went

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

## Flows

- `tests/flows/knacks.flow`: after the second `tab collection`, `click MiniCard#1` (your active
  pet on the cushion opens its shelf, chosen); the last `click PetCard#2` is `click MiniCard#2`.
- `tests/flows/fits.flow`: D1's `click PetCard#1..3` are `click MiniCard#1..3` (in the open shelf).
- Ran and PASSED: test_core (3587 checks), balance, flows fits, tutorial, knacks, pets_shelves,
  long_pet, toys, errands_crowd, workers, automation.
- Screenshots looked at: knacks grid / all_badges / other_pet (shelf corner badges, details with
  badges + card + heart + make active, all inside 920x600), fits pets_knacks.

## Text for the shared docs

docs/design.md and docs/architecture.md are updated here (knacks paragraph: shelf cards' corner,
herd counts x1; architecture: knacks_changed marks the pets tab dirty, templates at uid "").

Dev plan: B2 and D1 are merged into lanes/dungeon (C1) for E1; nothing new to tick.

CLAUDE.md "where we left off", add one line:
- lanes/dungeon now has C1 (herd) + B2 (boosts) + D1 (knacks) merged: shelf cards wear the best
  knack badge bottom-right; herd counts count no knacks (templates), stand-ins do. Save still v23.

## Questions for Emilia

1. Herd counts have no looks, so their knacks stay x1 (cards and stand-ins count theirs). Should
   they count something, like an average share per rarity?
2. The best-knack badge shows on opened shelves only, not on the cushion cards. Want it there too?
