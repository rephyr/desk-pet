# B1 pack tiers: done (lane b1)

Look C (today's counter) from design/mockups/screens/shop-tiers.html, names from docs/picks.md.

**Status: VERIFIED (2026-09-28).** Built, reviewed, tests + balance + flows passing on lanes/b1.

## What was built

- **Three tiers** in data/boxes.json: **sunny box** (id stays `starter`, page backyard, 50 coins,
  1 pet), **sunset box** (`sunset`, page beyond, 400, 2-3 pets), **midnight box** (`midnight`,
  page `next_door`, 3200, 2-3 pets). `next_door` isn't a page in data/unlocks.json yet, so the
  midnight box never shows in the shop (data only; `tiers all` shows it for testing).
- **Better per tier**: rarity odds (common 60% / 38% / 18%), traits, and gated finishes
  (sunny: shiny, holo, ghost; sunset + glitch; midnight + prismatic; glitch and prismatic left the
  sunny box).
- **New looks** (gated parts, data/parts.json `"from": "<box id>"`, existing parts, no new art):
  sunset: fox (body, epic), stars (pattern, epic), gold (palette, legendary); midnight: dragon
  (body, legendary), halo (accessory, epic), midnight (palette, rare). A lower box that rolls
  that rarity steps down (a sunny legendary gets crown / x-eyes / circuit, never dragon or gold).
  Trip parts follow the place's box too (backyard places are sunny, cellar and further down now
  bring sunset boxes and sunset looks).
- **Lucky box retired**. Save migration: lucky boxes on the pile become sunset boxes 1:1.
- **Shop (boxes tab, look C)**: two columns. Left: a counter row per tier in the shop, newest on
  top: map-page stamp (crayon doodle in a dashed circle: house / fence / moon, page name on
  hover), the pack (1-3 stars printed on it; odds on hover), name, gold tilted "new!" tag,
  "new looks" stickers (tiny plain pets wearing each gated look, named on hover), coin price chip +
  1/10/50 chips, "inside" shapes (1 for sunny; 3 for sunset, the 3rd fainter = 2-3; "2-3 pets
  inside" on hover), stepper, buy. A new tier's row glows gold while it's new. Below: "your
  stash", a pile per kind (every shop tier plus anything else on the pile, smaller packs when
  there are several), "open" + 1 / 10 / all. Right (232 px): your pet, and with the boxes job its
  card: master switch, a switch per tier (stamp + name; on = your pet opens it, off = saved for
  you, same `saved_boxes`), then the piggy bank part as before.
- **A tier arriving**: when its map page opens, the next time you see the boxes tab its row pops in
  with a gold sparkle and your pet says the box's `arrives` line (once per save, waits for unlock
  cards and openings). The spine's boxes tab gets its news dot until then. The gold "new!" tag
  stays until you buy your first box of it (never on the sunny box).
- **One box, 2-3 pets**: the pack ritual plays for the best pet; the result card gets an "also
  inside" row of small framed portraits (name + rarity on hover). **Open 10 / all**: BoxReveal
  counts boxes and pets apart ("opening 10 boxes…", "open 10 more" = boxes, "27 pets!").
- **Automation**: your pet (auto_open_pack) opens one box and shows its best pet, logs every pet,
  pins good ones; it opens and buys only switched-on tiers (buys only tiers in the shop, the
  cheapest it can afford, as before). **Workers now count boxes, not pets** (`_workers_open` used
  to add `pulled.size()`, which would open 2-3x too many sunset boxes).

## Files

- data/boxes.json (rewritten), data/parts.json (`from`), data/adventures.json (cellar, below:
  `"box": "sunset"`)
- scripts/pets/box_shop.gd (new, `BoxShop`): `open_tiers`, `split_open`, `best_first`,
  `migrate_retired`
- scripts/core/catalog.gd: `parts_in(slot, tier, box)`, `box_rank`, `shop_boxes`, `new_looks`
- scripts/pets/pet_roller.gd: gating through `parts_in`, `roll_box(box_id, force_tier)`
- scripts/adventure/rewards.gd: `roll_part` gated by the box
- scripts/game_state.gd: `shop_boxes`, `box_in_shop`, `stash_boxes`, `box_is_new`, `box_news`,
  `greet_box`, `pet_box_order`, `boxes_bought`, `boxes_greeted`, `debug_all_tiers`; `open_boxes`
  returns every pet of every box; `buy_boxes` only sells shop tiers and counts; `next_pet_box`,
  `auto_open_pack`, `_workers_open` handle tiers; save v23
- scripts/ui/boxes_tab.gd (look C; inner classes PileArt (size per pack width), Stamp, Inside,
  Sparks), scripts/ui/box_reveal.gd (`play(pets, boxes)`), scripts/ui/reveal/pack_opening.gd +
  reveal_result.gd ("also inside"), scripts/ui/pack_art.gd (stars), scripts/ui/crayon.gd (fence,
  moon doodles), scripts/ui/unlock_popup.gd (`UnlockPopup.up`), scripts/ui/expanded_view.gd
  (boxes news dot)
- scripts/dev/dev_driver.gd: click target `name:<node name>`, step `tiers all | off`
- tests/test_core.gd (`_test_box_tiers`, odds for sunset + midnight), tools/balance.gd (box tiers
  table), tests/flows/box_tiers.flow (new), boxes.flow + unlock_popup.flow (new button names)
- docs/design.md (Loot boxes), docs/architecture.md (Pets, saves)

## Data shape

```json
{ "id": "sunset", "name": "sunset box", "page": "beyond", "stamp": "fence", "price": 400,
  "pets": [2, 3], "arrives": "new boxes! they came all the way from beyond the fence.",
  "art": { "foil": ..., "foil_light": ..., "foil_dark": ..., "edge": ..., "logo": ..., "stars": 2 },
  "tiers": { ... }, "finishes": { ... }, "traits": [0, 40, 40, 20] }
```

Parts: `{ "id": "fox", "name": "fox", "rarity": "epic", "from": "sunset" }`.

## Save bump

**v22 -> v23** (renumbered to **v26** at the merge, after main's v23 scout notes, v24 stickers and v25 reserve). Nothing
in the lucky-box fix hangs on the number: `BoxShop.fix_retired` runs on every load (idempotent,
right after `_migrate`): `bag.lucky` -> `bag.sunset` (1:1, added to any sunset already there),
`saved_boxes` "lucky" -> "sunset", runs' `loot`, `log[].loot` and pre-v5 `boxes` "lucky" ->
"sunset"; load_game then drops bag ids the catalog doesn't know. New fields `boxes_bought`
{ id: n } and `boxes_greeted` [ids]: a save without `boxes_bought` gets every kind already on the
pile (so migrated boxes get no "new!" and no arrival); a save that has them keeps them. So the
renumbered version only needs the comment in `_migrate` moved; no code depends on it. Pets keep
`box: "lucky"` (just a string on the pet).

## Flows, tests, dev steps

- `python3 tools/play.py box_tiers`: sunny only -> find intel_fence -> sunset pops in with "new!"
  -> buy 10 (tag gone) -> teach boxes, job card with a switch per tier (sunset off shows "saved for
  you") -> open 1 (ritual, "also inside") -> open all -> piggy bank + `tiers all` -> 3 tiers fit.
- Re-run and passing: boxes, fits, home_pile (pile_full's lucky:3 loads as sunset 3), pet_box,
  unlock_popup, workers, automation, tutorial, postcard, gear.
- `godot --headless -s tests/test_core.gd`: odds for sunset and midnight over 100k rolls, finish
  and look gating, pets per box, shop tiers per open page, workers count boxes, the migration.
- `godot --headless -s tools/balance.gd`: a "box tiers" table (pets/box, coins/pet, avg rank,
  rare+, chance of a new look per box).
- Dev: `click name:<node>` (buy_<id>, amount_<id>_<n>, open_<id>_1/10/all, pile_<id>, let_<id>,
  boxes_job), `tiers all` / `tiers off`.

## Review fixes (second pass)

- Lucky -> sunset no longer tied to save v23 (see Save bump): a save written by main (v23/v24)
  with lucky boxes loads them as sunset boxes instead of losing them (or leaving a news dot on
  forever).
- "new" tags: `Collection.new_keys(box_pets)` works out the looks a whole box brought for the
  first time (two pets sharing a never-seen look both counted it, so neither showed "new"). The
  best pet's card shows them; an "also inside" pet bringing another new look gets a gold frame
  with "new ..." lines in its tooltip.
- Boxes tab: the arrival check runs only when something changed (`_greet_pending`, set by
  `_refresh`, visibility, and kept while an unlock card or opening blocks it); offer row styles
  are built once per tab and only swapped when "new" changes.
- `Catalog.parts_in` / `box_rank` cached; PetRoller caches signature-slot options and capped odds.
  5000 sunset boxes: 1.39 s -> 0.68 s to roll (debug headless). Box workers open at most
  `GameState.WORKER_BOXES_MAX` (2000) boxes per go; the rest wait on the pile.
- `UnlockPopup.up` is cleared when the popup leaves the tree while showing (look change).
- The scrapyard's uncommon parts go through `parts_in` (no better-tier looks from errands).
- The plain pet on the new-looks stickers / inside outline comes from `catalog.default_part`
  (`BoxesTab.plain()`), no part ids in UI code.

## Text to add elsewhere

**docs/dev-plan.md**, B1 heading: `### B1. Pack tiers per map page  (VERIFIED 2026-09-28)` and add:

> - **Built:** sunny / sunset / midnight boxes (data/boxes.json: page, stamp, pets, arrives),
>   gated finishes and new looks (parts.json `from`), lucky box retired (BoxShop.fix_retired on
>   every load: lucky -> sunset),
>   look C shop (counter row per tier with stamp, new looks stickers, inside shapes; stash pile per
>   tier; a switch per tier on the job card), a tier pops in once with a sparkle + "new!" until
>   bought, one box with 2-3 pets = ritual for the best + "also inside", workers count boxes.
>   Midnight waits for the next-door page (E2). Flow box_tiers.

**CLAUDE.md "Where we left off"**, new bullet:

> - B1 pack tiers (lane b1): sunny box (id `starter`) / sunset box (beyond the fence, 2-3 pets) /
>   midnight box (page `next_door`, data only until that page exists). data/boxes.json page, stamp,
>   pets, arrives; parts.json `from` = new looks only from that tier up (sunset: fox, stars, gold;
>   midnight: dragon, halo, midnight); finishes gated (glitch from sunset, prismatic from midnight).
>   BoxShop (scripts/pets/box_shop.gd) has the tier rules; Catalog.parts_in, PetRoller.roll_box,
>   GameState.shop_boxes / stash_boxes / box_is_new. Lucky box retired: BoxShop.fix_retired turns
>   lucky boxes into sunset boxes on every load (not tied to a version); save v23 adds
>   boxes_bought + boxes_greeted (filled from the pile when missing). Boxes tab = look C (counter row per tier,
>   stash pile per tier, a switch per tier on the job card). One box with 2-3 pets: ritual for the
>   best + "also inside". Workers count boxes, not pets. Flow box_tiers; dev steps `tiers all`,
>   click `name:<node>`.

## Questions for Emilia (the smallest safe pick was made)

1. Old lucky boxes became sunset boxes 1:1 (not refunded).
2. New looks: sunset = fox, stars, gold palette; midnight = dragon, halo, midnight palette. Fox is
   the only epic body and dragon the only legendary body, so a sunny box's epic/legendary pets
   are never those bodies now, and the midnight looks can't be pulled at all until next door
   exists (pets that have them keep them). OK, or new looks instead?
3. One box with 2-3 pets: one ritual for the best + an "also inside" row. Or a ritual per pet?
4. Only the cellar and further down bring sunset boxes (and sunset looks); should every
   beyond-the-fence place?
5. The boxes tab often opens after beyond the fence, so the sunset box can be there (with "new!"
   and its arrival) the first time you see the tab.
6. The sunny box keeps the id `starter` in data and saves (only the name shows).
7. With the piggy bank your pet still buys the cheapest switched-on tier it can afford. Should it
   buy the best one it can afford instead?
8. The book still lists every part, including midnight looks nobody can pull yet (hidden until
   earned?). Not touched here since the book is being reworked in A4.
