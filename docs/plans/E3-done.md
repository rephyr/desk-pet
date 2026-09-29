# E3 the sewing room: done notes (lane `lanes/sewing`)

Built from docs/picks.md (Brainstorm 3 "E3", Look picks round 3 "well additions") and the mockup
lanes/mockups2 `design/mockups/screens/well-additions.html` (the sewing room part; the column is
look A). Plan: docs/plans/E3.md.

## What was built

- **The door:** once the tiny key from floor 20 is found (`finds.little_key`, unlock `sewing`, quiet:
  "there's a tiny pink door on floor 20. the key fits it!"), `WellColumn` shows a `SewDoor` through
  the right wall of floor 20: a dashed tunnel, a pink arched door, a coral knob. Nothing before the
  key. When the door first turns up the column scrolls to it.
- **The pan:** tapping it slides the column sideways (0.45 s tween) to `SewingRoom`; the header
  turns into `‹ the sewing room` (‹ slides back). The tunnel strip, `‹ name ›`, dots (cleared + the
  next only, at most 9 around the one shown), the arched dashed chamber with the room's line drawing
  (SVG, 9 pictures, 3 straight from the mockup), the chalkboard of `ChalkMark`s, and the foot: a
  feeling word (or a coral pennant once cleared) + `in we go!` / `on the way…`.
- **Rooms:** 9 fixed rooms (button tin, pin cushion, thread maze, ribbon drawer, thimble tower,
  pattern book, needle case, the big scissors, the sewing basket), each ONE fight for the dungeon's
  army (cards, herd, entrance, who goes first) against `strength.base x grow^floor x room_x` at
  floors 21, 22, 24, 25, 26, 28, 29, 31, 33. Replays pay wisps, no firsts. Losses as a well floor
  (stars, never mentioned). Below the dungeon's `stuck` ratio: not cleared, no pay.
- **Chalk locks:** 3-5 marks (`part:<slot>:<id>`, `trait:<id>`, `finish:<id>`, `tier:<id>`,
  `buttons:<n>`). A mark fills in solid when a pet in the front row (`GameState.sew_front()` = the
  army's best 20 cards; your pet with the flag doesn't count) matches; matching front-row cards get a
  chalk tick (`FrontRow` ticks, only while the rooms pane shows). Tapping a dashed mark: your pet
  says `GameState.sew_hint(mark)` ("bunny ears come on rare pets! the lucky box has the most.").
  `in we go!` only when every mark is filled.
- **Firsts:** room 1 -> keep lines (unlock `keep_lines`, popup "new: keep lines!", waits for the
  sorting card), rooms 4 and 7 -> one more line each (your pet announces it), room 9 ->
  `find:plushie_machine` (the existing plushie unlock: the machine opens and sews one free button
  onto your active pet).
- **Rolled rooms** after room 9, forever: name + picture in turn from `rolled.rooms`, floor 34 + 1
  per room, a button lock first (1 + 1 per 3 rooms, max 25), then marks from `rolled.pool` (3 marks,
  +1 per 5 rooms, max 5), picked by the room's number (the same every time).
- **Keep lines** on the sorting card: `keep ‹zoomy ones› 12/50`. Picks: nothing, every trait, the
  knack parts in `sewing.json marks` the book has seen. A new plain pet from a box matching a line
  stays a card (not sorted away, not folded, the stall never takes it); each line keeps its newest
  50; changing a line lets its old pets go. Works with the rule on or off. With keep lines the card
  goes compact so 3 lines fit ("new pets below ‹rare›" on one line; new parts / favourites as icon
  chips with tooltips).

## Files

- New: `data/sewing.json`, `scripts/dungeon/sewing.gd` (`Sewing`, pure rules),
  `scripts/ui/sewing_room.gd` (`SewingRoom`), `scripts/ui/chalk_mark.gd` (`ChalkMark`),
  `scripts/ui/sew_door.gd` (`SewDoor`), `tests/flows/sewing.flow`.
- Changed: `scripts/dungeon/dungeon.gd` (`_fight` shared by floors and rooms, `simulate_room`,
  `run_seconds` / `run_floor` read room runs, `clean` keeps `last.room`), `scripts/game_state.gd`
  (sewing section, keep lines, `_run_losses`, save v27), `scripts/pets/collection.gd`
  (`keep_uids` in `always_card`), `scripts/pets/new_homes.gd` (`rule.lines`, `kept`),
  `scripts/ui/dungeon_view.gd` (the pan, header, ticks, last time card "went to ‹room›", a follow
  fix: the column now scrolls once it has its size), `scripts/ui/well_column.gd` (the door),
  `scripts/ui/front_row.gd` (ticks), `scripts/ui/sorting_card.gd` (keep lines),
  `scripts/ui/automation_tab.gd` (the army card says "in ‹room›" during a room run),
  `scripts/core/catalog.gd` (`catalog.sewing`), `scripts/dev/dev_driver.gd`, `data/unlocks.json`
  (unlocks `sewing`, `keep_lines`, earn key `sewing`, plushie_machine `given_by`), `data/voice.json`
  (`sewing_*` lines), `tests/test_core.gd`, `tests/flows/fits.flow`, `tools/balance.gd`,
  `docs/design.md`, `docs/architecture.md`.

## Data shape

- `data/sewing.json`: `door_floor`, `seconds` (60), `room_x`, `pay_x`, `keep.cap` (50), `rooms`
  [{ id, name, pic, floor, marks, first: { keep_lines | find } }], `rolled` { floor_start,
  floor_step, rooms [{ id, name, pic }], marks { start, every, max }, buttons { start, every, max },
  pool }, `marks` { mark: { many, keep } }, `hints` { part, finish, trait, tier, buttons, keep }.
- Unlock earn key `"sewing": n` = rooms cleared.

## Save bump: v26 -> v27 (renumber at the merge)

- New top-level `sewing: { cleared }`.
- `new_homes.rule.lines: [picks]`, `new_homes.kept: { pick: [uids oldest first] }`.
- A room run is the dungeon's `run` with `room`, `door`, `seconds`; `dungeon.last.room`.
- Migration: nothing moves. `load_game`: a v26- save with `dungeon.deep >= 20` and no key gets
  `finds.little_key` (and `check_unlocks` opens the door).
- The test "the save chain ends at v27" (`_test_merged_lanes`) needs the merged number.

## Flows, dev steps, tests

- Flow `sewing`: no door before the key -> door -> locked tin -> a mark's hint -> cards fill it
  (ticks) -> in -> on the way -> keep lines popup -> keep line on the card -> "went to the button
  tin" -> the sewing basket -> plushie popup -> a rolled room with a button lock -> 3 keep lines on
  the card. `expect fits` on every screen. `fits.flow` got a sewing room stop at the end.
- Dev steps: `door`, `sew-room <n>` (not `room`: that step already sets the room upgrade level),
  `sewn <n>`, `in`, `card k=v... [n]`, `keep <line> <pick|none>`. A mark's hint is
  `click ChalkMark#n` (no own step needed).
- Tests: `_test_sewing` (pure), `_test_sewing_game` (the game, v26 load, a run, keep lines with the
  rule on and off, the stall, the cap, the plushie machine, rolled rooms, save round trip, the v26
  key line). `tools/balance.gd` prints a rooms table (which armies clear which room, wisps/h).
- Review fixes (after the first pass): the idle sewing line no longer eats the well's news (wisps,
  deepest floor, home early) when the army comes home while the rooms pane shows; the room's
  button says "on the way…" only for its own run (a well run shows the plain disabled "in we go!");
  the automation card says "in ‹room›" instead of "down to floor N" during a room run; the column
  scrolls to the door (`WellColumn.door_y`) when it first turns up, and on the first show of a
  session while no room is cleared yet (a v26 save migrated at floor 40 gets its key on load and
  the door is shown, not floor 40); leading the army waits while the sewing room shows
  (`GameState.army_held`). Flow sewing got a well run with the rooms pane open.
- Checks: test_core ALL PASSED (4041 checks); balance runs; flows sewing, fits, dungeon, new_homes,
  plushie PASSED.

## Text to add elsewhere

### docs/dev-plan.md (E3)

> **E3 the sewing room: built** (lane sewing). Door on floor 20 after the key, the column slides to
> the rooms, 9 fixed rooms with chalk locks (front row marks, ticks, hints), keep lines from the tin
> (+1 at rooms 4 and 7), the last room opens the plushie machine (F1 hook), rolled rooms with button
> locks forever. data/sewing.json, Sewing, SewingRoom, ChalkMark, SewDoor; save v27; flow sewing.
> Open: Emilia's answers to the E3 questions (tier/finish exact, flagged pet, keep line count,
> replays, room names), tuning room floors against the pace sim.

### CLAUDE.md "where we left off"

> - E3 the sewing room (lane sewing): a pink door on the well's floor 20 once the tiny key is found
>   (SewDoor on WellColumn); tap it and the dungeon column slides to SewingRoom (‹ the sewing room).
>   9 fixed rooms (data/sewing.json, scripts/dungeon/sewing.gd `Sewing`), each one fight for the
>   army (Dungeon._fight / simulate_room at the room's floor) behind a chalk lock (ChalkMark: part
>   pictures, traits, finishes, tiers, buttons; filled when a front-row pet matches, ticks on the
>   FrontRow, a tap = GameState.sew_hint). Room 1 teaches keep lines on the sorting card (unlock
>   keep_lines; +1 at rooms 4 and 7; `new_homes.rule.lines` / `kept`, Collection.keep_uids, cap 50),
>   the last room grants find:plushie_machine, then rolled rooms with button locks forever. Save v27
>   field "sewing" (+ keep lines, room runs in dungeon.run). Flow: sewing; dev steps door, sew-room,
>   sewn, in, card, keep. While the sewing room shows, your pet leading the army waits at home
>   (GameState.army_held, not saved) so a room gets a turn.

### docs/design.md / docs/architecture.md

Already edited in this lane: design.md "## The sewing room (E3, off the well's floor 20)" after the
old well section; architecture.md scripts/dungeon line, the dungeon page UI line, and a "Save v27"
paragraph before "## Testing".

## Questions for Emilia (the smallest safe option is used meanwhile)

1. Tier and finish marks match exactly (as the mockup shows), not "that or better".
2. Your pet with the flag doesn't count for marks (it leads, never fights).
3. Keep lines come 1 + 1 + 1 (rooms 1, 4, 7) and work with the sorting rule off too; only plain
   pets from box openings are kept (holo and up are cards anyway).
4. Keep lines wait for the sorting card if it isn't found yet when the tin is cleared.
5. Rooms can be replayed for wisps; a room run doesn't walk down the well first (60 s at the door).
6. Room names past the five in the picks (thimble tower, pattern book, needle case, sewing basket)
   and all rolled rooms' names are placeholders. Floors 21-33 are placeholders too: a rare+uncommon
   army clears rooms 1-4, epic+rare up to 7, legendary+epic the last room (balance table).
7. While your pet leads the army (automation), it takes the army down the well again as soon as
   it's home. Smallest fix for now: while the sewing room is open on screen (DungeonView sets
   `GameState.army_held`, not saved), your pet waits at home, so you get a turn for a room once the
   army's back. Is that how it should work, or should "in we go!" queue the room as the army's next
   run (or leading the army do rooms itself)?

## Verified

- Step verified: test_core ALL PASSED (4041 checks), balance runs clean, flows sewing, fits,
  dungeon, new_homes and plushie pass (`expect fits` on every sewing screen).
- Commits on lanes/sewing: "the sewing room off the well's floor 20, keep lines" (the step), plus
  this note. Not pushed. Save bump v26 -> v27 needs renumbering at the merge (and the "save chain
  ends at v27" test with it).
