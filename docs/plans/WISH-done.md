# WISH done: the wishing jar (F3 wish list, Look A)

Built on `lanes/wish` as planned in WISH.md.

## What was built

- Collectibles > book: once earned, the **wishing jar** card (224 px) stands beside a narrower book
  (3 stickers a row, 74x78 tiles, smaller page margins). Before it's earned the book is exactly as
  before (no column, taps do nothing).
- Tap a found part sticker (bodies, palettes, patterns, eyes, accessories; not the finishes pages)
  to wish for it (on release, like a button). The wished sticker gets a jar badge + pink dashed
  outline and is the jar's label (a tilted sticker: the look, its name, its tier).
- Shelves: a chip per rarity you have pets of that can go (the next pet to go + a count), picked
  one dashed pink and tilted; then 1 / 10 / 100 / all. Only resting pets go (never the active pet,
  pets away, on errands, workers, pinned good pulls, or pets with sewn parts), the plainest first
  (normal finish, then fewer traits, then lowest stat total). They never come back (`Collection.remove`: each is a night-sky star).
- The jar (drawn in code): glass, the pets' palette colours as dots up to the level, one band per
  step, 3 dashed step lines, a wavy pink top while filling, a star per step down the side (gold when
  full), the lid glows gold when the jar is full (then the buttons are disabled). `N / M` under it
  (`8,800` when full). Up to 8 little pets hop from the chip into the jar; a gold star floats up
  when a step fills.
- Steps 200 / 600 / 2000 / 6000 (data). Every full step raises that look's weight inside its
  already-rolled tier in every box (x1.5 / x2 / x3 / x4 after steps 1-4): `PetRoller.wish` weights
  the part picked in the tier and the signature slot (by the mean weight of that slot's parts at the
  tier, so a look alone in its tier like the bunny body still turns up more). The tier roll never
  looks at it. All boxes go through `GameState._roller` (your rips, your pet's opening, box tables,
  the machine's pet box).
- Switching the wish keeps every jar's sent count, steps and boost.
- Your pet: `wish_pick` on a new wish (`wish_done` if that jar is already full), `wish_send` per
  send, `wish_step_1..4` when a step fills.
- Unlock `wish` (hidden): opens `feature:wish`, earn `{ "others": "boxes" }` (the other pets know
  how to open boxes = box tables). New earn key `others` in `GameState._earned`;
  `teach_others()` now calls `check_unlocks()`. Popup "new: a wishing jar!", show me -> the book.

## Review fixes (second pass)

- Speed at big collections: `Wish.plain_key` (finish rank, trait count, stat total as one int,
  cached on the pet as `Pet.plain`, not saved: none of those ever change). `Wish.goers` is one pass
  (n = 1: a min scan; otherwise buckets by key, only the distinct keys get sorted). `wish_pool(rarity)`
  and `wish_shelves` are single passes over `collection.pets` with one merged skip set. Measured at
  100k pets (headless): shelves 617 ms -> ~115 ms (first look ~400 ms while keys are worked out),
  tapping "1" 4 s+ -> ~100 ms, "all" (8,699 pets) ~180 ms (plus the usual save_game).
- `WishJarCard`: the jar redraws right away, the shelves are looked over at most once a second while
  pets stream in (box tables); chips are rebuilt only when which shelves exist (or the picked one)
  changes, otherwise counts and faces change in place. `send()` no longer calls `wish_shelves()`
  (uses the chip's own first pet) and drops the chip's count by what was sent straight away.
- Pets with sewn parts never go into the jar (test added next to the pinned check).
- `Collection.fallen` is capped at `FALLEN_MAX` 14,000 (a 920x600 sky holds 13,800 specks); past
  that `fallen_more` counts per palette (saved in the collection dict; no version bump, loaders
  without it start at none and a longer `fallen` moves its extra over). `NightSky._draw_more` draws
  at most `BAND_MAX` 8,000 of them into the band, a touch deeper as the count grows. Test added.
- Book stickers only set the wish when released over the sticker (drag off to cancel).
- Dev steps `wish` / `wish-shelf` fail cleanly with too few words.
- `JarArt.SPECKS := 110` names the drawn dot count (only the drawing; `dots` in data is how many
  colours a jar keeps).
- architecture.md: the v26 line now follows v25.

## Files

- New: `data/wish.json`, `scripts/pets/wish.gd` (class `Wish`), `scripts/ui/wish_jar.gd`
  (class `WishJarCard`, inner `JarArt`), `tests/flows/wish.flow`.
- Changed: `scripts/pets/pet_roller.gd` (`wish` + cached weights), `scripts/core/catalog.gd`
  (`catalog.wish`), `scripts/game_state.gd` (state, `wish_changed`, `wish_open`, `set_wish`,
  `wish_pool`, `wish_shelves`, `send_to_wish`, `debug_wish`, earn `others`, save/load/migrate,
  new game), `scripts/pets/collection.gd` (`remove` drops big batches in one pass, `fallen` cap +
  `fallen_more`, `fallen_count()`), `scripts/pets/pet.gd` (`plain` cache), `scripts/ui/night_sky.gd`
  (band from `fallen_more`),
  `scripts/ui/book_view.gd` (`narrow`, wishable stickers, badge, `showcase_pet`, `look_name`,
  counts via `UiTheme.num`), `scripts/ui/collection_tab.gd` (book row + `wish_jar`, `_show_jar`),
  `scripts/ui/ui_theme.gd` (`jar` doodle + pixel icon), `scripts/dev/dev_driver.gd`,
  `data/unlocks.json`, `data/voice.json`, `tests/test_core.gd` (`_test_wish`, feature:wish allowed),
  `docs/design.md`, `docs/architecture.md`.

## Data shape

- `data/wish.json`: `{ "steps": [200, 600, 2000, 6000], "weight": [1.0, 1.5, 2.0, 3.0, 4.0], "dots": 90 }`
  (weight by full steps 0..4; dots = colour dots a jar keeps).
- Save field `wish`: `{ "on": "part:pattern:spots" or "", "jars": { book key: { "sent": n, "dots": [palette ids] } } }`.
- Collection save dict gains `fallen_more`: `{ palette id: n }` (stars past the first 14,000).

## Save bump

`SAVE_VERSION` 25 -> **26** (merge step: renumber). `fallen_more` rides without a bump (additive). Migration: `data.wish = Wish.fresh()` for
older saves; `Wish.clean` on load drops unknown looks / finish keys and clamps `sent` to 8,800.

## Flow + dev steps

- Flow `wish` (tests/flows/wish.flow): hidden before; popup; empty jar; wish spots; 100 + 100 ->
  first star + the pet's line; switch to plain (0 / 200) and back (still / 600); 5,000 (three
  stars); 8,800 (lid glows); the palettes spread (4 rows) and finishes spread fit. Shots: hidden,
  popup, empty, wished, hop, first_star, switched, three_stars, full, palettes, finishes.
- Dev steps: `wish <slot> <id> [n]` (wish for that part, found if it wasn't, n pets already in its
  jar), `wish-shelf <rarity>`, and `teach <job> others` (the other pets know it too).
- Tests: `_test_wish` (steps, can_wish, rarity shares unchanged over 20k rolls of starter + sunset
  with 6 heavy wishes, spots x4 -> 80% of common patterns, bunny x4 more on rare pets, no wish =
  identical rolls, weights/clean, GameState: hidden until box tables, who goes, fallen stars,
  first step updates the roller, switching keeps steps + boost, the 8,800 cap, save round trip,
  v25 migration). fits.flow and book.flow still pass.

## Text to add

**docs/dev-plan.md** (F3): "The wish list is built as the wishing jar (Look A): jar beside the
book, earned with box tables (`others: boxes`), steps 200/600/2k/6k, weights x1.5/x2/x3/x4 inside
the tier via `PetRoller.wish`, rarity never moves. Next in F3: the shed workshop, held landings."

**CLAUDE.md "where we left off"**:
"- The wishing jar (F3 wish list, Look A): collectibles > book gets a jar card beside a narrower
  book once the other pets learn to open boxes (unlock `wish`, earn key `others`). Tap a found part
  sticker to wish for it (the jar's label); send pets by shelf 1/10/100/all (resting only, plainest
  first, never back: night-sky stars); steps 200/600/2k/6k (data/wish.json), a gold star each, lid
  glows when full; switching keeps each jar. Full steps weigh that look x1.5/x2/x3/x4 inside its
  tier in every box (`PetRoller.wish`: part pick + signature slot), rarity never moves.
  scripts/pets/wish.gd (Wish), scripts/ui/wish_jar.gd (WishJarCard), GameState.wish /
  set_wish / send_to_wish, save v26 field "wish". Flow: wish; dev steps `wish <slot> <id> [n]`,
  `wish-shelf <rarity>`, `teach <job> others`. Sewn pets never go; the plainest = finish, traits,
  stats (`Wish.plain_key`, cached on the pet). Lost pets past 14,000 are only counted
  (`Collection.fallen_more`, the night sky's band)."
Also add `wish` to the Flows list.

**docs/design.md / docs/architecture.md**: already added in this lane (Collection book section;
`Wish` paragraph + save v26 line).

## Questions for Emilia (smallest safe pick made)

1. Unlock when the other pets learn to open boxes (box tables). OK, or later?
2. Weights x1.5 / x2 / x3 / x4 after steps 1-4: strong enough?
3. Every jar keeps its boost after you switch the wish (not only the one on the label). OK?
4. "no hat" can be wished for. OK?
5. The plainest pets of a rarity go first (finish, then fewer traits, then stats); pinned good
   pulls and pets with sewn parts never go. OK?
6. Shelves are a chip per rarity for now (C1's rarity shelves aren't on this branch): line up later.
7. The unlock popup says pets "don't come back out" (so it's never a surprise that they're gone).
   Keep that line, or say nothing (show, don't explain)?
