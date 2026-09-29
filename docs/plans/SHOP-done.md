# SHOP: the shed workshop (F3, look A): done notes (lane workshop)

**Status: VERIFIED 2026-09-29** (after the review fixes at the end; tests + balance + flows pass).
Save **v26 -> v27** (one bump from this branch's 26; renumber at merge).

Built from docs/plans/SHOP.md, picks.md (Brainstorm 3 F3, Look picks round 3: the shed workshop
look A) and lanes/mockups2 design/mockups/screens/shed-workshop.html look A + its drawings table.

## What was built

- **Opening.** Unlock `workshop` -> `feature:workshop`, `show: hidden`, earn
  `{ "ours": "shed", "open": "feature:whistle" }` (new earn key `ours`: that place must be ours).
  Popup "new: the workshop!" (go: adventures), your pet: "the shed is ours! i drew some things for
  it." Before that (and after all 8 are built) tapping the shed opens its normal place card.
- **The card (look A)** `WorkshopCard`, held by a -1° `Tilted` on the map's top left (12, 46); the
  away column stays on the right. 298 px wide sticker:
  - "the old shed" + gold "ours!" + a small muted "adventure ›" pill (swaps to the shed's place
    card, which then has a "workshop ›" pill back; question 1).
  - A wooden plank (gold-tinted deep, plank lines every 36 px) with the pinned drawings as
    `Paper`s: a dotted lilac sheet with a pink pin, the crayon art (`UiTheme.drawing`, 50 px),
    the short name (display font, shrinks to fit 82 px), a mini bar (lilac, pink when full); tilts
    -3 / 2 / -1.5°; the picked one has a dashed pink outline; a newly pinned one pops in.
  - Two need rows: "helpers" N/M (lilac meter) and "‹tier› or up" n/count (tier colour); the
    numbers go pink when met.
  - Shelf chips: one per rarity with pets that may go (`homes_can_go`), a face
    (`NewHomesStall.face_for`) and the count (`UiTheme.num`, "2M"); the picked one is stitched pink
    and tilted -2°. Default pick: the first shelf that counts toward the drawing's tier.
  - 1 / 10 / 100 / all ("all" with the pink seam), "not yet" (closes: "i'll be in the shed if you
    need me!") and "build it! ♥" (pink and nudging when the picked drawing is full).
  - Voice (data/workshop.json): open "welcome to the workshop!", picking a drawing says its `say`,
    a take cheers ("hi helpers!", "more hammers!", ...), full: "that's everyone! let's build it!",
    nothing could go: "hmm, we need some fancier helpers.", built: its `done`.
- **Rules** (`Workshop`, scripts/idle/workshop.gd, pure): 3 drawings pinned at once, all fill at
  the same time; `useful` = pets below the tier only while there's room for the ones still needed
  at the tier; `take` never overfills; `build` (only when full) marks it built and pins the next
  drawing from the list in the same spot (empty spot when the list is out); `clean` repairs saves.
- **Helpers** (`GameState.send_helpers`): plain pets through `homes_pick` (never favourites, the
  active pet, new parts, holo+, pets away, pinned pulls, party leaders), off errands / machines
  first, then `Collection.leave(counts, uids, false)`: gone for good, **no star**, no `pets_left`.
  Pets only (no wisps).
- **Built things on the map** (`MapView._draw_built`, backyard only): lilac crayon drawings at
  their `at` (map units), size 48 x `size` px at the usual zoom; a just-built one pops up with a
  glow; the letterbox shows a pink count pill on its left while postcards wait (tap it).
- **The chores** (each checked against picks.md):

  | drawing | need | takes away | stays yours |
  |---|---|---|---|
  | bell rope | 40, 5 rare+ | trips you sent are welcomed back by themselves (`_ring_bell`, every second); their postcards pop up one at a time on the map when no card is open | the trip you're watching on the trail; your pet's own trips already welcome themselves |
  | toy shelf | 60, 10 epic+ | a play that ends starts again, same toy, same length (`_finish_plays`, also at load); "again!" by its clock | picking a new toy: tap the playing toy for a last round (tap again: once more), then its spot is free |
  | weather vane | 120, 20 epic+ | a trip waiting at a **plain** choice (no option at that place is risky) takes your last pick for that event at that place (`Workshop.vane_pick`) | every risky choice; the trip you're watching; a choice you never made there |
  | chore chart | 250, 40 epic+ | every errand has "new pets join here" (`job_joins`), the errands' switches go away | machines / tables (the whistle's) |
  | garden spade | 500, 5 legendary+ | twinkling rummage spots are dug through by themselves | |
  | sewing basket | 1000, 10 legendary+ | toys not being played with lose 0.1 wear an hour (stitched once a minute; also while closed, up to 12 h) | fixing at the workbench still works |
  | treat banner | 2000, 25 legendary+ | on the trail a treat is tossed whenever one's ready | |
  | letterbox | 5000, 60 legendary+ | postcards wait in the letterbox (at most 30, not saved) until you tap it | a trip you welcome back yourself still shows its postcard right away |

  Never a drawing (manual on purpose): the school bell, reel banking, the newest globe's lever,
  ripping boxes yourself, risky trip choices (none of the first three exist in this branch yet).

## Files

- New: `data/workshop.json`, `scripts/idle/workshop.gd`, `scripts/ui/workshop_card.gd`,
  `tests/flows/workshop.flow`, this file.
- Changed: `scripts/game_state.gd` (workshop state, save/load/migration, chores, `watching`,
  `postcards`, `ours` earn key, `job_joins`), `scripts/pets/collection.gd` (`leave(..., star)`),
  `scripts/machine/toys.gd` (`play` id, `ending`, `mend`), `scripts/core/catalog.gd`
  (`catalog.workshop`), `scripts/ui/adventures_tab.gd`, `scripts/ui/map_view.gd`,
  `scripts/ui/trail_view.gd`, `scripts/ui/errands_tab.gd`, `scripts/ui/ui_theme.gd`
  (`drawing()`), `scripts/ui/new_homes_stall.gd` (`face_for`), `scripts/dev/dev_driver.gd`,
  `data/unlocks.json`, `tests/test_core.gd`, `tools/balance.gd`, `docs/design.md`,
  `docs/architecture.md`.

## Data shape

- data/workshop.json: `pinned` (3), `takes`, `basket_mend_per_hour` (0.1), `letterbox_keep` (30),
  voice lines (`cheer`, `fancier`, `ready`, `open_say`, `close_say`), `drawings` [{ id, name,
  need, tier, count, at [x, y] map units, size, chore, say, done, art (SVG path bodies on 48 x 48) }].
- Save field `workshop`: `{ pinned: [id | "", x3], prog: { id: { sent, qual } }, built: [ids],
  helpers, vane: { "place:event": option index } }`. Toys' `playing[]` gain `play` and `again`
  (bool, default true: false after a tap means the shelf leaves that play when it ends).
- Bell postcards (`GameState.postcards`, not saved) carry `news` and `announce` (what your pet says
  about that trip, told when its postcard pops up).

## Save bump

**v26 -> v27** (renumber at merge). Migration: none needed in `_migrate` (a comment): `load_game`
runs `Workshop.clean(catalog, data.workshop)`, which gives older saves `Workshop.fresh` (bell,
shelf, vane pinned, nothing built); old plays load with `play: ""` (the shelf doesn't hand them).
The merged-save test now expects v27.

## Flows and dev steps

- `python3 tools/play.py workshop` (PASSED; shots: workshop_popup, map_ours, workshop_card,
  workshop_full, workshop_pick, workshop_built(_pop), map_bell, shed_place_card, bell_postcard,
  workshop_two, workshop_crowd (2M commons), workshop_banner_full, trail_banner, map_all,
  letterbox_waiting, letterbox_postcard; `expect fits` all along). `fits` PASSED. Also re-ran
  postcard, next_door, party, toys, errands, whistle, new_homes: all pass (new_homes failed once on
  its cheer line and passed three times after: looks like a bubble line talked over it).
- Dev steps: `walk` (every trip walks on to its next stop, from any tab), `helpers <drawing> <n> [qual]` (helpers for free), `build <drawing>` (built for free,
  next pinned), `expect built <id>`, `expect postcards <n>`; `visit` now also runs
  `check_unlocks` (a place turning ours can open the workshop).

## Tests

`_test_workshop` (data: 8 drawings in order, real tiers, count <= need, needs grow, art, spots
clear of places and each other; the unlock's earn; fresh; useful / take math; build pins in the
same spot; all built; clean on junk; the vane: nothing remembered, plain, a pick the party can't
take, risky, auto runs; Toys.ending / mend) and `_test_workshop_game` (v26 save -> fresh
workshop; old plays; the unlock needs ours AND whistle; helpers leave with no star, never the
active pet or a favourite; build; the bell: not the watched run, not auto runs, postcards capped;
the vane in the game: remembers your answers, skips the watched run, never risky; the shelf; the
chart; the spade; the basket; a round trip). ALL PASSED (4167 checks). balance.gd prints the
helpers per drawing (8,970 for all 8).

## Text to add

**dev plan** (under F3 / phase F):
> - **The shed workshop (F3, look A): built** (lane workshop, save v27). Once the old shed is ours
>   and the whistle is found, tapping the shed sticks a workshop card on the backyard map: 3
>   drawings on a plank fill at once from shelf chips (1/10/100/all, pets only, helpers stay on for
>   good with no star), "build it!" pins the next; 8 drawings take chores away (bell rope, toy
>   shelf, weather vane plain choices only, chore chart, garden spade, sewing basket, treat banner,
>   letterbox). Next: tune the needs against the herd at whistle time (pace sim); held landings.

**CLAUDE.md "where we left off"**:
> - The shed workshop (F3, look A; lane workshop, save v27): unlock `workshop` (earn `ours: shed` +
>   `open: feature:whistle`); tapping the shed opens `WorkshopCard` on the map (3 pinned drawings,
>   needs, shelf chips, 1/10/100/all, not yet / build it!; "adventure ›" / "workshop ›" pills).
>   Rules `Workshop` (scripts/idle/workshop.gd), data/workshop.json, save field `workshop`,
>   helpers via `send_helpers` (homes_pick, `Collection.leave(..., false)`: no star). Chores in
>   GameState (`_ring_bell`, `_vane`, `_finish_plays`, `_workshop_chores`, `job_joins`), the map
>   draws built things + the letterbox (`letter_picked`), the trail's banner tosses treats. Dev
>   steps `walk`, `helpers`, `build`, `expect built|postcards`. Flow: workshop.

**docs/design.md / docs/architecture.md**: already edited in this lane (a design bullet after
"Next door" in Adventures, the Stars line; an architecture paragraph after the v26 one).

## Questions for Emilia (what's built if there's no answer)

1. Trips to the shed once the workshop is open: built a small "adventure ›" pill on the workshop
   card (swaps to the shed's place card) and a "workshop ›" pill back. OK, or something else?
2. The chore chart overlaps "new pets join here" (which already does its job): built as "every
   errand joins, the switches go away". Or should it take away a different chore?
3. Treat banner: built as a full treat whenever one's ready (treats are the watching-a-party bit).
   Or a smaller treat?
4. Letterbox: every postcard the bell welcomes waits in it; ones you welcome yourself (the trip
   you watched) still pop up right away. Waiting postcards aren't saved (a restart drops them; the
   loot is already yours). OK, or only trips that came home while the game was closed?
5. The weather vane: your last pick per event per place; its own picks don't count as yours; it
   also leaves the trip you're watching on the trail alone (you're right there). Right?
6. The bell rope also leaves the watched trip to you (it waits for "welcome back" on the trail).
   And its postcards pop up by themselves on the map when no card is open: OK?
7. Needs are the mockup's (40 .. 5000, 8,970 for all 8); at whistle time players may have far
   more pets. Tune with the pace sim later?

## Review fixes (second pass)

- **Toy shelf loop:** a play the shelf hands again now shows "again!" by its clock; tapping the
  playing toy (ToysView `playing_<edition>`) flips `again` (`GameState.toy_again`,
  `Toys.flip_again`, voice `toy_again` / `toy_last`), so the play still isn't disturbed but the
  spot frees up when it ends. `_finish_plays` saves when it hands a play again.
- **Sewing basket:** mends once a minute (`_mend_acc`), so `toys_changed` no longer fires every
  second (ToysView / WorkbenchTab / MachineTab / Spine stop rebuilding every tick).
- **Built things on the map:** `_draw_built` rasterises each drawing once at its resting size
  (zoom rounded to 4 px steps) and scales it into the popping rect: no SVG raster per frame.
- **Stale trail:** `AdventuresTab._drop_stale_trail` (on showing the tab, and every 0.5 s) goes back
  to the map when the trail's trip was welcomed back by the bell rope; its postcard then pops up.
- **Bell postcard news:** `_ring_bell` stores `news` and the new `announcements` with each postcard
  and clears them; `_show_postcard` hands them back before `speak()`, so your pet talks about the
  trip on the card.
- **Workshop card:** redraws at most every 0.4 s while dirty, and when the pinned drawings, the
  picked one and the shelves are the same it only refills the Papers' bars (`Paper.refill`) and the
  chip counts in place (no freed buttons mid-click).
- Flow workshop gained: leave the tab while watching a trip (the bell takes it, back on the map
  with its postcard: `bell_came_back`), and the shelf's "again!" / last round (`shelf_again`,
  `shelf_last`). Tests: +6 checks (4173). Flows re-run: workshop, fits, toys, postcard, next_door,
  whistle: all pass.
