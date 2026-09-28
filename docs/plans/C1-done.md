# C1 + the herd: done notes (lane c1-c3)

**Status: VERIFIED 2026-09-29** (after review rounds 1 and 2; save still v23, one bump from 22).

Built from docs/plans/C1.md, dev-plan C1/C3 (the herd part only: the new homes stand and the
sorting rule are not in this step) and picks.md (C1 look A, one room cap).

## What was built

- **The herd.** Plain pets (finish below `card_from`, holo) fold into a count per rarity x finish
  (`"common:normal"`). Always a card: favourites, the active pet, holo or better, a pet that brought
  a part new to the book (`Pet.new_part`, set in `Collection.add`), pets with buttons (F2: a hook
  comment in `Collection.always_card`), and pets GameState needs whole (`Collection.busy`: away on an
  adventure incl. ones that stayed until the trip is welcomed back, pinned good pulls, adventure
  party leaders). Each shelf keeps its newest `keep_cards` (20) plain cards; past that the oldest
  foldable one folds (`Collection.refold`, run after add, unfav, a new active pet, a trip collected,
  a good pull dismissed, a party leader taken off, and at the end of loading).
- **Counts everywhere.** Errands (`jobs[id].herd`), workers (`automation.wherd`), resting
  (`GameState._resting`, cached until `_rest_changed`), crowds and polaroids (`job_faces`,
  `worker_faces`, `resting_faces`: cards first, then stand-in uids). Put on / take off / share out /
  fill up pick across cards and whole counts (`GameState._pick`, `GameState.water_fill`).
- **Stand-ins** for adventures: `h:<rarity>:<finish>:<n>` uids, `Herd.stand_in` (look from a seed,
  the rarity's average stats, no traits). `sendable_pets` offers up to `stand_ins` (10) per count;
  sending takes resting ones first, then off errands / machines (`_herd_off_places`). Home: they
  just stop being away. Lost: `Collection.remove` takes one off the count, adds a star and bumps
  `stand_next` (that look never comes back). A worker party led by a herd pet keeps a stand-in uid
  in its slot.
- **The room.** One cap for every plain pet together (cards and herd): `Herd.room_cap` (500 x1.5
  per level, rounded to 50), `GameState.room` (level, saved), `room_cap / room_left / room_price /
  buy_room / room_shown`. Full: `open_boxes` opens nothing (count clamped to what fits; `room_full`
  signal when by hand), your pet's opening stops (`can_auto_open`), box workers stop
  (`_workers_open`), the machine's pet box becomes a starter box on your pile. Gifts (tutorial pets,
  the basket pet) always come in.
- **Night sky.** Star i placed by `hash(i)` (not the uid), tinted by `fallen[i]` (palettes; past
  `fallen_keep` a star borrows one by its number); draws at most the panel's worth + 6000 band stars.
- **UI (look A, the bookcase).** `CollectionTab`: `pets | toys | book` + `RoomPill` (house, meter,
  "412 / 500"; full = pink + wiggle every 2.6 s; tap = the room card "more room 500 → 750" + coin
  button). `Bookcase`: pink cushion (up to 9 `MiniCard`s: active, favourites, best) + a `ShelfPlank`
  per rarity you have (tilted tag "common 48,210", newest 4 standing, `Mound` ~log10 of the count up
  to 60, "✦ n" shiny). `ShelfView`: "‹ shelves", tier + count, herd chips (plain / ✦ shiny with a
  small mound), always-cards (paged past `shelf_page`, 30), stitched line, the newest plain cards,
  `PetDetails` with the new heart button (favourite) next to make active. The old grid, sorts,
  filter chips and pages are gone.
- Voice lines: `pets_cozy` (90%+ full), `room_full` (squish), `room_more`, `room_poor`,
  `pets_fav_on`, `pets_fav_off`, `shelf_<rarity>`.

## Files

New: `data/herd.json`, `scripts/pets/herd.gd` (Herd), `scripts/ui/bookcase.gd` (Bookcase),
`scripts/ui/shelf_plank.gd` (ShelfPlank), `scripts/ui/shelf_view.gd` (ShelfView),
`scripts/ui/mini_card.gd` (MiniCard), `scripts/ui/mound.gd` (Mound), `scripts/ui/room_pill.gd`
(RoomPill), `tests/flows/pets_shelves.flow`.
Changed: `scripts/pets/collection.gd` (rewritten), `scripts/pets/pet.gd` (fav, new_part),
`scripts/game_state.gd`, `scripts/core/catalog.gd` (loads herd.json), `scripts/idle/automation.gd`
(fresh() has wherd), `scripts/ui/collection_tab.gd` (rewritten), `scripts/ui/pet_details.gd`,
`scripts/ui/errands_tab.gd`, `scripts/ui/automation_tab.gd`, `scripts/ui/adventures_tab.gd`,
`scripts/ui/boxes_tab.gd`, `scripts/ui/machine_tab.gd`, `scripts/ui/night_sky.gd`,
`scripts/dev/dev_driver.gd`, `data/voice.json`, `tests/test_core.gd`, `tests/flows/fits.flow`
(clicks cushion MiniCards and a ShelfPlank instead of the grid's PetCards), `tests/flows/long_pet.flow`
(the long pet is picked from the cushion), `docs/design.md`,
`docs/architecture.md`.

## Data shape (save)

**SAVE BUMP: 22 -> 23 (exactly one; the merge step renumbers it).**
- `collection`: `{ pets: [card dicts, may have fav / new_part], herd: { "common:normal": n },
  active, next_id, seen, fallen: [palettes], fallen_n, stand_next: { key: n }, herd_ever }`
- `jobs[id]`: `{ crew: [card uids], herd: { key: n }, fill }`
- `automation.wherd`: `{ job id: { key: n } }` (never adventures)
- top level `room`: int
- Migration: nothing at dict level. `Collection.load_from` reads old `fallen` pairs as palettes
  and, for a collection without `herd`, marks the first pet (in pull order) with each part
  `new_part`. `load_game` ends with `collection.refold()`, which folds old plain pets and turns old
  crews / workers of uids into counts through `pets_folded` -> `GameState._on_folded`.
  `_clamp_herd_places` keeps counts on places within what the herd has.

## Dev steps (DevDriver)

`herd <rarity> <finish> <n>`, `room <level>`, `fill-room`, `fav <n>`, `shelf <rarity>`,
`give-box <id> <n>`.

## Flows

New `pets_shelves` (near / shelf / full + squish / room card / later / million / million shelf /
errands + automation with a million / the party picker with stand-ins; `expect fits` each time).
All pass: pets_shelves, fits, errands, errands_crowd, workers, automation, party, postcard,
tutorial, home_pile, boxes, pet_box, new_game, long_pet, unlock_popup, toys, machine, rummage, gear,
encounters, bits_map, errand_tools, video, pack_sound (every flow in tests/flows).
Tests: `tests/test_core.gd` `_test_herd` (folding, always-cards, busy, round trip, stand-ins, old
collection, room math, water fill, 1M in a tiny save) and `_test_herd_game` (a v22 save with 200 on
an errand and 40 workers -> counts, same totals, rate within 15%, save shrinks; + all, take off 100,
share out, workers fill / off, stand-ins on a trip with one lost, room full -> box waits -> buy
room -> opens; 1M plain pets: save 1 ms, load 1 ms, a job 0 ms, 8 KB save). Balance unchanged.

## Text to add

### docs/dev-plan.md (C1 and C3)

- C1: **Built 2026-09-28 (lane c1-c3):** look A, the bookcase: cushion (active, favourites, best),
  a plank per rarity (tag, newest 4, a mound that grows with the count, shiny count), a shelf
  opened (herd chips, always-cards, newest 20, sticker with heart + make active), the room pill.
- C3: **The herd built (with C1):** counts per rarity x finish, always-cards, errands / workers /
  parties from counts (stand-ins for adventures), save v23, the night sky by index, the room cap
  (one cap, coins, simple first version). Still to do: busy paws switch, the new homes stall, the
  sorting rule card, feeding the machine (F1).

### CLAUDE.md "where we left off"

- C1 + the herd (lane c1-c3, save v23, renumber at merge): plain pets fold into counts per rarity x
  finish (`Collection.herd`, `Herd`, data/herd.json); always cards: favourites (`Pet.fav`), the
  active pet, holo+, `Pet.new_part`, busy (away, pinned, party leaders); each shelf keeps its
  newest 20. Errands `jobs[id].herd`, workers `automation.wherd`, resting cached
  (`GameState._resting` / `_rest_changed`), faces for crowds (`job_faces`, `worker_faces`,
  `resting_faces`), adventures take stand-ins (`h:<rarity>:<finish>:<n>`, `Herd.stand_in`). The room:
  one cap for plain pets (`GameState.room`, `room_cap`, `buy_room`), full = boxes wait, pill pink +
  wiggle, squish line. Night sky places star i by index. Pets tab = look A bookcase (`Bookcase`,
  `ShelfPlank`, `Mound`, `ShelfView`, `MiniCard`, `RoomPill`; heart in `PetDetails`). Dev steps
  `herd`, `room`, `fill-room`, `fav`, `shelf`, `give-box`; flow pets_shelves (fits clicks
  MiniCard / ShelfPlank now). Core tests always run in a profile (`-- --profile=test_core`; without
  one test_core picks it itself). Old saves get room for their pets on load.

## C1 review fixes (same lane, no new save bump: still v23)

- `tests/test_core.gd` never touches the real save: with no `--profile` it sets one ("test_core")
  through `DevArgs.overrides` before anything loads, and `_test_herd_game` skips without a profile.
  Check command for CLAUDE.md: `godot --headless -s tests/test_core.gd -- --profile=test_core`.
- A new active pet with sharing on sends the old one back to work (`_rest_changed()` first in the
  active_changed handler).
- Saves from before v23 load with room for their pets (+10%, `room.old_save_margin`).
- Pets tab: `_mark_dirty(rarities)` rebuilds at most once a frame (deferred) and skips an open
  shelf of another rarity; `Collection.herd_changed` now carries the changed keys.
  `GameState.shelf_split(rarity)` sorts always-cards with each rank worked out once.
- Auto parties get fresh stand-ins after each one leaves (`_resting_stand_ins`, `_sendable_stand_ins`).
- `last_moved` names the pet you tapped (`_moved_name`).
- `_clamp_herd_places` clears the crew / worker caches when it trims (held saves while loading).
- Automation tab key includes `automation.wherd`.
- Save loading: `Herd.clean_counts` for the herd (drops non-number values), untyped reads with type
  checks for `stand_next`, `fallen`, `automation.wherd`.
- UI uses public helpers: `GameState.herd_faces`, `shelf_split`, `room_is_full`, `room_is_cozy`
  (data/herd.json `room.cozy_at` 0.9); `Herd.mound_size(catalog, n, most)` (the chip uses it,
  `Herd.MOUND_LOG_SPAN`).
- New core checks: old active pet back to work, tapped stand-in named, 700-pet v22 save gets room,
  `room_level_for`.

## C1 review fixes, round 2 (still v23, no new save bump)

- Automation tab, open boxes job: with a full room it no longer says "the pile is empty". It shows
  "squish! N boxes on your pile" (full room) or "N boxes on your pile" (the pet can't open them for
  another reason), and "the pile is empty" only when it is. `GameState.boxes_on_pile()` (home tab
  uses it too); the tab's rebuild key includes the pile count and the full room.
- Room card: the coin button stays tappable when you're short (price and coin drawn in the locked
  colour), so the `room_poor` line fires.
- Bookcase: planks no longer stretch. `Bookcase._fit_planks` shares the page height out, each plank
  at most `Bookcase.PLANK_MAX` (76 px, at least `ShelfPlank.MIN_H` 48); the case shrinks to its
  planks, so one pet = one short plank under the cushion, and 5-6 rarities still fill the page.
- Scaling: `Collection._plain_cards` (plain-finish cards in pull order) is all `refold()` walks,
  and it returns at once when no shelf has more than keep_cards plain cards (skips the busy call
  too). Folded cards leave `pets` by native erase (a few) or one rebuild (many). `_is_plain` caches
  plain-ness per finish. `GameState.shelf_split` buckets by rank instead of sorting.
  Probe (check profile, 20k holo cards + 1M herd): 200 refolds 27.4 s -> 5 ms, shelf_split common
  482 -> 26-34 ms, an opening without saving 0.4 ms. What's left is the save itself: JSON of 20k
  cards is ~200-270 ms per opening. That scales with the always-cards, so it waits on Q1 (fewer
  always-cards) or a save throttle.
- Flow pets_shelves: + room card when short on coins (`room_poor` shot), + the box job with a full
  room (`auto_full` shot). Core test: 100 adds next to 10k holo cards (fold still right, quick).
- tools/play.py: its own Xvfb display number per lane + flow (committed separately; it was sitting
  uncommitted in the worktree).

## Questions for Emilia (smallest safe pick used for now)

1. Holo and better are always cards. The starter box rolls holo+ about 15% of the time, so a late
   game with a million pulls keeps ~150k whole cards (the save grows with them). For now the opened
   shelf pages them (30 at a time). Maybe only holo+ with something extra stays a card?
2. The room pill turns up when the first pet folds into the herd (the 21st plain pet on a shelf).
3. Room numbers are placeholders: 500 at first, x1.5 per upgrade, 500 coins x1.8 per upgrade.
4. Herd pets work at their rarity's average stats with no traits (a crew from counts is a bit
   slower than the same pets as cards, about 5-10% on the coin hunt, since traits like greedy are gone).
5. Unfaving an old pet folds it straight away if its shelf has 20 newer plain ones.
6. The old grid's sorts and filter chips are gone (the bookcase replaces them).
7. Only box openings wait when the room is full; gifts ignore the cap. `open 10` with room for 3
   opens 3.
8. A full room turns the machine's pet box into a starter box on your pile (it waits there).
9. Pets that stayed on an adventure now count as away until the trip is welcomed back (before they
   looked like resting pets for that moment).
10. Saves from before the room get room for their pets plus 10% (free). Smallest safe pick; could
    be exactly their pets instead.
11. (not from this step) the collectibles switch shows a padlock "???" for toys until toys open,
    which goes against "hidden until earned". Hide the toys switch until then?
