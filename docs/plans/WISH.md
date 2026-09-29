# WISH: the wishing jar (F3 wish list), build plan

From docs/picks.md (Brainstorm 3 F3 + Look picks round 3, Look A) and the mockup
lanes/mockups2/design/mockups/screens/wish-list.html (Look A).

## What it does

- Collectibles > book gets a side column: the **wishing jar** card beside a narrower book spread.
- Tap a sticker you've found on a part page (bodies, palettes, patterns, eyes, accessories; not
  the finishes pages) to wish for it. It becomes the jar's label; the sticker in the book gets a
  small jar badge + pink dashed outline.
- Send pets by shelf (a chip per rarity with a count), 1 / 10 / 100 / all. Every pet counts 1,
  they never come back (Collection.remove: each one adds a night-sky star).
- 4 steps of 200 / 600 / 2000 / 6000 (8,800 in all). A gold star on the jar's side per full step,
  the lid glows when all 4 are full, then sending stops for that look.
- Switching the wish keeps every sticker's filled steps (switch back and it's where you left it).
- Each full step raises that look's weight INSIDE its already-rolled tier in every box (your rips,
  your pet's opening, box tables, the machine's pet box): all go through GameState._roller.
  Rarity never moves.
- Your pet cheers on every send, a special line per full step, one for the full jar.

## Unlock (hidden until earned)

- New unlock `wish` opens `feature:wish`, earn `{ "others": "boxes" }`: once you've taught the
  other pets to open boxes (box tables = pets start arriving steadily). New earn key `others` in
  GameState._earned (knows_others); teach_others() calls check_unlocks().
- Popup "new: a wishing jar!", go to collectibles, opened on the book. Before it: the book looks
  and works exactly as now (no column, taps do nothing).

## Files

- **data/wish.json** (new): `{ "steps": [200, 600, 2000, 6000], "weight": [1.0, 1.5, 2.0, 3.0, 4.0],
  "dots": 90 }` (weight = the look's multiplier by full steps 0..4; dots = colour dots kept per jar).
- **scripts/pets/wish.gd** (new, pure rules, class Wish): fresh(), clean(catalog, saved),
  can_wish(catalog, key) (part keys only), where(catalog, sent) -> { full, done, have, need },
  room(catalog, sent), weights(catalog, state) -> { part_key: x } for every look with a full step,
  goers(pets, rarity, n) (which pets go: plainest first = normal finish, then lowest stat total).
- **scripts/pets/pet_roller.gd**: `var wish := {}` (part_key -> x). Empty = today's exact code
  path (same RNG use). Set: `_pick_part` picks with Weighted.pick over the tier's options (wished
  part weighted x); `_signature_slot` weights each candidate slot by the mean weight of its parts
  at that tier (so a lone rare body like bunny still turns up more on rare pets). Tier roll and
  the `_best_rank_in` cap are untouched.
- **scripts/core/catalog.gd**: load data/wish.json (`catalog.wish`).
- **scripts/game_state.gd**: `var wish := Wish.fresh()`, `signal wish_changed(step: int)`
  (step = the step that just filled, 0 if none), wish_open(), set_wish(key), wish_shelves() ->
  { rarity: resting pets }, send_to_wish(rarity, n) -> { sent, before, after }. Pets that can go =
  resting_pets() minus pinned (never the active pet, pets away, on errands, workers). Keeps
  `_roller.wish` in step on load, new game, set and send. Save field `wish`.
  SAVE_VERSION 25 -> 26, migration: `wish` = fresh for older saves.
- **data/unlocks.json**: the `wish` entry. **data/voice.json** ui lines: wish_pick
  ("{name}! ooh, good one."), wish_send (in you go! / plop! / it's filling up!), wish_step_1..4
  (one each, "a star!!", ...), wish_done ("all the stars! it's full!").
- **scripts/ui/wish_jar.gd** (new, WishJarCard): the side card.
- **scripts/ui/book_view.gd**: a `narrow` mode while the jar is up (3 columns, tiles ~74x84,
  12 px page margins); found part stickers are tappable then (-> set_wish); wished badge + outline;
  static showcase_pet(slot, id) for the label.
- **scripts/ui/collection_tab.gd**: book mode = HBox(BookView, WishJarCard ~220 px) when
  feature:wish is on.
- **scripts/ui/ui_theme.gd**: a `jar` doodle icon (from the mockup's JAR_ICO), pixel version too.
- **scripts/dev/dev_driver.gd**: steps `wish <slot> <id> [sent]` (set the wish, optionally its
  sent count, for jumping to later fills) and `wish-shelf <rarity>` (pick a chip).

## UI sketch (920x600, must `expect fits`)

```
| spine | pets toys [book]          found 31 of 71 stickers |
|       | [bodies][palettes][patterns]...   +--------------+
|       | +-----------+-----------+         | wishing jar  |
|       | | patterns  | eyes      |         |   ___lid___  |
|       | | [] [] []  | [] [] []  |         |  |  .:.:.  |*|  <- 4 stars down the side
|       | | [] [] []  | [] [] []  |         |  | [label] |*|     gold when full
|       | | [gift]    | [gift]    |         |  |.:.:.:.:.|*|  <- dots in the sent pets'
|       | +-----------+-----------+         |  |_________|*|     palette colours
|       |                                   |   412 / 600  |
|       |                                   | [c][u][r][e] |  <- chip per rarity: pet + count
|       |                                   | [1][10][100][all]
```

- Jar drawn in _draw: jar outline polygon, fill = Geometry2D.intersect_polygons(jar, below the
  level), 3 dashed step lines, dots seeded inside the fill (colours from the jar's saved dots),
  a wavy top line while filling, 4 stars, a gold glow on the lid when done.
- Label: a Tilted sticker over the jar (PetPortrait of the showcase pet, name, tier in its colour).
  No wish yet: the jar is empty, no label, the send buttons disabled (no hint text).
- Chips only for rarities you have resting pets of; picked chip dashed pink + tilted. Buttons
  disabled when the shelf is empty or the jar is full.
- Send: up to 8 small pet portraits hop from the chip into the jar (tween), a gold star floats up
  when a step fills; pet line via PetBubble.say_line.

## Flow: tests/flows/wish.flow

from after_tutorial, view full, tab collection, click "book": no "wishing jar" (hidden), fits,
shot. `stickers off`, `unlock feature:wish`, `pets 1200`, `book patterns`: jar shows empty, fits,
shot. Click "spots": label on, shot. Click "100" twice: "200"... first star, pet line
"a star!!", shot. Click another sticker: its jar at 0 / 200; click "spots" again: still one star.
`wish pattern spots 8800`: "8,800", lid glow, buttons disabled, shot. Also a spread with 4 rows
(palettes) with the jar up: fits.

## Tests (tests/test_core.gd, _test_wish)

- Wish.where: 0 / 199 / 200 / 800 / 8800 give the right full steps, have/need, done.
- can_wish: part keys yes, finish keys no, unknown no.
- **Rarity unchanged**: 20k rolls of the starter box (and one better box) with no wish vs the top
  wish on several looks: each tier's share within 1.5 points.
- **Weight works**: a common pattern's share among common-pattern picks rises about as the weight
  says; a lone-at-tier part (bunny) turns up more on rare pets via the signature slot.
- No wish = identical rolls to before for the same seed.
- GameState: send_to_wish takes resting pets only (not active/away/on errands/workers), adds that
  many to `fallen`, stops at 8,800, keeps the other sticker's steps on a switch, updates
  `_roller.wish` after a full step; unlock earn `others`; save round trip; v25 save migrates.
- Balance run stays green.

## Save bump

SAVE_VERSION 25 -> 26 (field `wish`: { "on": part key or "", "jars": { key: { "sent": n,
"dots": [palette ids, last 90] } } }). The merge step renumbers.

## Questions for Emilia (smallest safe pick made)

1. Unlock: when the other pets learn to open boxes (box tables). OK, or later (the herd / C1)?
2. Weights x1.5 / x2 / x3 / x4 after steps 1-4 (data/wish.json): strong enough?
3. Every sticker keeps its boost from its filled steps even after you switch the wish (not only
   the one on the label). OK?
4. "no hat" can be wished for (it's a sticker you found). OK?
5. Which pets go when you send 10: the plainest of that rarity first (normal finish, lowest
   stats). Pinned good pulls never go.
6. "Shelves" = a chip per rarity (C1's shelves aren't built on this branch); align with C1 later.
