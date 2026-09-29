# E2 next door: done (lane nextdoor)

Look A (the street) from design/mockups/screens/next-door.html, rules from docs/picks.md (E2 in
"Brainstorm 2 picks" and "Look picks, round 2"). Plan: docs/plans/E2.md.

**Status: VERIFIED 2026-09-29. Built, tests (3794 checks) + balance + flows passing on lanes/nextdoor, committed there (not pushed).**

## What was built

- **A new map page "next door"** (data/unlocks.json pages: `"paper": "night"`, `"layout":
  "street"`). Night paper (the theme's paper mixed toward deep), stars and a crayon moon, a row of
  house backs along the top, one per garden, whose windows are the lights (lit = lamp gold, dark =
  deep with a seam outline), picket fences between the gardens, our own fence along the bottom
  with their gate in it, one dashed path in through the gate with a spur up into each garden found
  so far. Gardens: their gate (in our fence), their garden path, the greenhouse, their pond, the
  porch (a broken capsule machine in the doodle), the doghouse (risky). Lights 3/4/5/5/6/8. A
  garden nobody has found yet is only its lit house (no ? cloud); a spotted one is faded with
  "tap to go!".
- **Places become ours.** One light goes out per visit (a trip welcomed back with somebody
  home, going home early counts). At the last light your pet colours the garden in with its own
  colour (the palette's body colour, lighter if it would vanish on a dark page), a flag in that
  colour goes on the roof and a flower replaces the locals' trace. The colouring-in plays once the
  next time you look at the map. An ours place: danger x0.5, loot x1.2, and events with
  `"local": true` (the locals' traces: slipper, watering can, teacup, the paper, a window lighting
  up, the big bowl, a snore) stop turning up. Their gate and path are ours from the start, so they
  carry no trace and no local events (the slipper is on the porch, the window at the greenhouse and
  porch), and their danger/loot are always met x0.5 / x1.2 (gate loot 7 -> 8.4, path 10 -> 12).
  **The backyard** can become ours too: 40 visits per place (`"ours_after": 40` on the backyard
  page), only once next door is open. Beyond the fence never does (no `ours_after`).
- **Your pet talks about it**: "shh... the house behind {place} is going to bed." when a light goes
  out on a trip you sent (not your pet's auto trips), "look! i coloured {place} in!" when a place
  becomes ours (data/adventures.json `ours`).
- **Place card**: a row of little windows (lights left) under the note while the place isn't ours,
  a pink "risky" tag on the doghouse (until ours), a cyan coin chip "×1.2" once ours. On the street
  the card sticks top left (tilted the other way) when the garden is in the right half
  (path, porch, doghouse), like the mockup. The swarm estimate uses the ours numbers.
- **Trips on the street** walk in through the gate, along the path and up into their garden; back
  ones wait by the gate. The trail for a next-door trip is on night paper with house backs.
- **The hook for C2**: `GameState.open_page(page_id) -> bool`. Next door's unlock has
  `"earn": { "called": true }`: `check_unlocks` never opens it, `UnlockRules.stale` never closes it.
  `open_page` fires the unlock through the same `_open_entry` as `check_unlocks` (popup "new: next
  door!" with show me -> adventures, your pet's announce line, milestone), emits
  `page_opened(page_id)` and saves. Backyard places already past 40 visits get coloured in when
  next door opens. **Nothing else opens next door** (C2 calls `GameState.open_page("next_door")`).
- **The midnight box tier** appears by itself (BoxShop.open_tiers checks `page_open`), with B1's
  arrival line and "new!" tag.

## Files

- data/unlocks.json: page `next_door`, backyard `ours_after`, unlock `next_door` (earn `called`),
  notes for `called` and page fields
- data/adventures.json: `ours` block, 6 places, 20 `nd_*` events (7 `local`), note
- scripts/adventure/ours.gd (new, `Ours`): pure rules (needed, lights, lights_left, is_ours,
  opens_with, place, say, visits_from)
- scripts/adventure/adventure_runner.gd: `start(..., ours)`, `pick_events(..., ours)` skips local
  events, `place(state, catalog)` used in resolve / play (cached on `RunState.met`); run_gap reads the catalog, `estimate_return(..., ours)`
- scripts/adventure/run_state.gd: `ours` (saved), `met` (an ours run's scaled place, not saved)
- scripts/core/catalog.gd: `ours`, `page_info(id)`
- scripts/core/unlock_rules.gd: `called(entry)`, `opening(list, what)`, stale skips called ones
- scripts/game_state.gd: `open_page`, `_open_entry` (check_unlocks refactor), `page_opened`,
  `visits`, `unshown_ours` / `ours_shown`, `next_door_open`, `visits_at`, `lights_left`, `is_ours`, `add_visits`;
  send passes ours, collect_run counts the visit, trail pickups use the ours place; save v24
- scripts/pets/pet_look.gd: `main_color(pet, dark)`
- scripts/ui/street_page.gd (new, `StreetPage`): the street's layout, drawing, hit rects, routes,
  night colours, `scribble`, `window`, flags
- scripts/ui/map_view.gd: night paper, street layout hand-off, ours places on other pages (scribble
  oval, pet colour, small flag), street walkers, title shrinks before it runs into the bookmarks
- scripts/ui/crayon.gd: doodles gate, greenhouse, porch, doghouse, slipper, can, cup, paper, bowl,
  flower; `Crayon.bend` (quadratic curve points)
- scripts/ui/adventures_tab.gd: lights row, risky tag, ×1.2 chip, card side, welcome back buttons
  named `welcome_<place>`
- scripts/ui/trail_view.gd: night paper and house backs for next-door trips
- scripts/dev/dev_driver.gd: steps `open`, `visit`, expects `ours`, `not-ours`, `lights`
- tests/test_core.gd (`_test_next_door`; the "not drawn on top of each other" check is per page
  now), tools/balance.gd (next door table, ours vs not), tests/flows/next_door.flow (new)
- docs/design.md (Adventures: next door), docs/architecture.md (Screens, Saving)

## Data shape

```json
"ours": { "opens_with": "next_door", "danger": 0.5, "loot": 1.2,
  "say_dark": "shh... the house behind {place} is going to bed.", "say_ours": "look! i coloured {place} in!" }

{ "id": "greenhouse", "type": "foraging", "page": "next_door", "name": "the greenhouse", "lights": 5,
  "max_party": 30, "minutes": 12, "go_home": true, "difficulty": 1.5, "danger": 1.0, "loot": 11, "box": "midnight",
  "finish_rewards": [...], "draws": 4, "pool": [...],
  "map": { "x": 1, "y": 0, "doodle": "greenhouse", "note": "so warm!", "trace": "can" } }
```

`map.x` is the garden's column on the street (pond 0, greenhouse 1, path 2, porch 3, doghouse 4),
`map.y` 1 = in our fence (the gate, column 2). `ours_at_start` on the gate and path (both also
`start`), `risky` on the doghouse. Spotting: gate -> greenhouse 0.5; path -> pond 0.4, porch 0.3;
porch -> doghouse 0.3. Events: `"local": true` marks the locals' traces; every place keeps at least
`draws` non-local events. The porch's broken machine is only an event (`nd_machine`); the midnight
globe is A5's.

Unlock: `{ "id": "next_door", "opens": ["page:next_door"], "show": "hidden", "popup": {...},
"earn": { "called": true }, "announce": "there are gardens next door! let's tiptoe over and have a look." }`.
Page: `{ "id": "next_door", "name": "next door", "paper": "night", "layout": "street" }`, backyard
gets `"ours_after": 40`.

## Save bump

**v23 -> v24** (the merge step renumbers). New field `visits` { place id: n }; the migration
(`version < 24 and not data.has("visits")`) gives every place in `visited` one visit
(`Ours.visits_from`). Runs save `ours` (missing = false). Nothing about being ours is saved:
it's worked out from visits every time, so renumbering only needs the comment/condition moved.

## Flows, tests, dev steps

- `python3 tools/play.py next_door` (from rich): no midnight box and no bookmark at first ->
  `open next_door` (popup) -> the street (gate + path ours, 3 bookmarks, title fits) -> greenhouse
  card with 5 windows -> `visit greenhouse 4` (1 light) -> `visit greenhouse 1` (ours: coloured in,
  flag, ×1.2 on the card) -> doghouse card "risky" (card on the left) -> a trip to the greenhouse
  (night trail, walker on the street) -> a real trip to their pond all the way home: 4 lights left
  and "shh... the house behind their pond is going to bed." -> boxes: midnight box with "new!" ->
  backyard: meadow ours at 40 visits. `expect fits` after every screen. Shots in
  play-next_door-nextdoor/shots.
- Re-run and passing: fits, party, bits_map, tutorial, postcard, box_tiers, gear, unlock_popup,
  automation.
- `godot --headless -s tests/test_core.gd`: `_test_next_door` (page, 6 places with lights and a
  column each, lights 3/4/5/5/6/8, gate/path ours at start, enough non-local events, local events
  only next door, only `called` opens next door and it never goes stale, lights go out per visit,
  ours at the last light, nothing ours while closed, backyard at 40 only with next door open,
  beyond never, ours place x0.5 / x1.2 without touching the catalog, ours trips never meet locals,
  ours round-trips through a save, more come home once ours, v24 visits migration).
- `godot --headless -s tools/balance.gd`: a "next door, 20 commons by the rules" table (coins per
  trip / per minute, share home, boxes; before and after ours).
- Dev: `open <page>` (GameState.open_page, popup and all), `visit <place> [n]`,
  `expect ours <place>`, `expect not-ours <place>`, `expect lights <place> <n>`, click
  `name:welcome_<place>`.

## Text to add elsewhere

**docs/dev-plan.md**, E2 heading: `### E2. The next map page (zone 3)  (BUILT 2026-09-29, lane nextdoor)` and add:

> - **Built:** next door, look A (the street): data/unlocks.json page `next_door` (night paper,
>   street layout), 6 places in data/adventures.json (their gate, their garden path, the
>   greenhouse, their pond, the porch, the doghouse; lights 3/4/5/5/6/8; gate + path ours at the
>   start), places become ours (`Ours`: one light out per visit, then your pet colours it in with
>   its own colour + a flag; danger x0.5, loot x1.2, `local` events stop; backyard after 40 visits
>   once next door is open), `StreetPage` draws it, place card lights row / risky / ×1.2. Opening
>   is C2's: `GameState.open_page("next_door")` (unlock `earn: called`). Save v24 `visits`.
>   Flow next_door.

**CLAUDE.md "Where we left off"**, new bullet:

> - E2 next door (lane nextdoor): map page `next_door` (data/unlocks.json: `paper: night`,
>   `layout: street`), drawn by scripts/ui/street_page.gd (house backs whose windows are the
>   lights, gardens, our fence with their gate, path in). 6 places (their_gate, their_path,
>   greenhouse, their_pond, porch, doghouse; `lights`, `ours_at_start`, `risky`, `map.x` =
>   column, `map.trace`), 20 `nd_*` events (`local: true` = the locals' traces). Places become
>   ours (scripts/adventure/ours.gd `Ours`; GameState.visits / is_ours / lights_left / add_visits;
>   adventures.json `ours`: danger 0.5, loot 1.2, say lines; backyard `ours_after` 40, only with
>   next door open): coloured in with your pet's colour (PetLook.main_color) + flag, locals stop.
>   Nothing opens next door but code: `GameState.open_page(page_id)` (unlock `earn: { called:
>   true }`, popup + `page_opened`), for C2 to call. Save v24 `visits` (+ RunState `ours`).
>   Flow next_door; dev steps `open <page>`, `visit <place> [n]`, `expect ours / not-ours /
>   lights`.

## Questions for Emilia (the smallest safe pick was made)

1. The mockup shows ours places as "a short walk". The picks only say safer and pays more, so trip
   time stays the same. Should ours trips be quicker too?
2. Backyard places become ours after 40 visits each, and only once next door is open (a place
   already past 40 is coloured in when next door opens). Beyond the fence never becomes ours. OK?
3. A garden nobody has found yet shows only its lit house (no ? cloud, no name). OK?
4. A visit = a trip welcomed back with at least one pet home (going home early counts; a trip where
   nobody came back doesn't put a light out).
5. Your pet whispers "shh... the house behind the greenhouse is going to bed." when a light goes
   out on a trip you sent yourself (not on its own auto trips, to keep it quiet). The wording is a
   placeholder.
6. Next door's places bring midnight boxes and midnight looks (parts) as their "box". The box drops
   are rare (0.02-0.05). Numbers (loot 8-20, party caps 20-100, minutes 8-30) are placeholders:
   the balance table shows ~1-6k coins per 20-pet trip.
7. The flag and the colouring-in are in your pet's own colour, and the gate/path flags too (the
   mockup drew them pink). The colour follows whichever pet is active now.

## Review fixes (E2 second pass)

- **Unreachable locals**: their gate and path stay ours from the start (Emilia's pick in
  docs/picks.md: "the gate and path start as ours"), so option (b): `nd_window` left the gate and
  path pools (it's at the greenhouse and the porch now), `nd_slipper` moved to the porch ("a fluffy
  slipper at the bottom of the porch steps"), their_path lost its `trace`, gate/path pools got
  sprinkler / moths instead. Gate loot 8 -> 7, path 9 -> 10 so their real (ours) numbers sit under
  the greenhouse per minute (balance: gate 136, path 118, greenhouse 143 coins/min before ours).
  Tests: an ours-from-the-start place has no trace and no local events; every local event is in a
  pool of a place that starts un-ours. balance.gd skips the "ours: no" rows for those places.
- **Draw without side effects**: `GameState.just_ours` (msec timing) is now `unshown_ours` (id ->
  true, not saved) + `ours_shown(id)`. MapView owns `_colouring` (id -> start msec), starts it in
  `_process` for places on the page it shows, forgets it after, and passes `grow` into
  `StreetPage.draw(..., grow)`; `StreetPage.colouring` is gone.
- **run_gap** reads `catalog.location` again; `AdventureRunner.place` works an ours run's place
  out once into `RunState.met` (not saved).
- **MapView._process** checks `unshown_ours` / `_colouring` emptiness first; no lambda per frame.
- **Back trips on the map**: they wait in a short line (at most 4 little pets, `BACK_SHOWN`) by home
  or their gate; one back keeps its "<who> is back!" tag, more get one "N parties are back!" tag to
  the left of the line (clamped to the map). Same on the backyard. Checked with 7 back next door
  and 8 back in the backyard (temporary flows).
- Flow next_door: the colouring-in shot now comes right after the last visit (it was taken after
  the animation had finished).
