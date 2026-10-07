# SWEEP: full check suite on a fresh base: done notes

Lane `sweep` (branch lanes/sweep, from 13a1126). Ran the core tests, tools/balance.gd and every
flow in tests/flows (60), grepped each flow's whole Godot output for SCRIPT ERROR / ERROR: /
WARNING: / leaked objects at exit, and looked at the shots of the big screens.

## Before (fresh 13a1126)

- `tests/test_core.gd`: ALL PASSED (6117 checks). Its one WARNING ("save is from a newer version")
  is the migration test on purpose.
- `tools/balance.gd`: runs to the end, no errors.
- Flows: all 60 passed (exit 0), none exited 3 (script error).
- Godot output: no SCRIPT ERROR and no leaked objects/resources at exit in any flow. One real error:
  working_pets printed `ERROR: Invalid polygon data, triangulation failed` twice
  (MapView._draw_torn_paper). Every flow prints `WARNING: Could not set V-Sync mode`: that's the
  hidden Xvfb screen (llvmpipe can't change vsync), not the game, so left alone (and settings.gd
  has Emilia's uncommitted work in the main checkout, so I kept out of it).
- A plain headless start in a check profile: no errors or warnings.

## Fixed

- **Torn map paper drawn before it has a size** (scripts/ui/map_view.gd): the edge page's map draws
  its torn paper on the first frames at 0 x 0 and 0 x 285, a polygon that can't be triangulated.
  It now skips drawing until the sheet is big enough to tear. working_pets is clean now.
- **A wrapped job name's lines touched** (scripts/ui/errands_tab.gd): "lemonade stand" wraps on a
  narrow corkboard note and with line spacing -4 the two lines of the display font ran into each
  other. Now -1 (shot jobs_lemonade in errand_tools).
- **Pack strip slivers** (scripts/ui/reveal/card_pack.gd): only showed in the second full run
  (pack_sound, 3x `ERROR: Invalid polygon data, triangulation failed` in CardPack._draw_strip).
  When the fold line lands right along an edge of the tear strip, Geometry2D.clip_polygons /
  intersect_polygons hand back a sliver that can't be triangulated (a probe over 20000 random folds:
  12 of 104847 pieces). Those slivers are skipped now; pack_sound, boxes and pet_box are clean.
- tools/play.py also writes the game's whole output to `godot.log` in the flow's profile folder
  (so warnings and exit leaks can be grepped after a run; it only printed ERROR lines before).

## After

- `tests/test_core.gd`: ALL PASSED (6117 checks). balance.gd unchanged.
- Second full run of all 60 flows (load average ~75 from other lanes): 59 passed, gear failed once
  at step 75 (`expect text "next treat in*"` after `wait 9.5`). The treat timer runs on the wall
  clock and the window it checks is 9 s (zoom ends) to 13 s (next treat); under that load more than
  13 s went by between the toss and the check, so the button already said "toss a treat". Not a game
  bug: gear passed twice in a row on a rerun (and in the first full run). Flow left as it is; it
  can flake when the machine is very busy.
- After the pack fix: pack_sound, boxes, pet_box re-run clean. No SCRIPT ERROR / ERROR / leak lines
  left in any flow output (only the Xvfb vsync warning).

## Shots looked at

home (home_pile, goals), machine, errands, errand_tools, automation, workers, dungeon, plushie,
sewing, toys_late, parts, plus fits, house, next_door, workshop at half size. Nothing spills past
the window. Things that look odd but are by design, left alone:
- a two-line pet bubble grows over the row under the top bar (commit 20bc5aa did that on purpose).
- the errands corkboard and the parts grid scroll, so a note/row can sit cut at the bottom edge.

## Save, data, merge notes

- No save version bump, no data changes. Small edits in map_view.gd, errands_tab.gd, tools/play.py:
  nothing that should conflict with other lanes.

## Questions for Emilia

- The plushie machine's card pets picker pages 20 pets (5 rows of 4) but only about 3.5 rows fit in
  the hopper at the 920x600 size, so a page also scrolls and the 4th row sits cut in half
  (shot cards_pages). Make a page as many rows as fit (12-16 pets), or keep it?
