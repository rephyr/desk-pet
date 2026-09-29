# F1/F2 done: the plushie machine (look A, the cabinet) + buttons

Branch `lanes/plushie`. Built from docs/dev-plan.md F1/F2, docs/picks.md (F1 lines, Details, Look
picks round 2, Brainstorm 3) and design/mockups/screens/sacrifice-reels.html look A.

## What was built

- **The machine**: a third workbench page, `your pet | toys | plushie machine`, fully hidden until
  `feature:plushie`. Pink cabinet with a hopper funnel (the fed pet bobs in it, spins and nudge
  dots on the left, name / tier / traits on the right), bulbs that blink while rolling, a part name
  over each of 5 reels, the reels (3 cells, roll + land one by one ~170 ms apart with a bounce),
  under each reel its button marks (sewn / held / room), its odds (button / blank / crack %) and
  bank / hold (or "kept!" / "full!"), a ▼ nudge tab on a fresh reel, the lever, the spin button
  (spin! / next! / empty!). Side card: keeper (portrait, name, buttons, ‹ ›), hopper rows by
  rarity (a face, the shelf's herd count, how many wait, +) or the card pets picker, wisps (big,
  coral), the shop (nudges, holds, wild reel). The wild 6th reel appears for the pet it was bought
  for, with ‹ part › on its head.
- **Rules** (`Plushie`, pure): keeper, hopper (best pet hops in first), spins by rarity, nudges by
  finish, trait tilts, odds by a part's buttons (crack floor), auto-bank of unheld reels, hold
  doubles, crack clears, blank keeps, cap at 5 minus the part's buttons, full parts don't spin,
  bank, hold limit (2 + bought), nudge (the cell above lands, re-resolves from before the spin),
  spins run out -> everything held is banked and the next pet hops in, wisps per miss (x2 crack, x
  perfection, x greedy), shop prices, wild reel (default: fewest buttons; ‹ › skips full parts; its
  button sews on at once).
- **Buttons**: `Pet.buttons` (slot -> 1..5), always a card, knacks x (1 + 0.5 per button) in
  `Knacks.of / sum_in / parts`, tiny pink buttons round the knack badges' rims (details and the
  shelf cards' corners), grafting keeps them (`slot:id@n` bag keys; the part sticker shows them,
  the sewing card has a "buttons" row).
- **Wisps**: `GameState.wisps`, `grant_wisps(n)`, `grant({ "wisps": n })`; colour `wisp` (candy
  floss coral) in all 5 themes; doodles `wisp`, `button`, `reel_blank`, `reel_crack`.
- **Opening**: one hook. Unlock `plushie` in data/unlocks.json: earn `{ find: plushie_machine }`,
  opens `feature:plushie` + `tab:inventory`, `button_gift: 1` (sewn on the active pet's best-knack
  part, else the emptiest part), popup (go: inventory; the workbench flips to the machine page).
  The find `plushie_machine` has `given_by` (nothing in the game gives it yet); **E3's last room
  only has to call `GameState.grant({ "find:plushie_machine": 1 })`**. Dev step `open-plushie`.
- Your pet cheers every spin, then "a new button!!" or "oops, a bit of fluff!"; lines in
  data/voice.json `plushie*` (never winks). The workbench tab says its toys line when it opens on the
  toys page (the your pet and plushie pages speak for themselves when they show).

## Review fixes (F1 review round)

- The keeper stays home: `sendable_pets()` leaves it out while the machine is open (covers the
  adventures tab, auto parties and worker parties, which all go through `send_on_adventure`).
  `plushie_keeper()` is read-only: null while the saved keeper is away (old saves); only when none
  is picked or it's gone for good does the first keeper take over, and anything held is banked onto
  it first (`Plushie.set_keeper(catalog, state, pet)` returns what it sewed).
- Banked reels stay banked across a keeper swap (only `next_pet` clears them): swap there and back
  no longer spins a banked reel again. `plushie_swap` also works while the keeper is away (nothing
  held).
- `plushie_feed_herd` finds the pet first, then takes it off a job; `_herd_off_places` returns how
  many it took (new `_herd_at_places`), and a count with nobody resting or working is not picked.
- UI speed: `plushie_can_swap()` is a cheap count; `plushie_has_cards()` stops at the first card;
  the picker only scans cards while open and shows 20 a page (‹ n/m ›); hopper rows are rebuilt only
  when the rarities shown change (marked by plushie / herd / pets / jobs / automation / adventures
  signals), counts and + update in place, so clicks aren't lost to a rebuild every second.
- `Lever.enabled` redraws the knob; Hopper and ReelView skip `_process` while hidden.
- The wild reel's buy button says "on!" only when it's on; it's hidden when every part is full.
- `Plushie.can_hold` and `Plushie.wild_available` are the one place for those rules (the UI uses
  them). Prices cap at `shop.max` in data/plushie.json (no more `Jobs.MAX_PRICE`).
- `Knacks.size(..., buttons := 0)` replaces `_sized`.
- New checks: bank, swap, swap back (still banked), a new keeper gets what's held, the next pet
  starts every reel, can_hold, no wild reel when full, price cap, knack size with buttons, the keeper
  isn't sendable, an away keeper leaves the reels alone, nothing taken off a job for nothing. The
  plushie flow pages the picker (40 more pets, "1/*", shot cards_pages).

## Files

New: data/plushie.json, scripts/machine/plushie.gd, scripts/ui/plushie_machine.gd,
tests/flows/plushie.flow, docs/plans/F1.md, docs/plans/F1-done.md.
Changed: scripts/game_state.gd, scripts/pets/pet.gd, scripts/pets/collection.gd,
scripts/pets/knacks.gd, scripts/pets/grafting.gd, scripts/core/catalog.gd,
scripts/ui/workbench_tab.gd, scripts/ui/inventory_tab.gd, scripts/ui/knack_badge.gd,
scripts/ui/ui_theme.gd, scripts/dev/dev_driver.gd, data/unlocks.json, data/themes.json,
data/voice.json, tests/test_core.gd, tests/flows/fits.flow, docs/design.md, docs/architecture.md.

## Data shape

data/plushie.json: `spins` (by rarity), `nudges` (by finish), `button` / `crack` (% by the part's
buttons 0-4), `crack_min`, `puff` (by rarity), `crack_puff`, `perfection`, `max_buttons`,
`knack_per_button`, `holds`, `hopper_max`, `shop` { nudge { wisps, grow }, hold { wisps, grow },
wild { wisps }, max (price cap) }, `traits` { id: { button | crack | spins | wisps } }. All placeholders.

Save state `plushie`: `{ keeper, hopper: [pet dicts], nudges, bought: { nudge, hold }, try: { fed,
spins, spins_max, reels: [5 x { strip, held, hold, banked, fresh, before, was_hold }], wild: {} or
{ slot, strip } } }`.

## Save bump (merge: renumber!)

**SAVE_VERSION 23 -> 24** on this branch. Adds top-level `plushie` and `wisps`, optional `buttons`
on pet dicts, bag keys `slot:id@n`. Migration: nothing to move (a comment in `_migrate`); older
saves load an empty machine and 0 wisps. The dungeon lane also adds wisps: unify on
`GameState.wisps` + `grant_wisps` (this branch's `grant()` also takes `"wisps": n`).

## Flows and checks

- `tests/flows/plushie.flow` (PASSED): hidden before the find, the popup, "1 button", empty
  machine, hopper + (a UI click) and dev feeding, next! (the epic hops in), a spin with forced
  landings, hold + auto-bank, buying a nudge / hold / wild reel, a nudge, a bank ("kept!"), spins
  run out -> next pet, keeper swap, the card picker, feeding a card, the picker's pages, the badges
  with buttons, a buttoned part in the bag. `expect fits` on every screen. Shots: hidden, opened,
  empty, mid_try, held, shop, next, keeper, cards, cards_pages, badges, bag.
- `tests/flows/fits.flow` (PASSED): a plushie stop at the end (a pet in, the wild reel showing).
- `tests/test_core.gd`: `_test_plushie` (pure rules, odds, wisps, the shop, wild reel, save
  round trip, knack x3.5, lean totals agree, grafting keeps buttons, always a card) and
  `_test_plushie_game` (v23 save loads empty, nothing before the find, the find + free button once,
  grant wisps, keepers order, herd feeding + stars, card feeding rules, off a job when none rest,
  a try through a save, the keeper can't swap while held, the keeper stays busy, banked reels
  survive a swap, the keeper can't be sent, an away keeper). ALL PASSED (3751 checks). `_test_unlocks` knows `feature:plushie` and lets a find with `given_by` wait for
  its step.
- tools/balance.gd output byte-identical to before.

## Dev steps (DevDriver)

`open-plushie`, `wisps <n>`, `buttons <slot>=<n> ...`, `hopper <rarity> <n>`, `cards on|off`,
`feed-card <n>`, `land <slot>=button|blank|crack ...` (slot `wild` too), `spin [n]` (waits for the
reels), `bank <slot>`, `hold <slot>`, `nudge <slot>`, `buy nudge|hold|wild`, `keeper next|prev`,
`part <slot:id[@n]> [count]`, `page inventory <0-2>`.

## Text to add

**docs/design.md, docs/architecture.md**: already added on this branch (design: "The plushie
machine" paragraph after Knacks; architecture: a Boosts bullet on buttons, a "The plushie machine"
section, save v24 in Saving).

**docs/dev-plan.md**, replace the F1 and F2 headings' status and add under F2:

```
### F1. The sacrifice machine: upgrading parts  (BUILT 2026-09-29, lane plushie)
### F2. A new layer on pets: perfect is hard again  (BUILT 2026-09-29, lane plushie)
- **Built:** the plushie machine (look A, the cabinet), a workbench page hidden until the sewing
  room's last room gives find:plushie_machine (E3 grants it; one free button on the active pet).
  Keeper ‹ ›, hopper from herd shelves (+) and card pets, 5 reels with odds shown, bank / hold /
  nudge, auto-bank, spins run out -> banked, wild 6th reel, wisps (candy floss coral) from misses
  buy nudges, holds and the wild reel. Buttons 0-5 per part multiply its knack (x1.5 each), stay on
  grafted parts (slot:id@n), make a pet always a card. data/plushie.json, Plushie, PlushieMachine,
  save v24 (plushie, wisps, buttons). Flow: plushie. Open: handoff rules (bank at 3...), plushie
  perks on the well wall, balance.
```

**CLAUDE.md "Where we left off"**, add:

```
- F1/F2 the plushie machine (look A, the cabinet): workbench = your pet | toys | plushie machine
  (hidden until find plushie_machine; E3's last room grants it, unlock `plushie` sews one free
  button on the active pet). scripts/machine/plushie.gd (Plushie: pure rules on GameState.plushie),
  scripts/ui/plushie_machine.gd (PlushieMachine), data/plushie.json. Keeper ‹ ›, hopper (herd +,
  card pets; fed pets leave = stars), reels per part with odds, bank / hold / nudge, auto-bank,
  wild 6th reel, WISPS (GameState.wisps, grant_wisps / grant "wisps", UiTheme.WISP coral). Buttons
  (Pet.buttons 0-5 per part): knack x(1 + 0.5 b), always a card, grafting keeps them (bag keys
  slot:id@n). Save v24 (plushie, wisps, buttons). Flow: plushie; dev steps open-plushie, wisps,
  buttons, hopper, cards, feed-card, land, spin, bank, hold, nudge, buy, keeper, part,
  page inventory <n>.
```

## Questions for Emilia (smallest safe pick in place)

1. Sewing a part with buttons can still fail like any part, and the buttons are lost with it. Or
   should buttoned parts never slip?
2. The wild reel is bought per fed pet, and its button sews on straight away (no hold). OK?
3. Hopper: a pet leaves (a star) the moment you tap +. There's no take-back. OK?
4. The free button from the sewing room goes on the active pet's best-knack part. OK?
5. "x perfection" on wisps is 1 + 0.1 per button the keeper has. OK?
6. The trait tilts (lucky, curious, greedy, zoomy) are placeholders, and so are all the numbers.
7. The machine also opens the workbench tab (in case E3 comes before any toy or part). Fine?
8. Swapping keepers is only allowed while nothing is held. The fed pet stays in the machine across
   a swap, and reels you banked stay banked for it. OK?
9. A nudge doesn't puff wisps again (the first miss already did). OK?
10. The keeper can't go on adventures while it's the keeper (it has to be swapped out first). OK?
11. If the keeper is ever gone for good (it can't be sent or fed, so only odd old saves), whatever
    the reels held is sewn onto the next keeper instead of being lost. OK?

## Merged (lanes/merge, 2026-09-29)

Save v24 here became **v34** (after the dungeon's v33). Wisps are one purse: `GameState.wisps`
(saved since v33) and one `grant_wisps(n, quiet)` that the dungeon's floors, the machine's misses and
`grant({ "wisps": n })` all pay through. The keeper also stays out of the dungeon's army, and army
pets can't be the keeper. The plushie flow turns stickers off (book pages filled by `pets 40` popped
over the badges shot).
