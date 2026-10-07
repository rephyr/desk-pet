# A5 the midnight globe: done (lane midnight)

Emilia's pick (docs/picks.md A5): next door's porch machine comes home as the midnight globe,
broken beside the others, with a short repair branch needing bits from the next-door page, ending in
its own rusted hatch. Look A, side by side. Built on lanes/midnight from 13a1126.

**Status: built, tests + balance + flows passing on lanes/midnight (not pushed).**

## What was built

- **The find:** `porch_machine` (data/unlocks.json finds) from a new porch event `nd_porch_machine`
  ("the porch machine": auto, `after_machine: hatch`, so it waits for the sunset hatch; in the porch
  pool, sure on the 3rd try like every find). The porch's old teaser `nd_machine` ("a broken
  capsule machine") stops once the sunset hatch is fixed, with a new event key `until_machine`
  (AdventureRunner.can_meet), so the teaser and the find never meet on the same trip.
- **Repairs** (data/machine_tree.json, `"globe": "midnight", "branch": "midnight"`, a chain off the
  sunset `hatch`, drawn from y -440 to -760 inside the midnight `view`):
  1. brush out the cobwebs: 1B (works: you pull it from now on)
  2. a chain for the crank: 2.5B + 2 chain links (x2, a second chute)
  3. new bulbs: 15B + 2 bulbs + 1 chain link (x2, lucky lights)
  4. moon glass: 50B + 2 moon glass (x3, glass: shiny balls)
  5. the rusted hatch: 120B + 3 hinges, 3 chain links, 3 bulbs, 3 moon glass (x5; midnight boxes,
     midnight pet boxes, the midnight toy set)
- **Bits** (machine_tree.json `bits`, globe midnight): chain link (`link`), bulb, moon glass
  (`moonglass`), hinge. They drop only once the porch machine is home (finish rewards with
  `after: porch_machine`): their gate links 0.4, the greenhouse bulbs 0.6, their pond moon glass
  0.5, the porch hinges 0.5, the doghouse links 0.6 + hinges 0.3.
- **Step 72** (was a 144 placeholder): the cobwebs keep your pull at least as good (x1.05, the same
  rule as the sunset nest; 144 made it x2.10). Prices follow the sunset branch's "pulls each" shape
  (tools/balance.gd globes table now runs every later globe).
- **Midnight toys** (data/toys.json set "midnight friends", globe midnight, palette letters n N d):
  little bat (common, speed), fluffy slipper (common, loot), teacup (uncommon, toys), crescent moon
  (rare, all). 14 x 14 pixel art.
- **Machine tab:** up to three stages. The stage shows the globe your pet/workers crank, the one you
  pull and the newest one (two or three, oldest left; ratios 0.62 / 0.82 / 1.0). While the midnight
  globe is broken all three stand side by side (sunny with its workers, sunset in your hand, the
  broken midnight one); once the cobwebs are out the sunny globe steps off the stage (nobody cranks
  it any more) and the workers move to the sunset one. Signs and stat lines of a narrow stage stay
  inside the panel (`MachineStage._inside`). Broken pieces drawn from data `fixes`: `cobwebs` (webs
  in the glass, a spider bobbing on its thread, rust spots), `chain` (the lever flops like the
  sunset sag, a snapped chain dangles off the mount; fixed: a chain from a floor hook up the lever),
  `bulbs` (popped bulbs), `fog` (fog drifting in the glass; fixed: a cool glow and twinkling stars),
  `hatch` (the existing crooked rusty hatch). Fix sparkles per node, a voice line per fix.
- **Icons:** bit_link, bit_bulb, bit_moonglass, bit_hinge, tree_cobweb, tree_chain, tree_bulb,
  tree_moon (scripts/ui/ui_theme.gd).
- **Small fix outside the lane's scope:** StreetPage._centred skipped text at font size 0 (the
  street's first frame before it has a size printed `p_size <= 0` engine errors when a place card
  opens right after `map-page next_door`).

## Files

- data/machine_tree.json (midnight bits + 5 nodes, step 72, arrives line, note), data/adventures.json
  (nd_porch_machine, nd_machine `until_machine`, midnight bit drops, note), data/unlocks.json (find),
  data/toys.json (set + art + palette), data/voice.json (machine_fix_porch_*)
- scripts/adventure/adventure_runner.gd (`until_machine`), scripts/machine/machine.gd (branch),
  scripts/ui/machine_tree_view.gd (branch name, repairs), scripts/ui/machine_tab.gd (three stages,
  midnight drawing, `_inside`), scripts/ui/ui_theme.gd (icons), scripts/ui/street_page.gd (size 0)
- tests/test_core.gd (`_test_globes`: the injected midnight catalog is replaced by real-data checks;
  `_test_globes_game`: bulbs wait for the porch machine, its find brings it home), tools/balance.gd
  (globes table for every globe), tests/flows/midnight.flow (new)
- docs/design.md (Globes: the midnight globe), docs/architecture.md (machine tab stages),
  docs/dev-plan.md (A5 heading + "Midnight built", the P3 and E2 "not yet" lines, suggested order)

## Save bump

**None.** The globe list (`machine.globes`) and toys are already saved generically; an old save with
`porch_machine` in `finds` gets the globe on load (A5's rule).

## Merge notes

- `until_machine` is a new event key (one line in `can_meet`).
- The machine tab's `stages` is now three long; `stage` returns the hand stage, else the last
  visible one. `_layout` picks behind / hand / newest. Two-globe saves look exactly as before.
- Flows re-run and passing here: midnight, globes, next_door, box_tiers, machine, fits, workers,
  pet_box, toys, machine_odds, tutorial, bits_map, automation, goals.
- tests: `ALL PASSED (6203 checks)`. The known flaky "v21 and v2x saves load the same" failed once
  in the first run and passed on the re-run (nothing in this lane touches saves).

## Text to add elsewhere

**CLAUDE.md "Where we left off"**, new bullet:

> - A5 midnight globe (lane midnight, 2026-10-07): next door's porch machine (find `porch_machine`,
>   event `nd_porch_machine` on the porch after the sunset hatch; `nd_machine` stops then via the new
>   event key `until_machine`). Repairs porch_dust (works) / porch_chain / porch_bulbs / porch_glass /
>   porch_hatch off the sunset hatch, bits link / bulb / moonglass / hinge from next door (after
>   porch_machine), step 72, midnight toys (bat, slipper, teacup, moon). Machine tab shows up to
>   three globes (behind, hand, newest). No save bump. Flow midnight.

## Questions for Emilia (the smallest safe pick was made)

1. **Bits and where they drop** (placeholders): chain links (their gate 0.4, the doghouse 0.6),
   bulbs (the greenhouse 0.6), moon glass (their pond 0.5), hinges (the porch 0.5, the doghouse
   0.3). Names and places OK? Their garden path brings none.
2. **Repair names and looks:** brush out the cobwebs (a spider lives in it), a chain for the crank
   (the lever flops until then, like the sunset sag), new bulbs, moon glass (foggy until then), the
   rusted hatch (needs hinges). OK, or other broken bits for the porch machine?
3. **Prices:** 1B / 2.5B / 15B / 50B / 120B, the same "a few pulls each" shape as the sunset
   branch, so bits are the real gate again (same open question as the sunset A5 #6).
4. **Step 72** keeps the first midnight pull just above the finished sunset globe (x1.05), like the
   sunset rule. Want a bigger jump when the cobwebs come out?
5. **The sunny globe steps off the stage** once the midnight globe works (nobody uses it: workers
   and errands pay at the globe one behind your hand). Keep it standing there idle instead (three
   globes forever), or is stepping off right?
6. **When it turns up:** only after the sunset hatch (`after_machine: hatch`) and on the porch,
   which you reach from their garden path (spot 0.3). OK? Next door could open before the sunset
   hatch is done; then the porch keeps showing the old broken machine until it is.
7. **Midnight toys:** little bat (common, speed), fluffy slipper (common, loot), teacup (uncommon,
   toys), crescent moon (rare, all). OK?
8. **Open item:** the porch's street doodle still draws its broken capsule machine after it's
   gone home. Swap it for an empty porch?
