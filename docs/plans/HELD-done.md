# HELD done: held landings (dungeon shortcuts)

Built from docs/picks.md (F3 "held landings", Stars rule, round 3 look A) and lanes/mockups2
`well-additions.html` Look A part 3. Plan: docs/plans/HELD.md.

## What was built

- Every 10th landing the army has cleared (10, 20, 30... down to `dungeon.deep`) can be held by a
  crowd of plain pets sent by shelf. Needs 500 / 2k / 8k for 10 / 20 / 30, then x3 each (24k, 72k...).
- Who may go: exactly the new homes stall's picks (`homes_pick`): never favourites, your pet, pets
  with a new part or buttons, holo and better, pets away or in the army, the plushie keeper, pinned
  pulls, party leaders, kept pets. Resting ones first, then pets on errands and machines (taken off
  them like the stall does).
- Holders stay on for good: they leave the collection with NO night-sky star (`Collection.leave(...,
  false)`, no `pets_left`); their stand-in looks go with them.
- On the well (look A): a HoldSpot per landing that can be held. The crowd is posed by band: around the
  rope's end on the sagging rope floor at 10, beside the cellar door at 20 (the door swings open, a dark
  doorway + the leaf, once it's held), sitting on the stairs down to 30+ (a held stairs landing's guard
  is gone: not drawn, and a run walking past it doesn't fight it either; no lamp where a crowd stands). A coral count pill right of the shaft: solid coral 'N' when
  held, dashed lilac 'N/M' while it fills (dashed pink while its card is open), a dashed '0/500' on an
  empty landing (the only sign there). Once the sewing room's door is on 20 its pill sits just under the landing,
  clear of the door, and floor 21's feeling word steps down a few px under it (WellColumn draw). Counts in the pill, the meter and the card's big count are short (500, 1.2k, 8k, 109k). A pill too
  wide for the gap right of the shaft (deep landings: '35.1k/72k', '109k/216k') slides left to stay inside
  the column (WellColumn passes its width as geo.w) and drops just under its landing when it has to reach
  over the shaft's wall.
- Tapping a crowd or pill opens the hold card where "last time" sits (one card at a time with the perk
  cards; ✕ closes; the well scrolls the landing to the middle): "landing N" + ✕ (+ a coral pennant once
  held), the crowd (a Mound of stand-in faces), the big count, "holding the rope | door | stairs"; while
  it fills: a coral meter 'N / M', a row per shelf that has pets that may go (name, "of N" = every pet of that
  shelf that may go, ‹ n › going at most as far as the landing still needs, steps of need / 20), and "hold on tight!".
- Orders card: a new first line "start from ‹the top | landing N›", only once a landing is fully held.
  "go down to floor" can't go above start + 1 (stepping the start moves the target down with it).
- A run from a landing: the army pops out there; the floors above are skipped: no fights, no losses,
  no lanterns, no time. "Last time" says at least that landing. Firsts are only given for floors a run
  walked (floor 10's part, if it's still waiting for parts, needs a run from the top). Your pet leading
  the army and the music box use the same orders, so they start there too.
- Voice (data/voice.json ui): `hold_send` ("hold on tight, everyone!"), `hold_full` ("landing {f} is
  held! straight down next time!"), `dungeon_go_from` ("straight down to landing {f}! hi, everyone!").

## Data shape

data/dungeon.json:
```json
"hold": { "every": 10, "need": [500, 2000, 8000], "grow": 3, "steps_to_fill": 20, "faces": 14, "card_faces": 24, "looks": 8,
          "what": { "rope": "the rope", "doors": "the door", "stairs": "the stairs" } }
```
State (in `dungeon`): `held: { "10": { "common:normal": 480, "uncommon:normal": 20 } }` (count keys,
cards turned into their key), `start: 0 | a fully held landing`. A run: `run.start`.

## Save bump

SAVE_VERSION 28 -> 29 (this lane; renumber at the merge). Migration `version < 29`: `dungeon.held = {}`,
`dungeon.start = 0`. `Dungeon.clean` also fills them and makes them safe (landings not every 10th
dropped, counts via Herd.clean_counts, each crowd cut to its need, start back to 0 unless fully held and
<= deep, target >= start + 1). Tests: "the save chain ends at v29", the perks test's "saves at v29".

## Files

- New: `scripts/ui/hold_spot.gd` (HoldSpot), `tests/flows/held.flow`, this file.
- `data/dungeon.json` (hold + note), `data/voice.json` (3 lines).
- `scripts/dungeon/dungeon.gd`: `hold_every / hold_need / hold_what / held_n / is_held / hold_spots /
  starts / held_landings / kind_at / hold_int`, `strength(catalog, f, held)` (a held guard landing has no
  guard_x), `fresh` / `clean` (held, start), `simulate` (`orders.start`, `orders.held`), `run_seconds` / `run_floor`
  (walked floors, from the landing).
- `scripts/pets/collection.gd`: `leave(counts, uids, star := true)` (same signature as lanes/workshop;
  this lane's body uses `_herd_away` for the no-star counts), `_herd_away`.
- `scripts/game_state.gd`: SAVE_VERSION 29 + migration, `hold_spots`, `hold_room`, `hold_can_go`, `hold_faces`,
  `send_holders` (nobody goes when the room is 0), `set_start(f)` (used by `set_order("start")`; target
  >= start + 1), `floor_words` (held guards), `send_army` (orders.start, run.start),
  `_finish_dungeon_run` (to >= start, firsts for walked floors, start dropped if no longer held).
- `scripts/ui/mound.gd`: faces may be Pets; flipped sprites are mirrored with a transform (a
  negative-width rect drew them a sprite's width to the right, so heaps had stray pets on their right
  side, e.g. the herd card's mound; this fixes every Mound).
- `scripts/ui/well_column.gd`: `hold_pressed(f)`, `_build_holds` / `_place_holds`, `set_hold_picked`,
  `hold_spot(f)`, no guard on a held landing, no lamp under a crowd.
- `scripts/ui/dungeon_view.gd`: `pick_hold`, `_hold_card` (the shelf list keeps its scroll across
  rebuilds; the page's rebuild key uses `hold_can_go`, capped, and nothing for a fully held landing),
  `_hold_step`, `hold_pick` / `hold_list` (flows),
  `_send_holders`, `_Pennant`, `_show_hold`, the orders' start line, `dungeon_go_from`.
- `scripts/dev/dev_driver.gd`: dev steps below.
- `tests/test_core.gd`: `_test_held`, `_test_held_game`, save chain 29.
- `docs/design.md` (the old well: held landings), `docs/architecture.md` (Save v29).

## Dev steps

- `holders <landing> <rarity> <n>`: n pets of that rarity go and hold that landing (like the card's
  button; fails if none could go). (Not `hold`: that's the plushie machine's reel step.)
- `hold-pick <rarity> <n>`: the open hold card's stepper for that shelf shows n.
- `start <landing>`: the orders start there via `GameState.set_start` (0: the top; fails if not fully
  held or the army is out).
- `hold-scroll <px>` / `hold-scrolled <px>`: scroll the open hold card's shelf list / check it's still
  there (after a stepper click and the page's checks).

## Flows

- `tests/flows/held.flow`: empty spots (dashed pills), the empty card (six shelves), a picked stepper,
  the shelf list staying scrolled after a step, "hold on tight!",
  filling (dashed 200/500), rope held (coral 500 + pennant), door filling (1.2k/2k on the landing),
  door held (propped open, next to the sewing room's door), stairs held (no guard), start from landing
  30, the run popping out at 30, "last time" floor 31, deep pills (deep 62, 35.1k/72k on 50 and
  109k/216k on 60 slid in under their landings, the card reading "109k"). `expect fits` at every shot.
- Also played: fits, dungeon, perks, sewing (all pass).

## Tests

`_test_held`: needs 500/2k/8k/24k/72k, a held guard landing has no x2 (strength, kind_at, a run
walking past held landing 30 isn't stuck where it would be with the guard), only every 10th, what per band, spots only down to deep, starts
only through fully held landings, a run from 20 to 25 walks/pays only 21..25 and takes 5 floors of
time (run_floor 20 -> 25), a weak army gets stuck on 21, a start below the target is ignored, clean
(bad keys, over-need cut, start not held / past deep -> 0, target moves below start).
`_test_held_game`: v28 -> v29 (held {}, start 0), hold_can_go caps at the need and never takes holo
cards, send_holders takes pets off errands, no star (fallen_n unchanged), the army keeps its pets, it
stops at the need, a crowd over its need takes nobody, favourites and your pet stay, set_start refuses
a landing that isn't held and a running army, the start stepper and target clamp, a run from
landing 30 has no floors above it and is down there at once, last time, save v29 round trip.

## Text for the shared docs (merge step)

**docs/dev-plan.md** (F3, mark done): "Held landings: built (lanes/sewing HELD). Every 10th cleared
landing is held by a crowd sent by shelf (500 / 2k / 8k, then x3; data/dungeon.json hold); the orders
start from the deepest held one; skipped floors pay no lanterns, take no time; holders stay on for good
with no star. Save v29 (renumber). Flow held."

**CLAUDE.md "where we left off"** (add a bullet):
"- Held landings (F3, lanes/sewing): every 10th landing the army cleared can be held by a crowd of plain
  pets sent by shelf (the stall's rules; 500 / 2k / 8k then x3, data/dungeon.json "hold"). HoldSpot on
  the well (rope / propped door / stairs poses, coral count pill, dashed 'N/M' while filling), the hold
  card in the side column (DungeonView.pick_hold), orders "start from ‹the top | landing N›"
  (Dungeon.starts, simulate orders.start: skipped floors no fights/losses/lanterns/time; a held guard
  landing has no guard, drawn or fought, orders.held). Holders stay
  on for good, no star (Collection.leave(..., false)). GameState.send_holders / hold_can_go /
  hold_room / hold_faces / set_start, save v29 (dungeon.held, dungeon.start). Dev steps `holders <landing> <rarity> <n>`,
  `hold-pick <rarity> <n>`, `hold-scroll <px>` / `hold-scrolled <px>`, `start <landing>`; flow held. Mound now mirrors flipped sprites properly."

docs/design.md and docs/architecture.md are already updated in this lane.

## Questions for Emilia (the smallest safe pick is in for now)

1. Holders come off errands and machines like new homes does (picked), or only resting pets?
2. Stepper steps of need / 20 (25 / 100 / 400) (picked), or the stall's 1 / 10 / 100 / all chips?
3. An empty landing only shows a dashed '0/500' pill (picked), nothing else. Enough?
4. Skipped floors take no time at all (picked: the army pops out at the landing)?
5. A held stairs landing's guard is gone in the fight too now (the plan said "loses its guard"), so
   a run walking past it from higher up fights plain stairs there. OK, or should the guard stay in
   the fight (and be drawn again)?
6. The empty landing's card says "0 holding the rope": fine, or should an empty card say something else?
