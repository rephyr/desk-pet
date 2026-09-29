# PAWS (care E): quiet paws

From docs/picks.md "Brainstorm 3 picks", care E. Build plan, short.

Out on your windows (DesktopPet, `pet_out`) your pet keeps doing its one job in place, with poses
only, no text. The setting picks how much of it you see. The setting changes drawing only. It never
changes what gets opened or cranked.

## What it shows

| setting | shows |
| --- | --- |
| off | the pet walks around like it does now |
| big things | a good pull held up for 4 s, and an adventure waiting (foot tap) |
| everything | the big things, plus the boxes routine and the crank machine |

- **Boxes job** (`packs_on` and `GameState.background_packing() >= 0`, so the background opening
  is running): when the pet stops on an edge with room, it does a **work stint** (20-40 s) in
  place. A tiny pile of 3 packs sits beside it on the same edge. The pose follows
  `background_packing()` p: p < 0.3 it faces the pile, then it holds the pack, and from 0.55 on
  it shakes it (wiggle, a squash every 0.5 s). On `opened_in_background(pet)` there's a puff. An
  ordinary pet hops off (1.1 s, smaller PetView, the way PetAtWork's does). After the stint it
  walks again. Nothing here calls `pack_job_seen()` or `auto_open_pack()`, so the background
  opening stays the only opener.
- **Crank job** (`automation.task == "machine"`): same stint, with a tiny capsule machine beside
  it (a globe on a body, and a handle whose angle follows `automation.fill`). On each
  `pet_cranked`, the machine bounces and the pet does a small squash.
- **Good pull** (`opened_in_background` + `is_good_pull`, big things and up): the pet stops, even
  mid-walk, and holds the pet over its head for 4 s with the gold sparkles from PetAtWork. If it's
  falling or being dragged, the hold waits until it lands (dropped after 10 s). `pinned` is left
  alone, so the home screen still tells you about it. A tap is still a pat.
- **Adventure waiting** (big things and up): there's a run that isn't `auto` with status
  WAITING (a question) or DONE (a postcard). When the pet stands, it faces the corner panel (the
  home window) and taps a foot: a small squash on a beat plus 2 dust pixels at its front foot.
  This comes before work stints. Order: hold > wait > stint > walk.
- Adventures job: no pose (not in the pick).

## Data: data/care.json gets a "paws" block

```json
"paws": { "hold": 4, "hop": 1.1, "stint": [20, 40], "reach_until": 0.3, "shake_from": 0.55,
          "hold_waits": 10, "tap_every": 0.4, "room": 2.4 }
```
`room` = how wide an edge must be, in pet widths, before the pile or machine fits beside the pet.

## Setting (no save change)

- `Settings.paws := 2` (0 off, 1 big things, 2 everything), stored in settings.json as `"paws"`,
  clamped 0..2. It's not in the game save, so **no SAVE_VERSION bump**.
- Settings tab, general page, "your pet at work" section: a row
  `_choice("out on your windows", ["off", "big things", "everything"], ...)` (the segmented
  switch, no dropdown). It's hidden until there's something to act out: the adventures tab is open
  or your pet knows a job. The boxes switch stays where it is and this row never touches
  `packs_on` or `automation.task`.

```
 your pet at work
 [x] open boxes in the corner
 out on your windows   [ off | big things | everything ]
```
If the row doesn't fit the half-width section, the label goes on its own line above the switch
(the flow's `expect fits` decides).

## Code

- `scripts/pets/quiet_paws.gd` (new, `class_name QuietPaws extends Node`): the brain. It connects
  `opened_in_background` and `pet_cranked`, and `step(delta, standing, level)` sets `pose`
  (NONE, BOXES, MACHINE, HOLD, WAIT), `held`, `phase` (reach/hold/shake), `puff`, `bounce`,
  `hop`, `stint_left` and `wants_still`. It reads GameState and care.json. No drawing.
- `scripts/pets/paws_view.gd` (new, `class_name PawsView extends Node2D`): draws the props at the
  desktop pet's `pixel` scale: pile, pack in paws, puff, hopping pet, held pet and sparkles,
  tiny machine, foot dust. `PetAtWork._draw_pack` becomes static `PetAtWork.draw_pack(on, at,
  tilt, scale, empty)` so both share the pack art.
- `scripts/desktop_pet.gd`: owns a QuietPaws, a PawsView and a held PetView. `_idle` holds still
  while `wants_still` (the walk timer doesn't run). `_walk` stops for a HOLD. The prop side is
  the side of the edge with more room. Stints only start on edges `room` pet widths wide (the
  floor always is). WAIT faces `source.home_rect(...)`. Drag or fall = `standing` false.
  - A small seam for testing: an optional `stage: Control`. When it's set, the size, the mouse and
    the click shape come from the Control instead of the overlay Window, so tests and flows can
    run the real DesktopPet inside the game window.
- `scripts/platform/window_source.gd`: `home_rect(home, overlay) -> Rect2` in overlay pixels
  (the base uses the Window positions, Hyprland uses `_find_own(home)` + `_to_local`).
  `DesktopPet` gets `home` from home.gd.
- `scripts/settings.gd` (`paws`), `scripts/ui/settings_tab.gd` (the row).
- `scripts/ui/desk_stage.gd` (new, dev only): a Control over the full game with a sky backdrop,
  one fake window, a fake corner panel, and a real DesktopPet in stage mode with a
  `StageSource` (a WindowSource that returns those two rects). Nothing goes onto the real
  desktop, and profile runs still keep `pet_out` off.

## Dev steps (DevDriver)

- `paws <off|big|everything>`: sets the setting.
- `desk on|off`: shows or hides the DeskStage.
- `desk good`: a rolled rare pet (not added to the collection) goes to the stage pet as if it had
  been opened in the background.
- `give-box <id> <n>`: n boxes of that kind in the pile.
- `finish-trips`: `debug_finish_runs()`.
- `expect setting <key> <value>`.

## Flow: tests/flows/paws.flow

from after_tutorial, view full, tab settings, expect fits, shot settings, click "big things",
expect setting paws 1, shot big, click "everything", expect setting paws 2, then:
teach boxes, task boxes, give-box starter 30, desk on, wait 2, shot desk_boxes, wait 6,
shot desk_shake, desk good, wait 1, shot desk_hold, teach machine, task machine, crank 1,
shot desk_crank, send garden 1, finish-trips, wait 1, shot desk_wait, paws off, wait 2,
shot desk_off, desk off, expect fits. Run it again with `fits` and `automation`.

## Tests (tests/test_core.gd, `_test_paws`)

- Settings: `paws` defaults to 2, is clamped 0..2, and survives a write and read (test profile).
- QuietPaws with level 0: pose NONE with a good pull and a waiting run. Level 1: a good pull
  holds 4 s and then clears, an ordinary pull doesn't hold, a waiting run gives WAIT, and the
  boxes job gives no stint. Level 2: the boxes job + background opening gives BOXES with the phase
  following `background_packing()`, `task machine` gives MACHINE, and a crank sets the bounce.
  Hold beats wait, and wait beats a stint.
- **Not a second switch:** with the boxes job and a pile, 80 s of `_open_in_background` opens the
  same number of packs at levels 0, 1 and 2 while QuietPaws steps. `background_packing()` stays
  >= 0 (QuietPaws never marks itself seen). Changing the level leaves `packs_on`,
  `automation.task` and `pinned` unchanged.
- DesktopPet in stage mode with a StageSource: it doesn't move during a stint (x is unchanged
  over 10 s), a HOLD while walking stops it, WAIT faces the home rect, a drag cancels poses and a
  hold during a fall plays after landing. With off, it walks like it does now.
- Settings tab: the row has 3 options, and it's hidden before adventures or any job.
- `tools/balance.gd` still runs.

## Docs

docs/design.md (Care / the desktop pet), docs/architecture.md (QuietPaws, PawsView, the
DesktopPet stage seam, `home_rect`), and PAWS-done.md with the dev plan and CLAUDE.md text.

## Questions for Emilia (smallest safe pick taken)

- Default setting: **everything**. Or should it be big things?
- Good pulls held up only come from your pet's own background opening, not from box workers'
  bulk opening (they can open hundreds at once). OK?
- An adventure waiting beats the boxes routine, so while a postcard sits there the pet only taps
  its foot. OK, or should it take turns?
- The desktop hold doesn't count as "seen it": the good pull stays pinned for the home screen.
