# HELD: held landings (dungeon shortcuts), build plan

From picks.md F3 + round 3 look A (well-additions.html, part 3). Every 10th landing the army has
cleared can be held by a crowd of pets sent by shelf. Once a landing is fully held, the orders card
can start the army from it; floors above it are skipped (no fights, no losses, no wisps). Holders
stay on for good: they leave the collection with NO star.

## Data (data/dungeon.json, new "hold")

```json
"hold": { "every": 10, "need": [500, 2000, 8000], "grow": 3, "steps_to_fill": 20,
          "what": { "rope": "the rope", "doors": "the door", "stairs": "the stairs" } }
```
- need for landing 10/20/30 from the list, then last x grow each 10 (40 = 24k, 50 = 72k ...).
- "what" is picked by the landing's band kind (10 rope, 20 door, 30+ stairs).
- stepper step = ceil(need / steps_to_fill) (25 / 100 / 400 / 1200).

## Rules (scripts/dungeon/dungeon.gd, pure)

- `hold_need(catalog, f)`, `hold_what(catalog, f)`, `held_n(state, f)`, `is_held(catalog, state, f)`.
- `hold_spots(catalog, state)`: landings every 10 up to `deep` (hidden until the army cleared them).
- `starts(catalog, state)`: [0] + fully held landings.
- `simulate`: new `orders.start` (default 0); the loop begins at floor start+1, so skipped floors
  never appear in `floors` (no pay, no losses). The run keeps `start`.
- `run_seconds` / `run_floor`: count only walked floors; the army is drawn from `start` down
  (it pops out at the landing, skipped floors take no time).
- `fresh` / `clean`: new `held: { "10": { count key: n } }` (keys must be multiples of every,
  counts via Herd.clean_counts, total clamped to need) and `start` (0, or a fully held landing
  <= deep, else 0).

## State (scripts/game_state.gd)

- `hold_can_go(f, rarity)`: plain pets `homes_pick` may take (same rules as new homes and the
  workshop lane: never favourites, active, army, keeper, holo+...), at most what the landing still needs.
- `send_holders(f, rarity, n)`: takes them (off errands/machines if needed, like send_home), cards
  turned into their count key, `collection.leave(counts, uids, false)` (no star), adds to
  `dungeon.held[f]`, emits dungeon_changed, saves. Returns how many went.
- `set_order("start", ±1)`: steps through `starts()`; target clamps to >= start+1.
- `send_army`: passes `start` in the orders, stores `run.start`. The music box and your pet leading
  the army use the same orders, so they start from the landing too.
- Collection.leave gets `star := true` (same signature as lanes/workshop, easy merge).
- Mound: `faces` may also hold Pet objects (holders' faces are stand-in looks of gone counts).

## Save

SAVE_VERSION 28 -> 29. Migration `version < 29`: dungeon gets `held: {}` and `start: 0` (clean
fills them too). Merge step renumbers; noted in HELD-done.md.

## UI (look A, on the walls)

- WellColumn: a new `HoldSpot` (scripts/ui/hold_spot.gd, clickable, signal `hold_pressed(f)`) on
  each shown landing: a small crowd of stand-in faces (size grows like Herd.mound_size) posed by
  band: around the rope at 10, beside the propped-open door at 20, sitting on the stairs at 30+.
  A coral count pill right of the shaft (at 20 under the landing, clear of the sewing door):
  solid 'N' when full, dashed lilac 'N/M' while filling, just '0/500' dashed on an empty landing.
  A fully held stairs landing loses its guard.
- DungeonView side column: tapping a spot opens the hold card where "last time" / the nail card
  sits (one card at a time, ✕ closes): "landing 20" + ✕ (+ coral pennant when full), mound + big
  count + "holding the door"; while filling: meter 'N / M', a row per shelf that has pets that may
  go (name, "of N", ‹ n › stepper), and "hold on tight!".
- Orders card: new first line "start from ‹the top | landing 20›", only once a landing is fully held.
  "go down to floor" can't go below start+1.
- Pet lines (data/voice.json ui): hold_send "hold on tight, everyone!", hold_full "landing {f} is
  held! straight down next time!", dungeon_go_from "straight down to landing {f}! hi, everyone!".

## Dev steps + flow

- Dev steps: `hold <landing> <rarity> <n>` (send_holders, like the card), `start <landing>`
  (the orders' start, fails if not held).
- tests/flows/held.flow: from rich, big herd, dungeon, deep 32; click HoldSpot#1 (empty 0/500),
  step common up, "hold on tight!" (shot partial, dashed pill); fill 10, partial 20, full 30 (shots
  of the three poses + pills); orders card shows "start from", step to landing 30 (shot); down,
  army starts at 30 (shot), down-done, "last time" shows the floor; `expect fits` at every shot.

## Tests (tests/test_core.gd)

- needs 500/2000/8000/24000; what per band; spots only up to deep.
- simulate from start 20 to 25: floors are 21..25 only, pay = sum of those, losses only there;
  run_seconds 5 floors; run_floor starts at 20.
- clean: bad keys dropped, over-need clamped, start not held or past deep -> 0.
- send_holders: pets leave, fallen_n unchanged (no star), clamps at need, never takes favourites /
  active / army pets; start stepper only through held landings; target >= start+1; send_army stores
  run.start. v28 save loads as v29 with held {} start 0; save chain check becomes 29.

## Questions for Emilia (smallest safe pick for now)

1. Holders may come off errands/machines like new homes does (picked: yes, same rules) or resting only?
2. Stepper step = need/20 (25/100/400) ok, or 1/10/100/all chips like the stall?
3. An empty landing shows only a dashed '0/500' pill as its sign (no pet line) ok?
4. Skipped floors take no time (the army pops out at the landing) ok?
