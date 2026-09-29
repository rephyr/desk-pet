# PAWS (care E): quiet paws, done

Plan: docs/plans/PAWS.md. Built on lane `care`, committed there. Status: VERIFIED (2026-09-29).

Out on your windows (DesktopPet, `pet_out`) your pet keeps doing its one job in place with poses
only, no text. The setting changes drawing only: it never opens, cranks or marks anything seen.

## What was built

| setting | shows |
| --- | --- |
| off | the pet walks around like before |
| big things | a good pull held over its head 4 s, a foot tap facing the corner panel while an adventure waits |
| everything (default) | the big things, plus the boxes routine and the tiny crank machine |

- **Boxes job** (`packs_on` and `background_packing() >= 0`): when the pet stops on an edge where
  the side with more room fits the biggest prop as drawn (`PawsView.widest()`, the tiny machine's
  handle), it stands for a 20-40 s stint beside a pile of 3 packs (on the side
  of the edge with more room). Pose follows the background opening: faces the pile (p < 0.3),
  holds a pack, shakes it (p >= 0.55, a squash every 0.5 s). On `opened_in_background` a puff; an
  ordinary pet hops out of its paws over the pile and away (1.1 s, fading).
- **Crank job** (`automation.task == "machine"`): same stint beside a tiny capsule machine; the
  handle follows `automation.fill` (smoothed), and on `pet_cranked` the machine hops and a capsule
  rolls out of the chute.
- **Good pull** (`opened_in_background` + `is_good_pull`, big things and up): it stops (even
  mid-walk) and holds the pet over its head with gold sparkles for 4 s; a fall or a drag makes it
  wait for the landing (dropped after 10 s); up to 3 queue. `pinned` is left alone.
- **Adventure waiting** (big things and up): a run that isn't `auto` and isn't WALKING. It faces
  the corner panel (`WindowSource.home_rect`) and taps a foot on every 0.4 s beat (small squash,
  2 lilac dust pixels at its front foot). It's a stint too (20-40 s, then a walk), no room needed.
- Priority: hold > foot tap > job stint > walking. A job change mid-stint switches the props
  (boxes -> machine) without ending the stint; the stint ends when nothing is left to act out.
- A drag or fall drops all poses. A tap during any pose is still a pat. A hold cut short by a
  drag starts over (4 s) on landing, unless the pull has waited past `hold_waits` by then.
- Drawing: the pet, its props and the held pet all sit on whole screen pixels (one `_snap` per
  frame, the sparkles follow the held pet). The prop views only redraw while there's a pose or a
  puff (plus one frame to clear), and Settings is looked up once in `_ready`.

## Files

- new `scripts/pets/quiet_paws.gd` (`QuietPaws`, RefCounted: the brain; `step(delta, grounded,
  stopped, room, level)`, `opened()`, `show_off()`, `cranked()`, `has_something()`)
- new `scripts/pets/paws_view.gd` (`PawsView`: draws the props; `PawsView.draw_pack()` is the
  shared pack art, the corner panel's `PetAtWork` uses it now)
- new `scripts/platform/stage_source.gd` (`StageSource`: pretend windows for stage mode)
- new `scripts/dev/desk_stage.gd` (`DeskStage`, dev only: a pretend desktop over the full game)
- `scripts/desktop_pet.gd` (QuietPaws + two PawsViews + a held PetView; holds still for poses;
  stage mode: `stage` Control instead of the overlay; `home`; no autoload names so tests load it)
- `scripts/platform/window_source.gd`, `hyprland_window_source.gd` (`home_rect()`)
- `scripts/home.gd` (`_pet.home = get_window()`)
- `scripts/settings.gd` (`paws`, `PAWS_LEVELS`, `PAWS_DEFAULT`, `paws_from()`)
- `scripts/ui/settings_tab.gd` (the "out on your windows" row, stacked label over the switch;
  `_choice(..., stacked)`)
- `scripts/ui/pet_at_work.gd` (pack art moved to PawsView)
- `scripts/dev/dev_driver.gd` (new steps), `data/care.json` (`paws` block + note),
  `tests/test_core.gd` (`_test_paws`), `tests/flows/paws.flow`
- docs/design.md (Care) and docs/architecture.md (Platform) have their sections already.

## Data shape

`data/care.json`:
```json
"paws": { "hold": 4, "hold_waits": 10, "hop": 1.1, "stint": [20, 40], "reach_until": 0.3,
          "shake_from": 0.55, "tap_every": 0.4 }
```
`settings.json` gets `"paws": 0..2` (default 2).

## Save

No game save change, **no SAVE_VERSION bump** (the setting lives in settings.json).

## Flows and dev steps

- Flow `paws` (from pile_full): the setting on the settings page (`expect setting`, `expect fits`),
  then on the pretend desktop: reach, holding, shake, hop, hold, crank, foot tap, off; ends with
  `expect fits`. Also played: fits, automation, care (all pass).
- Dev steps: `paws <off|big|everything>`, `desk on|off|good`, `give-box <id> <n>`,
  `finish-trips`, `expect setting <key> <value>`, `wait packing <p>`.

## Text for docs/dev-plan.md

Under Phase G "Care / the desktop pet", add:
```
- **Quiet paws** (care E, built 2026-09-29, lane care): out on your windows your pet acts out its
  job with poses only (boxes routine on a window edge, tiny crank machine, a good pull held up 4 s,
  foot tap facing the corner panel while an adventure waits). Setting "out on your windows"
  off / big things / everything (settings.json, no save bump). Flow: paws.
```

## Text for CLAUDE.md "where we left off"

```
- Quiet paws (care E): out on your windows your pet keeps doing its one job with poses only, no
  text (scripts/pets/quiet_paws.gd brain, paws_view.gd props, data/care.json "paws"): boxes
  routine beside a tiny pile on the edge it stands on (follows GameState.background_packing), a
  tiny crank machine that hops on each crank, a good pull held over its head 4 s, a foot tap facing
  the corner panel (WindowSource.home_rect) while an adventure waits. Setting Settings.paws
  (settings.json, general page "out on your windows": off / big things / everything, default
  everything); it only draws, never a second box-opening switch. DesktopPet has a stage mode
  (a Control + StageSource) so tests and the dev DeskStage (`desk on|off|good`) never touch the
  real desktop. Dev steps paws, desk, give-box, finish-trips, `expect setting`, `wait packing`.
  Flow: paws.
```
Also add `paws` to the CLAUDE.md flows list.

## Questions for Emilia

- Default "everything", or "big things"?
- Only good pulls from your pet's own background opening are held up, not box workers' bulk
  opening (they can open hundreds at once). OK?
- An adventure waiting beats the boxes routine, so while a postcard sits there the pet only taps
  its foot (in stints, with walks between). OK, or should they take turns?
- The desktop hold doesn't count as "seen it": the good pull stays pinned for the home screen. OK?
- The row shows once the tutorial is done or your pet knows a job (adventures are open for
  everyone after the tutorial, so that's the real gate). OK?
