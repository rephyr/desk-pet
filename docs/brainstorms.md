# Brainstorms: options not picked (2026-09-28)

The four brainstorms from docs/dev-plan.md ran on 2026-09-28. Emilia's picks are in the plan
(A2, C3, F1, F2). These are the options she didn't pick, kept in case they're wanted later
(e.g. a second whole-pet axis after the reels). All 8 gear upgrades were picked, so gear isn't here.

## Bad pets (C3)

### Spare parts (medium)
Take a spare pet apart at the workbench and one of its parts drops into your parts bag, where piles of the same part stitch into a star.

A pet gives one random part (odds lean to its best slot), which goes into GameState.parts. Parts are already stored as 'slot:id' -> count, so this scales. To avoid the known bag flood, parts from pets are only of that pet's rarity and pile up for stars (for example 10 of a part = a star, and stars feed D1 knack size or F2). The best parts stay adventure and dungeon only. Done by the shelf at the workbench.

- Pros: Strongest fit with the theme and Emilia's seed 'part them': a hundred commons to make your cat perfect; Storage already scales, and grafting and knacks already want parts; Gives a use to piles that would otherwise only be sold
- Cons: Waits for feature:parts (40 trips placeholder) and fits D more than C, so it can't be the first answer; The bag floods fast (a scrapyard crew already does); Can make hunting parts on adventures feel pointless unless dungeon parts are clearly better

## The new layer (F2)

### The Cradle (big)
Two pets go into the cradle, you pick where their bead bracelets are cut and joined, and one new pet hatches with beads from both, sometimes with a strange new look.

Every pet rolls a hidden 8-bead bracelet: dull, plain or bright beads. It rolls for army pets too, so every pack pet brings some. It only shows once the cradle opens (hidden until earned). You put in two pets and both are gone for good (fusion from design.md's risk list, grown up). You see both bracelets and pick a cut point: beads left of it come from A, beads right of it from B, and parts come from whichever side holds that slot. Each bead can glow up to gold, fade, or very rarely turn strange: a named mutation that changes the LOOK (tiny wings, a third eye, a shadow that lags behind). Perfect means 8 gold beads plus a set of mutations, built over many generations. Planning across generations is hard to hand off, so pets only run it later (a nursery job with pairing rules, worse than you).

- Pros: The longest chase on the list: a family line you work on for weeks, really really hard by design; Mutations are new LOOKS, which feeds the collection and the 'woah' more than a number would; Quiet darkness that never winks: two pets go in, one comes out, and your pet says 'they're in the egg!'; Also answers C3: bad pets with one bright bead become breeding stock instead of clutter
- Cons: Big build: bead art, mutation art, hatching, and a pet made from two others; Reads like breeding. Keep it kid-safe (knitting, beads, an egg), never family words; It doesn't use F1's reels, so the sacrifice machine needs its own job (or the cradle becomes the machine); Mutations need art per slot, and that's a lot of pixel work

### The Sewing Table (medium)
Grafting grows up: each stitch pulls a thread from the fed pets' spools, and you stop when the seam is as close to the part's number as you dare, because going over tears it off.

New axis: fit (0-100%) per sewn part, and fit multiplies that part's knack. No cards, just threads with numbers on them. The part shows a target (say 21). The fed pets' spools make the thread pile, and rarer pets add better threads. You pull threads one at a time and stop whenever you like. Going over tears the part off (the part is lost, the keeper is fine). Landing exactly on target makes it seamless, and the stitch marks disappear (stitch marks already exist in grafting.gd). Perfect means every part is a seamless mythic. The skill is counting what's left in the pile. Later pets sew with a plain 'stop at 17', and upgrades teach them to count.

- Pros: Builds on what exists (grafting.gd, stitch marks, fail chance by rarity), so it's the smallest step from the current code; Easy to learn, with real depth in counting the pile; The prize is visible: a seamless pet with no stitch marks
- Cons: It's blackjack underneath, even without cards. Rating risk is lower than poker but still there; Grafting is active-pet only today. It has to open to any pet to help E1's armies; 'Fit' is more abstract than stars or a glow

### Soul Candle (small)
Your keeper sits by a candle and you add pets one at a time to grow the flame, stopping before it goes out; the flame you keep becomes its soul.

New axis: soul, a level from 1 to 12 plus a colour. Each added pet grows the flame a step and blends in that pet's palette colour. At each step the flame might go out and drop back to the last level you locked in by stopping. There are no odds, only signs: the flame flickers and your pet chatters ('so warm!!' vs 'ooh, wobbly'), the same feeling words adventures use. The added pet's traits change the chance. Perfect means level 12 in one pure colour, so every pet added shared a palette, and you had to sort and save them up first. Later a pet runs it with a stop rule, and a sorting job gathers pets by colour.

- Pros: Small build: a candle, a level, blended colours; Feels like the same game as adventures (push your luck, feeling words, nothing shown as a number); The pure-colour chase gives C3 bad pets a sorting job
- Cons: Go-or-stop is easy to automate ('stop at 6'), which works against 'more complex than a lever'; Only one choice per step. The real depth is in the sorting beforehand; Covers the whole pet and doesn't touch parts, so less 'woah' than changing a part

### Star Sign (big)
Pets you feed in become stars that you place on your keeper's star chart, one at a time, to finish a sign's shape; a finished sign lights up and gives a big boon.

A fed pet becomes a star in its palette colour, brighter if it was rarer. You see it plus the next two and place it on a small grid over a faint shape (a cat, a kite, a crown). Lines only join neighbours the sign allows, and a bad spot leaves a dim stray star in the way. A finished shape gives a big multiplier plus a boon only that sign gives. Perfect means the rarest sign with every star at mythic brightness. It's a puzzle with a random stream, like Tetris, which is the clearest reason pets can't do it at first. Later a stargazer pet places stars by simple rules.

- Pros: The prettiest theme on the list: on the surface it's just a starry chart; A real puzzle, the strongest case for 'too complex for pets at first'; Signs are something new to collect (a book page per sign)
- Cons: It clashes with the night sky, where a star per lost pet is never explained. Showing the star-making openly could spoil that quiet secret, or it could deepen it. Emilia should judge; Big build: grid, shapes, colour rules, a preview of upcoming stars; Puzzle fun is a different kind of fun than gambling, and it covers the whole pet, not its parts

### Brave Patches (big)
You take a small squad of your very best pets deeper than the army has been, one floor at a time; the ones who make it home get sewn-on patches that make them stronger for good.

New axis: patches earned by surviving, not from a machine. Pick 3-5 of your best for a deep dive. On each floor any pet can earn a patch (first to floor 30, the goose's own) or be lost. After each floor you choose: go on, send one pet home with its patches, or change the plan. Patches stack into power, and sets give boons. Perfect means one pet carrying patches from the deepest floor of every dungeon, still alive. Your best pets are the stakes, the 'great gamble' from the adventures brief. Later a sergeant pet leads dives by your retreat rules.

- Pros: The darkest arc and a clean fit for the theme: veterans, losses by choice, patches sewn on; No new machine: it uses E1's floors; Your own great pets are what's at risk, the biggest stakes on the list
- Cons: Needs E1 built first, so it comes late; Closer to a mode of E1 (a squad dive) than a new layer on pets. It may belong in E1's design instead; Much overlap with adventure push-your-luck (hearts, go home), and more tactics than gambling

## The darker currency (F2)

### Hugs from hard workers (medium)
Pets on jobs slowly fill up with little hearts, and when you spend one, all its stored hearts pop out at once.

Every worker, errand crew and army pet builds up devotion over time (faster for rarer and more perfect pets), shown as tiny hearts over its head. When it's spent (dungeon, sacrifice machine, F3), the stored amount pays out. To handle millions, it's tracked per group (job x rarity x time on the job), not per pet. Later a policy like 'spend the ones who've served longest' automates the choice.

- Pros: a real timing choice: spend now, or let them fill up more; keeps the whole automation layer useful (old workers become the currency's farm); very cute on top, dark underneath ('they loved you the most'), without ever winking
- Cons: close to generic idle income unless payouts only happen on spending; needs the group bookkeeping and a save field for it; the name 'hugs' may push voice lines towards winking; the name is a separate choice

### The little flowerbed (medium)
Every pet you spend plants a flower in a patch, flowers bloom over hours and you pick their petals.

Merges the brainstorm's collar bells and petals (both 'one keepsake per spent pet'). Each spent pet plants a flower tinted by its palette (like its star). It blooms on a timer (hours at first, faster with upgrades) and gives petals by rarity x perfection. You pick blooms by hand, and later a gardener job does it. Past a few dozen flowers it becomes a counted field (no per-flower drawing). A small patch caps how many unpicked blooms wait, which is the offline limit.

- Pros: the timer gives the slow early trickle for free, plus an offline source; a manual picking chore with a clear later automation (the gardener); a strong never-winks picture: a pretty garden that is a graveyard; the flowers are counted, so the night sky can stay uncounted
- Cons: a second memorial next to the night sky; the two can dilute each other; pays per lost pet, which nudges players to throw pets away; timers plus picking can feel like a mobile farm game; needs a spot in the full UI (X1)

### Ribbons from the pet show (big)
You enter your best pets into a judged show, push your luck through a few rounds, and win ribbons.

The F2 'gambling loop more complex than a lever' doubling as the source. Pick a pet, then a few rounds (grooming roll, pose, judges' mood), each asking push or stop. Placing pays ribbons, scaled by rarity and perfection. 'Winner takes all' rounds stake the entered pets (only by choice). Too many choices for pets at first; later a trainer pet runs the heats and the finals stay yours.

- Pros: gives the currency an active manual source (always something manual); pet quality matters directly (better pets place higher); great voice space: losers 'went home with a lovely participation ribbon'
- Cons: a big build, a whole minigame; really an answer to brainstorm 3 (the F2 layer); only worth it if Emilia picks a show as the layer; the darkness is weak unless the stake rounds cost pets

## Other bundles

### The nursery (the cradle)
- Bad pets: Busy paws, then the sorting rule with a keep line for 'one bright bead'. Most spares go to New homes, and pets with a good bead become cradle partners.
- Layer: The Cradle: two pets go in, one hatches with beads from both. You pick the cut point, and rare mutations change the LOOK. It takes generations and weeks.
- Currency: Hugs from hard workers: old workers and crews fill up with hearts, and the hearts pop out when you spend them (in the cradle, in dungeons). Dungeons also drop hugs.
- Story: A cosy knitting and egg nursery. Your pet says 'they're in the egg!' Two go in and one comes out, and the pets who served longest are the best to spend. Very cute on top and the darkest underneath, never winking.

### The sewing room (grafting grows up)
- Bad pets: Busy paws, then Spare parts at the workbench (a spare pet gives its thread spool and a part of its own rarity), with the sorting rule sending pets there once it opens. New homes stays small for pets with nothing to give.
- Layer: The Sewing Table: pull threads from the fed pets' spools up to a part's number, stop when you dare, going over tears the part off. Landing exactly on the number makes the seam invisible (the stitch marks go away).
- Currency: Dungeon lanterns only: one source, one curve, never paid per loss.
- Story: The smallest step from today's code: grafting and stitch marks already exist. Bad pets become thread and parts, and a seamless pet is the proof of how many went into it.
