# SMALL done: cut the pet's slips, capsule machine odds, fever burst

No save change (SAVE_VERSION stays 23 on this branch).

## What was built

1. **Slips cut (data only).**
   - data/unlocks.json, the beyond announce line is now "a map of past the fence! there's so much out there. let's go see all of it!"
   - data/voice.json trail_part_kept: "this one's a keeper!"
   - data/voice.json scaredy rumour line: "{rumour}?! eek! that sounds big!"
   - `grep -rn -i "i mean" data/` finds nothing now. "i meant for that to happen." (the graft fail brag) stays.
2. **The capsule machine shows its odds.**
   - `Machine.odds(state, catalog, gives, lucky, toy_luck, toy_rate)` returns prize id -> chance, adding up to 1. It uses the same weights as `roll()`, and a kind that `gives` says isn't open yet folds into coins, the same swap `GameState._capsule` makes.
   - `GameState.machine_odds(lucky)` wraps it with `_machine_gives` and the current toy boosts.
   - UI: `MachineTab.OddsCard`, a child of MachineStage.
     - A small "prizes" tag (Button `odds_tag`, tilted 4 degrees) sits in the stage's top right corner. Hovering shows the odds as a tooltip, like a pack in the boxes tab.
     - Tapping flips it (scale.x, like the box_reveal flip) into a card (`odds_card`): name | "a capsule" | "lucky" (gold, only once the lights are rewired), with a gold "shiny" row once shiny balls are fixed.
     - Tapping the card flips it back. It's hidden during the tutorial and stays inside the stage.
     - While open it refills when the odds change (GameState machine_upgraded, toys_changed, unlocked, tutorial_changed). It's placed on the stage's resize and after each fill, not every frame.
     - A pet box only comes in a pull's first capsule (`_capsule`), so `Machine.odds(..., first)` folds it into coins when `first` is false. Once a pull can drop more than one capsule (`Machine.many_capsules`: a second chute, double or triple drop), the columns show any capsule's odds (no pet box) and the pet box moves under an "a pull" header row with its first-capsule chance.
     - `Machine.FALLBACK_PRIZE` ("coins") is the prize a closed kind turns into, used by both `odds()` and `GameState._capsule`, so reordering machine.json can't split them.
   - The rows come from `MachineTab.odds_columns()`, `odds_rows()` and `prize_name()`; `odds_text()` builds the tooltip.
   - Data: each prize in data/machine.json has a "name" (coins, xp, a part, a toy, a golden capsule, a pet in a box). The box prize has no name and uses its box's own name ("sunny box").
3. **Fever stays a burst.**
   - New data/machine.json `"fever_burst": 0.8`.
   - `Machine.fever_cap(state, catalog)` is fever_burst x lights x reveal_seconds (at normal speed). `Machine.fever_for(state, catalog, fever_boost, speed)` is the smaller of fever_seconds x boost and the cap, divided by speed: fever counts in pulls, so a speed toy gives the same fever pulls in less time and every "longer fever" level still adds pulls (review fix: before, dividing only the cap let a x1.4 speed toy cancel all three levels).
   - `GameState.pull_lever` uses `fever_for` with toy_boost("fever") and toy_boost("speed"). tools/machine_pace.gd uses `fever_for`.
   - Retune: base fever is 10 s -> 8 s, and "longer fever" gives +1 s a level instead of +3 s (gain text updated). Fully upgraded that's 11 s, under the cap of 11.2 s. With toys the cap cuts it.

## Files

- data/machine.json, data/machine_tree.json, data/unlocks.json, data/voice.json
- scripts/machine/machine.gd (fever_cap, fever_for, odds)
- scripts/game_state.gd (pull_lever uses fever_for, machine_odds)
- scripts/ui/machine_tab.gd (OddsCard, odds_columns / odds_rows / prize_name / odds_text)
- tools/machine_pace.gd
- tests/test_core.gd:
  - odds add up to 1
  - better drops gating
  - a closed kind counts as coins
  - lucky odds only hold lucky prizes
  - the toy rate shows on the odds
  - fever under the relight time with a 5x fever toy and a 3x speed toy
  - every longer fever level still adds fever pulls with speed toys x1.0 / x1.1 / x1.5 / x3.0, and a speed toy gives the same fever pulls
  - a pet box is only on the first capsule's odds (a later capsule's chance goes to coins), and many_capsules
  - fully upgraded fever isn't cut short
  - every prize has a card name
- tests/flows/machine_odds.flow (new)
- docs/design.md (the fever line and odds), docs/architecture.md (OddsCard)

## Checks run

- test_core: ALL PASSED (3387 checks)
- balance.gd and machine_pace.gd run clean
- Flows machine_odds, fits, machine and tutorial all PASSED. Shots checked: the tag, the early card, the lucky card, after a pull, odds_many (the "a pull" row), the fever shot, and the tutorial with no tag.

## Flows / dev steps

- Flow: `machine_odds` (shots tag, odds_early, odds_lucky, after_pull, odds_many: the card open while a second chute is fixed refills and shows "a pull").
- Dev step `fix <node>` now also emits `GameState.machine_upgraded` (like a real buy), so the machine's sparkle and the odds card react. Click targets: `name:odds_tag`, `name:odds_card`. No new dev steps.

## Text to add

**docs/dev-plan.md** (mark the small picks done):
> Small picks done (lane b1): the pet's possessive slips cut (unlocks beyond line, voice trail_part_kept, the scaredy rumour "i mean… yay!"); the capsule machine shows its odds (a "prizes" tag in the stage corner flips into the odds card, Machine.odds / GameState.machine_odds, flow machine_odds); fever stays a burst (machine.json fever_burst 0.8 of the relight time caps it, base 8 s, +1 s a level of longer fever, 11 s max; counts in pulls, so speed toys shorten its seconds but not its pulls).

**CLAUDE.md "where we left off"** (one bullet):
> - Small picks (lane b1): slips cut ("i mean…" lines gone from data/); the capsule machine shows its odds: MachineTab.OddsCard, a "prizes" tag in the stage's top right (hover = tooltip) that flips into a card (a capsule | lucky once the lights work | shiny once fixed), Machine.odds + GameState.machine_odds, prize "name"s in machine.json, hidden in the tutorial, refills while open, the pet box gets its own "a pull" row once a pull drops more than one capsule, flow machine_odds; fever stays a burst: Machine.fever_cap / fever_for, machine.json "fever_burst" 0.8 of lights x capsule seconds, fever counts in pulls (speed toys divide its seconds), fever 8 s + 1 s a level (11 s max).

(docs/design.md and docs/architecture.md are already edited in this lane.)

## Not done / notes

- The bee (fever toy) adds little once longer fever is maxed: 11 s x 1.2 is capped at 11.2 s. That's what "fever stays a burst" asks for; if the bee should matter late, fever_burst or the longer fever numbers need a retune (question for Emilia).

- The picks line also says to fix docs/design.md's stale "the machine is NEVER automated" (around line 171). That wasn't part of this step, so it's left for whoever owns that doc pass.
