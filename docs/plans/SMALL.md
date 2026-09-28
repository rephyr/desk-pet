# SMALL: cut the pet's slips, capsule machine odds, fever burst

Three small picks from docs/picks.md. No save change (SAVE_VERSION stays 23).

## 1. Cut the pet's possessive slips (data only)

- data/unlocks.json beyond announce: "...there's so much out there. it should all be ours! i mean,
  we should visit!" -> "a map of past the fence! there's so much out there. let's go see all of it!"
- data/voice.json trail_part_kept: "mine now. i mean ours!" -> "this one's a keeper!"
- Other "i mean" in data/: voice.json rumour "{rumour}?! eek! i mean… yay!" is a correction too ->
  "{rumour}?! eek! that sounds big!". "i meant for that to happen." (graft fail) is a vain brag, not
  a slip: kept.
- Check: `grep -rn -i "i mean" data/` comes back empty.

## 2. The capsule machine shows its odds

Rules (scripts/machine/machine.gd):
- `Machine.odds(state, catalog, gives: Callable, lucky := false, toy_luck := 1.0, toy_rate := 1.0)
  -> Dictionary` prize id -> chance (sums to 1). Same weights as `roll()` (drops gating, lucky only,
  toy boosts); prizes whose kind isn't open yet (`gives` says no) fold into coins, the way
  `_capsule` swaps them. Pet box stays at its own chance (it's the first capsule's).
- `GameState.machine_odds(lucky: bool) -> Dictionary`: wraps it with `_machine_gives` and the live
  toy boosts, so what's shown is what's rolled right now.

Data (data/machine.json): each prize gets a "name" for the card: coins "coins", xp "xp", part
"a part", box "a box" (uses the box's own name from boxes.json when there is one), toy "a toy",
golden "golden capsule", pet_box "a pet box".

UI (scripts/ui/machine_tab.gd, MachineStage):
- A small paper card taped to the machine, right of the globe (free space, about design (430, 40)),
  node name `odds_tag`. Hover: a tooltip with the same text as the card (like the pack's hover in
  the boxes tab). Tap: it flips open (the box_reveal card flip) into a paper card over the right side
  of the stage; tap again or anywhere on the stage closes it. The lever still works while it's shut.
- The card, like the back of a pack (boxes_tab `_odds_text` style, two-column name | percent grid
  like the workbench sacrifice odds, `UiTheme.percent`):

  ```
  +------------------------------+
  | a capsule        lucky       |   <- "lucky" column only once the lights are rewired
  | coins     84%    xp     44%  |
  | xp         8%    toy    25%  |
  | toy      4.4%    golden  6%  |
  | golden     1%    ...         |
  | a pet box 0.2%               |
  | shiny  12%                   |   <- only once shiny balls are fixed
  +------------------------------+
  ```
- Hidden during the tutorial (capsules are only coins then, so the card would lie). No hint text.
  Must stay inside the stage (clip) and the window: `expect fits`.

## 3. Fever stays a burst

- data/machine.json: new "fever_burst": 0.8 = fever lasts at most that share of the time it takes to
  relight every light (lights x capsule seconds, the fastest a pull can go; with snail toys that's
  quicker, so the cap shrinks with it).
- `Machine.fever_cap(state, catalog, capsule_s) -> float` and
  `Machine.fever_for(state, catalog, fever_boost, capsule_s) = min(fever_seconds x boost, cap)`.
- GameState.pull_lever: `fever_until = now + Machine.fever_for(machine, catalog, toy_boost("fever"),
  capsule_seconds())`. The bee's "pays more" part still works; only its time is capped.
- Retune so upgrades still matter under the cap (10 lights x 1.4 s x 0.8 = 11.2 s): base
  "fever_seconds" 10 -> 8, "longer fever" node fever_s 3 -> 1 ("+1 s of fever a level"), fully
  upgraded 11 s. tools/machine_pace.gd uses fever_for too.
- docs/design.md: "FEVER (10 s ..." -> 8 s, stays a burst, cap text.

## Flow: tests/flows/machine_odds.flow

```
from after_tutorial
view full
tab machine
click name:odds_tag
wait 0.5
expect text "coins"
expect no-text "lucky"
expect fits
shot odds_early
click name:odds_tag
bits spring 3 / glass 3 / bolt 3 / gear 3
fix tape, oil, flap, glass, wires, shiny 5, fever 3
click name:odds_tag
wait 0.5
expect text "lucky"
expect text "shiny"
expect fits
shot odds_lucky
```
Also rerun the machine and tutorial flows (card hidden in the tutorial, lever unchanged).

## Tests (tests/test_core.gd)

- Machine.odds sums to 1; drops-gated prizes missing before "better drops"; a closed kind folds
  into coins; lucky odds hold only lucky prizes.
- Fever burst: every node fully bought, fever toy boost 5x and speed toy boost 3x: fever_for <
  lights x capsule seconds. Plain fully upgraded fever_for == 11 s.
- tools/balance.gd and tools/machine_pace.gd still run clean.

## Questions for Emilia (smallest safe picks taken)

- Fever retune: base 8 s + 1 s a level (max 11 s, under the 11.2 s cap). Rather keep 10 s and make
  the lights take 12 pulls instead?
- The odds card is a little paper card taped to the machine (tap to open, hover for the tooltip).
  OK, or would you like it somewhere else?
