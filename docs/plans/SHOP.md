# SHOP plan: the shed workshop (F3), look A (the card on the map)

Sources: picks.md (Brainstorm 3 F3, Look picks round 3), mockup lanes/mockups2 shed-workshop.html
look A and its drawings table. Branch lanes/workshop, save 26 -> 27.

## What it does
- Opens (`feature:workshop`) once **the old shed is ours** (coloured in) **and the whistle is
  found**. Before that, tapping the shed opens its normal place card, as now.
- Tap the shed on the backyard map: a **workshop card** sticks on the map (top left, the away
  column stays on the right). 3 drawings pinned on a plank, each with a small progress bar. The
  picked one shows its needs: **helpers N/M** and **"<tier> or up" n/count** (two meters),
  shelf chips (a face + count per rarity you can send), **1 / 10 / 100 / all**, **not yet** (closes)
  and **build it!** (only lit when the picked drawing is full).
- **All 3 pinned drawings fill at once**; nothing builds by itself, you tap build it!. Building
  puts the thing on the map and pins the next drawing from the list **in that same spot**. When
  the list runs out the spot stays empty; with nothing left pinned, the shed opens its place card
  again.
- Helpers are **plain pets only** (the same pets the new homes stall may take: no favourites,
  active pet, pets away, pinned pulls, holo or better). They **stay on for good**: they leave the
  collection but add **no star**. Pets below the drawing's tier only go in while there's room left
  for the ones that meet it (mockup `useful()`), so a drawing can always be finished.
- Built things stand around the backyard map (crayon drawings at their spots), each takes one
  chore away.

## The 8 drawings (numbers from the mockup, in data; tune later)
| id | name | need | tier / count | chore it takes away |
|---|---|---|---|---|
| bell | the bell rope | 40 | rare 5 | trips you sent are welcomed back by themselves when home (not the one you're watching on the trail); finds go in the bag, the postcard waits for you |
| shelf | the toy shelf | 60 | epic 10 | a play ends: your pet takes the same toy back down for the same length |
| vane | the weather vane | 120 | epic 20 | a trip waiting at a **plain** choice (no option risky at that place) takes your last pick for that event at that place; risky choices always wait for you |
| chart | the chore chart | 250 | epic 40 | every open errand counts as "new pets join here" (errands only; the whistle keeps doing machines/tables) |
| spade | the garden spade | 500 | legendary 5 | twinkling rummage spots in the room get dug through by themselves |
| basket | the sewing basket | 1000 | legendary 10 | toys not being played with mend a little (wear down per hour) |
| banner | the treat banner | 2000 | legendary 25 | on the trail, a treat is tossed whenever one is ready |
| letter | the letterbox | 5000 | legendary 60 | postcards don't pop up: they wait in the letterbox (count on it) until you tap it |

Kept manual on purpose (never a drawing): the school bell, reel banking, the newest globe's lever,
ripping boxes yourself, risky trip choices.

## Data: data/workshop.json (new)
```
{ "_note": "...",
  "pinned": 3,
  "unlock": { "ours": "shed" },
  "basket_mend_per_hour": 0.1,        // wear 0..1
  "letterbox_keep": 30,               // postcards kept (not saved)
  "cheer": ["hi helpers!", "more hammers!", ...], "fancier": "hmm, we need some fancier helpers.",
  "ready": "that's everyone! let's build it!", "open_say": "welcome to the workshop!",
  "close_say": "i'll be in the shed if you need me!",
  "drawings": [ { "id": "bell", "name": "the bell rope", "need": 40, "tier": "rare", "count": 5,
      "at": [-0.46, -0.11], "size": 0.5, "chore": "...", "say": "...", "done": "...",
      "art": "<svg path d strings, 48x48 sheet, from the mockup>" }, ... 8, in list order ] }
```
Catalog loads it (`catalog.workshop`). unlocks.json: unlock `workshop` opens `feature:workshop`,
earn `{ "ours": "shed", "open": "feature:whistle" }` (new earn key `ours`, documented in the
_note), popup "new: the workshop!" (go adventures), announce line.

## Save (v27)
New field `"workshop"`: `{ pinned: [id, id, id], prog: { id: { sent, qual } }, built: [ids],
helpers: total ever, vane: { "place:event": option index } }`. Migration: older saves get
`Workshop.fresh()` (first 3 drawings pinned, nothing built). `vane` is filled by every answer you
give from v27 on, so the vane works as soon as it's built. Toys' `playing` entries gain `play`
(the play length id) so the shelf can replay; old entries without it just don't replay.
Postcards waiting (bell / letterbox) are NOT saved (loot is already granted; a restart drops them).

## Code
- `scripts/idle/workshop.gd` (new, pure rules): `fresh`, `clean`, `drawing(id)`, `pinned`,
  `full(state, d)`, `useful(state, d, rarity)`, `take(state, d, rarity, n)` (sent/qual),
  `build(state, id)` (built += id, next unpinned drawing into that slot), `has(state, id)`.
- `scripts/pets/collection.gd`: `leave(counts, uids, star := true)`; helpers pass false.
- `scripts/game_state.gd`: `workshop` var + save/load/migration; `workshop_open()`,
  `workshop_can_go(rarity)` (min of homes_pick n and useful), `send_helpers(id, rarity, n)`
  (homes_pick -> off places -> leave without stars), `build_drawing(id)`, `built(id)`;
  `_earned` gets `ours`; chores: bell (tick: collect done non-auto runs except `watching`, push
  the postcard dict to `postcards`), vane (in `_advance_runs`: waiting runs, plain events,
  remembered pick; `answer_event` records picks), shelf (after `Toys.finish_plays`), basket (tick
  + offline gap on load), spade (tick: `rummage()` on ready spots), chart (`job_joins` true for
  open errands when built). `watching` (the run on the trail, set by AdventuresTab; not saved).
- `scripts/machine/toys.gd`: `play()` stores `play`; load keeps it.
- `scripts/ui/workshop_card.gd` (new, WorkshopCard): the look A card (~298 px wide sticker,
  tilted -1deg): title "the old shed" + gold "ours!", a wood plank with 3 `Paper`s (drawing art
  via UiTheme svg texture, short name, mini bar; the picked one lifted, a fresh one glows), the two
  need rows, shelf chips (only rarities you have), 1/10/100/all, not yet / build it!. Your pet
  talks in the shared bubble (say on pick, cheer on send, done on build).
- `scripts/ui/adventures_tab.gd`: shed tapped + workshop open -> WorkshopCard instead of the place
  card; sets `GameState.watching` with the trail; shows waiting postcards one by one when the tab
  is visible (bell, no letterbox); letterbox tapped -> next postcard; welcome back with the
  letterbox built -> postcard goes in the letterbox.
- `scripts/ui/map_view.gd`: draws built things at their `at` on the backyard page (a sparkle
  when just built); the letterbox with a count pill and a hit area (`letter_picked` signal).
- `scripts/ui/trail_view.gd`: banner tosses the treat when ready.
- `scripts/ui/errands_tab.gd`: hide the errands' "new pets join here" switches once the chart
  is built (they'd do nothing).
- `scripts/dev/dev_driver.gd`: steps `helpers <drawing> <n> [qual]` (progress for free) and
  `build <drawing>` (built for free, next pinned); doc lines.

## Flow: tests/flows/workshop.flow (+ screenshots, expect fits)
from rich; herd rare/epic/legendary + commons; tab adventures; `place shed` -> expect no-text
"build it!"; `open next_door`; `visit shed 40`; `unlock feature:whistle`; wait popup, shot
workshop_popup; tab adventures; `place shed` -> expect text "the old shed", "not yet"; expect fits;
shot workshop_card; pick the bell rope, rare chip, "all" -> "build it!"; shot workshop_full;
build it! -> expect text "chore chart" pinned; shot workshop_built; not yet; shot map_bell;
`build` the rest; shot map_all; `herd common normal 2000000` -> chips "2M", expect fits, shot
workshop_crowd; `send shed 3` + wait event/back -> trips welcome themselves, letterbox count;
click the letterbox -> postcard; shot letterbox.

## Tests (tests/test_core.gd)
Data checks (8 drawings, unique ids, real tiers, count <= need, needs grow, art present, spots
not on top of places); useful/take math (below-tier pets leave room; all never overfills); build
pins the next in the same slot, all-built leaves none; clean() on junk; v26 save -> fresh
workshop; helpers leave with no stars (fallen_n unchanged); unlock needs ours shed AND whistle;
vane answers plain events only, never risky ones, only with a remembered allowed pick; shelf
replays; basket mends only resting toys; chart makes open errands join; bell collects done runs
but not the watched one, and not auto runs; letterbox keeps postcards (up to keep).
balance.gd: print total helpers for all 8 (a pace line), no gate.

## Questions for Emilia (smallest safe pick in brackets)
1. Trips to the shed once the workshop is open: [the card header gets a small "adventure ›" pill
   that swaps to the normal place card, and the place card a "workshop ›" pill back].
2. The chore chart overlaps "new pets join here" (which already puts new pets on the errand with
   the smallest crew). [Built chart = every errand joins, the switches go away.] Or swap it for
   another chore, e.g. saying yes to places pets spotted?
3. Treat banner: treats are the watching-a-party bit. [Built as the mockup: full treat whenever
   ready.] Or a smaller treat?
4. Letterbox: [postcards wait always]; or only for trips that came home while the game was closed?
   Waiting postcards aren't saved [a restart drops them; the loot is already yours].
5. The vane's "last pick" is per event per place [yes]; picks the vane made don't count as yours.
6. Needs are the mockup's (40 .. 5000); at whistle time players may have far more pets. Tune with
   the pace sim later.
