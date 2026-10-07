# MOCKUPS3 done: prep mockups (no game code)

Branch `lanes/mockups3`. Prep only: three mockup pages with 3 looks each, linked from
design/mockups/index.html ("prep round 4"), screenshots in design/mockups/shots/mockups3/, and a
"Prep ready" note under each step in docs/dev-plan.md.

## What I built

- **design/mockups/screens/plushie-handoff.html** (F2 handoff): a pet spins the plushie machine
  for you by its rules. Every frame plays itself (a spin every 2.4 s) so you can change a rule and
  watch it. Looks:
  - **A, the rules card:** the cabinet as built, lilac blob on a stool at the lever; the side card
    has the keeper, a `you | lilac blob` switch and the rules as sentences with steppers (like the
    sorting rule): "bank at ‹3›", "never risk the ‹body›" (part chips), "nudge ‹never | off a crack
    | always›", then a tally (spins, sewn on, popped, pets fed).
  - **B, tags on the reels:** the rules hang on the machine: a paper tag under each reel ("bank at"
    stepper + a "careful" heart), a tag on the lever for nudges. A rule per part.
  - **C, a job on the automation tab:** "spin the plushie machine" is one more job card for your
    pet (one job at a time); its rules are its notebook page in crayon ("i bank at 3 buttons", "i
    never risk the body", "i nudge off a crack", "i sew on gold dragon").
- **design/mockups/screens/midnight-globe.html** (A5, the midnight globe): three globes on the
  machine tab. The fixes list is the picked look A from globes.html. Looks: **A** three in a row,
  small to big; **B** the old globes up on a shelf at the back with a ladder for their workers, the
  midnight globe on the floor; **C** one globe on the stage at a time, the globe signs switch.
  Plus the 5 midnight fixes and name ideas for the 4 midnight bits (6 candidates).
- **design/mockups/screens/news-pile.html** (A4's "several popups at once", the bag popup on the
  postcard, coming back after hours): **A** one card at a time, the waiting ones peek out behind
  as card edges; **B** nothing pops up, news lands as envelopes in a pile by your pet (gold dot on
  home), tap to open one on the side; **C** one "while you were away" letter, a row per thing with
  "show me ›" (while you play, look A).

Rules kept: real game words (workbench, keeper, hopper, bank / hold / nudge, buttons, wisps,
"page full!", "show me" / "lovely", the unlock popup's own text), no hint copy in the game frames,
no '·' separators, everything inside the 920x600 window (checked on screenshots), dark plum theme.

Save version bump: **none** (no game code). Checks: core tests in profile core-test-mockups3 (see
the lane result).

## Merge notes

- New files only, plus small inserts in design/mockups/index.html (a new section before "theme
  lab") and docs/dev-plan.md (three "Prep ready" bullets: A4, A5, F2). No conflicts expected.
- Screenshot PNGs in design/mockups/shots/mockups3/ (Godot may add .import files next to them,
  like the other shots).

## Questions for Emilia

### F2: your pet's rules for the plushie machine (plushie-handoff.html)
1. **Which look:** A the rules card, B tags on the reels, C a job on the automation tab.
2. **What "never risk the body" means.** Mockup: that part is banked the moment it holds a button,
   never held (a crack can still pop a sewn button). Or: the pet leaves that reel still (no risk,
   but no new buttons there either).
3. **How it plays worse than you.** Mockup: slower (a spin every few seconds), never holds past its
   "bank at", nudges only the way its rule says, never spends wisps (no buying nudges, holds or the
   wild reel). Other ideas: sometimes forgets a nudge; can't use the wild 6th reel at all.
4. **Who spins and how it opens.** Your active pet as one more automation job (C), or a pet on a
   stool at the machine (A, B). Opens with a well wall perk, a shed workshop drawing, or a rolled
   sewing room. (Workshop rules said "reel banking stays yours", so this is the deliberate step
   that hands it over.)
5. **While the game is closed:** keeps spinning (like the crank with the stool) or only while open
   (like lead the army)?
6. **The hopper:** the pet only spins what you put in, or the sorting rule's keep lines top it up.

### A5: the midnight globe (midnight-globe.html)
1. **Which look** for three globes: A in a row, B the old ones on a shelf, C one at a time.
2. **Who uses which globe.** Mockup: your hand = midnight; your pet, workers and errands = sunset
   (one behind, as today). And the sunny globe: its workers stay on it (as drawn), move to sunset,
   or it becomes just a decoration?
3. **Bits:** pick 4 names (bulbs from the porch, fuses from the doghouse, magnets from their pond,
   frosted glass from the greenhouse; spares: doorbells from their gate, clock hands from their
   garden path).
4. **Fixes:** dust it off (works), a new bulb, magnets for the flap (2nd chute), frosted glass
   (shinies + lucky lights), the rusted hatch (midnight boxes + a midnight toy set). Prices are the
   sunset's x12 (24M .. 3.6B coins): fine as placeholders?
5. **The midnight toy set** (4 toys like the sunset's firefly, hedgehog, sleepy owl, paper
   lantern): names to pick later, or ideas now (little bat, moon pillow, glow jar, wind-up mouse)?
6. **Where it turns up:** the porch's broken machine event (`nd_machine`) gives the find, sure by
   the 3rd try like other finds?

### Lots of news at once (news-pile.html)
1. **Which look:** A one at a time with a stack, B a pile on the rug, C one welcome back letter
   (and A while you play).
2. **Same kind at once:** two full book pages = two cards, or one card with both stickers?
3. **What waits for what.** Mockup: a postcard and an unlock never share the screen (the unlock
   waits for the postcard to close: the bag-on-postcard item); popups still wait while a box or
   the plushie machine opens.
4. **What counts as news:** only things that open something or change a pet (unlocks, book pages,
   finds, a party home, the plushie tally), or small stuff too (errand goals, worn-out toys)?
