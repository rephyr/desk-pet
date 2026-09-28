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

# Brainstorm 2: options not picked (2026-09-28, evening)

## A5 the machine later

### Fever for everyone (the lever becomes the conductor) (small)
When your lucky lights fill, every little machine in the house lights up too, and for those seconds every capsule they drop pays fever.

In _pet_cranks (live ticks only, gap of 5 s or less), multiply capsule coins by fever_pay x toy_boost('fever') while fever_until is live. The same way pull_lever works out `pay`, so it touches coins only. Errands pay in capsules too, so they can share it (job_boost gets the same factor). That's a choice, see sub-questions. Only hand pulls fill the lights, so the more workers you have, the more your pulling is worth. Shown, not explained: MachineMini and the worker cards blink pink during fever, and the fever loop music is already there. Time away never counts.

- Pros: Answers A5's real problem head-on: past the crossover, pulling doesn't make your own coins, it doubles everyone else's; Grows with the worker count by itself and can never run away (a fixed x2-2.4 on coins, no new curve); Tiny build: one factor in _pet_cranks, plus blinking on existing views; Carrot, not stick: being away loses nothing, being there pays; Fits Emilia's rule that pressing may go out of date later: the lever turns from earner into booster without a hard cut
- Cons: Fully upgraded, fever (~23 s) lasts longer than relighting (~19.5 s), so it becomes a steady 'while you pull, the house pays double', not bursts. Fine as a presence bonus, but it kills the 'lights fill so slowly' irritant late on; If the house pays double while you pull, the invisible floor (option 3) isn't needed. Don't build both; 'Every capsule in the house' has to stop at coins: boxes, toys and parts get no fever (already true of Machine.loot)

### Shiny pet capsules (the lever's own road to a rare pet) (small)
Now and then a shiny ball bounces out with a pet box inside, and the pet comes out sparkly. A pet box from a lucky capsule leans rarer. Only your hand ever pulls these.

Add pet_box to the shiny roll in _capsule (it's only coins, golden, box and part today). A shiny pet box rolls its finish from shiny and up (the box's finish weights without 'normal'). A lucky-capsule pet box gets a rarity step through PetRoller.roll's force_tier hook, or a shifted tier table. Rates stay as they are: pet_box is ~1 in 400 pulls, so at max shiny (20%) a shiny pet capsule is ~1 in 2000 pulls, about an hour of pulling. With globes, the pet box rolls from that globe's tier. Workers never get pet boxes (already true).

- Pros: Ties the lever straight to the main goal, 'I want a good, rare pet', and no number of workers makes it obsolete; Almost no new code: the shiny roll, pet_box, PackOpening at the machine and the force_tier hook all exist; Needs no words: 'shiny ball, shiny pet' reads on its own; Rare enough (~1 per hour of pulling) not to rival B1's box buying
- Cons: Needs to settle whether the machine shows its odds (boxes and the plushie machine do, and the capsule machine doesn't today); Can feel like a reason to pull forever. Keep the rate modest: a treat, not a job; A lucky pet box already rolls ~1.3% of lucky capsules, so check a rarity step there against B1's sunset/midnight odds

## B2 where multipliers show

### The fridge in your pet's room (medium)
A little fridge turns up in the room on the home tab, and every boost you earn sticks to its door as a magnet. Tap the door to see what each one does, with the totals on a shopping list.

home_tab.gd already turns finds into furniture (cushion, basket, cart). The fridge arrives the same way, with the first toy play or book sticker, and it stands by the wall. Each source is a magnet: a toy doodle while it plays, the book page's sticker, the active pet's badges, and a recipe card while the kitchen crew works. Tapping it opens the door as an overlay about 560x420, with magnets grouped by kind on the left and a handwritten shopping list on the right with a total per kind and each line's number. A playing toy's magnet slowly slides down the door and falls off when the play ends. Past about 12 magnets, the door art shows a crowded pile and the list carries the numbers.

- Pros: The most show-don't-explain option: the door fills up as you earn things, with no menu; Home is the first tab. The room already holds finds and rummage spots, so there's no new tab; Pairs with A3's kitchen, which 'feeds your pet' and is being built now: the cooks can stand by it; A crowded fridge door makes a good picture of progress, and a nice screenshot
- Cons: Only on the home tab, so you have to go home to check; The room is already busy (window, rug, cushion, box pile, sticky notes, rummage spots, floor card), so it needs a spot mocked up; Ongoing pixel work: each new source kind needs a magnet

### Your pet's sticker sheet (medium)
Tap your pet on its moon and it holds up everything that makes it good: its sewn badges, the toy in its paw, the book stickers it has earned, with a number per kind underneath.

The moon tap in spine.gd (57-60) opens an overlay about 400x420 instead of patting. Pat stays on the home tab, which already has it on the pet and the floor card. At the top are the pet's portrait, its D1 look C badges and the toy it's playing with (already drawn on the moon). In the middle, book stickers sit as tilted stamps. At the bottom is a grid with one cell per kind the player has (coins x1.54, luck x1.3...). Tapping a cell lights up the badges, toys and stickers that feed it. The kitchen shows as a small 'from home' stamp.

- Pros: Fits 'the active pet is the commander': its badges boost everyone, so the pet is showing off; Grows D1's picked badge look into the one place for all boosts; Reachable from every tab (the moon is always there), and in-world
- Cons: Thin until D1 (phase D). Before that it's one toy and a few book stickers; The kitchen and the book aren't really the pet's, so the metaphor stretches; Swapping your active pet changes which badges count, so the sheet jumps around

## C2/F3 spending pets

### The swarm (no more party cap) (small)
A find removes the hay wagon's limit, and whole crowds go to the meadow, the pond, and down the well, where some don't come home.

Mostly built: GameState.max_party() already goes uncapped once the 'automation' unlock ("swarms that follow your rules") is on. Only debug grants it now. A find grants it (a flatbed or a whole barn door on wheels; name open), turning up after the hay wagon with N pets resting. Losses already run on party fractions (Party, AdventureRunner), coins grow with each pet, finds with sqrt(party). Workers' party spots (automation 'party': 3) can then take bigger n. Gear works at the meadow and pond, so the harness and leaf matter there, but NOT at the well, cellar or below (Gear.for_trip skips type 'dungeon'). New loot so the deep places are worth pets: bits for late machine nodes, a small sunset box chance. Pays in things that exist, no lanterns.

- Pros: Smallest build on the list: one find plus a few loot lines; the cap code exists; Starts the night sky filling right when pets per second starts, from where you chose to send them; Gives PolicyChooser (push on / go home / leave the wounded) real stakes: practice for E1; Lost only by choice holds: you pick the place and the size
- Cons: A drain by attrition, not a price: a big swarm to the meadow is mostly an income, and players will just avoid the losses; The well, cellar and below are already 'dungeon' places: sending swarms there before E1 uses up E1's first beat unless E1 clearly adds floors, army power and lanterns on top; Once the C3 herd lands, parties drawn from counts need made-up per-rarity records (Party.make wants Pet objects)

### Settling places (later, zone 3 onward) (medium)
Pets move into places you've already explored. A place with enough of them gets little roofs on the map, and swarms sent there come home safer and fuller.

Only once scouts have opened zone 3 (so it rides with every new page). Each open place gets a 'move in' count by shelf; steps at 100, 1k, 10k give that place fewer losses and more loot for parties sent there (a per-place multiplier in AdventureRunner, like a local harness + tote). No passive income stream (that would flatten 'always something manual') and no change to B3's machine cap per page (already decided). The doodle grows roofs; your pet: 'the pond has 1,200 friends now!'. Settled pets never come back; whether they add stars is Emilia's call.

- Pros: The invasion lore at its plainest: you fill land you've taken with your own, and the voice sees a housewarming; Keeps old places worth visiting all game, and makes the swarm option better; One sink per place, so it grows with every page the scouts open
- Cons: Per-place counts, levels and map art: medium build for a mid-priority sink; A multiplier on adventures again (next to gear): has to be clearly different (per place, bought with pets); Only useful if swarms are a real thing; skip it if the swarm option isn't picked

## E2 zone 3

### The little town (big)
A tiny town of creatures you never see: lit windows, a bakery that smells of buns, a clock that chimes at night. Each visit it gets a little quieter, and your pet thinks everyone's just asleep.

Page 'the little town', night paper. Places: the lamplit lane (start, exploration), the bakery (coins), the post office (rumours), the toy shop (toys, plus an old capsule machine to haul home for B3), the playground (safe, finds), the clock tower (risky: 'it rang and everyone wanted to play!'). Uses the same windows and visits counter as option 1. New bits: bulbs, keys, coils, which fix the hauled machines. The intel should NOT be the knocking cellar door (that needs E1 floor clears and pushes the midnight box late). Use the map corners, or a letter slipped under the cellar door (an existing event, 'a present was slipped under the door!') that turns out to be a street map.

- Pros: The strongest invasion reading of all the options, closest to Emilia's 'exterminating others from the zones'; The knocking cellar door and 'someone was home! they love visitors!' already hint at it; Every building has a clear job, so it reads well on the map
- Cons: Clashes with the adventures brief's 'No NPCs or towns'. The locals can only ever be traces; An emptying town is the easiest option to read, so it sits right on the edge of winking. Lines need care; The most new art: a doodle per building, plus the window drawing; Largely the same systems as option 1, just with more art

### The old fair (big)
Over the far fields the lights of a fair come on at night: a carousel, an arcade full of capsule machines, a prize stall. Nobody's minding the stalls, so your pets start running them.

Page 'the old fair'. Places: the ticket gate (start, exploration), the carousel (coins, a dizzy risk), the arcade (the most machines to haul home for B3), the prize stall (toys, box finds, a claw game event), the hall of mirrors (eyes parts), the ferris wheel (spotting, rumours). It shares the well line for dungeons (no ghost train: an empty night fair is a horror trope). Taking a stall turns its string lights your pet's colour and shows a tiny crew of your workers at it. The fair's own staff are only traces (a half-eaten toffee apple, a carousel still turning) and they just stop turning up. New bits: tokens and big cogs, which fix arcade cabinets (spot cap + speed). Intel: an 'admit one' ticket blows in on the far fields as an auto find, or the map corners. Don't use a machine capsule again, which would just repeat the fence scrap.

- Pros: Everything here is gambling and machines, so it deepens the core instead of adding a side theme; The arcade makes B3's 'machines come from places you've taken' feel physical; The lights and the ferris wheel suit the midnight box and the lucky lights / fever look; Workers seen running the stalls show your army growing without a word
- Cons: A weaker invasion: taking over a fair feels more like a new job than a conquest; A night fair must stay bright and sweet (no clowns, no ghost train) or the place itself winks; It stacks another machine theme onto a game that already has the machine tab and the plushie machine

### The shore (medium)
The stream runs all the way to the sea: dunes, glowing rock pools at night, a pier with an arcade, and a lighthouse your pets want to see up close.

Page 'the shore', a night beach (glowing rock pools fit the midnight box). Places: the dunes (start, exploration), the rock pools (eyes / palette parts), the crab rocks (locals as traces: little holes, tiny footprints; not a 'crab town', because of the brief), the pier (arcade machines for B3), the fishing huts (coins), the lighthouse (spotting; a taken lighthouse beam turns your pet's colour across the whole page). Shares the well line. New bits: sea glass and brass. Intel: the stream already has a bottle event ('the note is a map! and a little gift!'). Once beyond is open, a rare auto version brings the real map, and the stream's '?' cloud (stream has more: true) finally leads somewhere.

- Pros: Fresh scenery after grass and fields, and it answers the stream's '?' cloud that's already on the map; The intel reuses an event that's already written; The lighthouse is one clear, pretty picture of 'ours' that needs no words
- Cons: The weakest invasion reading: crabs are a soft target; The page is reached from a backyard place, not beyond, so the page order muddles (fine if it's gated on beyond being open); A beach is sunny by nature, and the midnight box makes it a night beach

## E1 the first dungeon

### The cellar doors only (the smaller first dungeon) (medium)
Behind the little door is a hall of doors, someone knocking on each; big doors test power, tiny doors let only rare and up through, and a key on a ribbon hangs behind the 10th.

Only the cellar turns into the dungeon: its rumour stays, and the well and further down stay trips for now (further down can become the second dungeon later). Each floor is a door with a strength and a size: floor 4 needs 5 rare+, floor 8 needs 3 epic+ (tiny doors, drawn small). Knock-back doors test luck. The 10th door drops the key to E3; the hall carries on past it for farming (strength about 100 x 1.2^n).

- Pros: Half the build of A, with the most readable picture: a hallway, doors swinging open, a lantern over each; Rarity is a requirement for the first time: 'armies of good pets' made literal; The door texts already exist ('someone was home! they love visitors!'), and the key is a real key
- Cons: A tiny door can hard-block wrong shelves, so its size must read at a glance, with no text; Further down stays a plain trip that 'goes further than anyone's been', which feels odd next to a dungeon; Only doors as floor kinds, so the policies have less to grip

### Policies: marks on the shaft (medium)
No words: a flag pin on the floor to stop at, and a ribbon on a jar of tiny pets marks when to come home; the same picture is the run you watch.

The cross-section is the control: ‹ › moves the flag one landing, ‹ › moves the ribbon in 10% steps. During a run the jar empties as the count ticks down; when it passes the ribbon the army turns round. Extra orders become small stickers on the jar, so it tops out at 3-4 rules.

- Pros: Show, don't explain at its best: goal and cost in one picture; Setup and watching share one drawing, so less UI; Cute on top, with the quietly darkest picture in the game underneath
- Cons: Custom drawing (like MachineStage), more work than the card; Room for only a few rules, so the earned lines of the card have nowhere to go; The draining jar must stay cheerful (sparkles, never falling pets) or it winks

# Brainstorm 3: options not picked (2026-09-29)

## E3 the hard dungeon

### The heavy doors (someone has to hold them) (small)
Past the key, every landing has a heavy door that swings shut. A few pets stay to hold each one open so everyone can come back up, and if nobody holds it, there's no going back.

A band behind the floor 20 key drawn as its own back stairs, so it doesn't replace E1's 21+ stairs. About 10 landings. Each door shows its holders as paw prints (e.g. 3 in rare colour). One new order line: 'who holds the doors ‹plain ones› / ‹anyone› / ‹nobody›'. Holders leave the fight, so the army carries on with less power. When the army turns back it comes up through held doors and the holders walk home with it. A door you didn't hold has shut, so 'come home when ‹30%› are gone' only works back to the last held door. ‹nobody› means a one-way trip, and the game never says so. If the army is lost below, its holders stay. The first time, draw holders waving on the way back up so the rule reads without text. Lanterns: holders count as sent, never paid for when lost. The last landing opens a quiet workroom with the plushie machine.

- Pros: The cleanest bridge to sacrificing: you pick pet by pet who gets set aside, which rehearses feeding the hopper; One dictator clue, fully in your orders: 'nobody holds the doors' is a sentence you wrote; Retreat becomes a real trade (holders cost power, skipping them costs the way home) instead of always the safe pick; Small build on E1: same power maths, a holder count per door, one order line, and the retreat line checks the last held door
- Cons: It can feel like a tax on the herd if holder counts are high. Keep them small and rarity-coloured so it's quality, not count; The rule ('holders come home if you do') has to be worked out. It needs a clear first picture; The least new picture: it looks like more of the well; Same drawing as E1, so it needs something of its own (heavy doors with paws on them) or it reads as 'E1 but meaner'

### Under the doghouse (shh, it's sleeping) (medium)
Once next door's doghouse is ours, a hatch shows in its floor. Something big sleeps down there, and a big noisy army wakes it up, so only a small crowd of really good pets gets to the bottom.

A dungeon under E2's doghouse, about 10 floors plus endless farming floors. What's new: a sleep bubble per floor that fills with pets sent AND with time taken (a big army is slow on the ladder, so speed matters). It hooks onto the 'thing' event's existing sneak option (tag sneak, stat speed), the zoomy trait and trip knacks (fox trot, fresh air), and there are no new 'sneaky' knacks. Army power still has to beat floor strength, so the sweet spot is ~20-60 very good pets. If the bubble pops, the orders decide: 'if it stirs ‹tiptoe back› / ‹keep going›' and 'who sings it back to sleep ‹plain ones›' (the singers stay for a nap). Waking it uses the 'thing' losses ('it woke up and wanted to play!'). The dog is only ever a trace: a tail, snore bubbles, a big shadow. At the bottom, in an old basket, the plushie machine.

- Pros: Hard in the opposite way to E1: fewer, better pets instead of more; Gives speed and the zoomy trait a real job in dungeons (power has had the spotlight); Reuses what exists: the doghouse (E2), the 'thing' event text and its sneak/speed option; Small armies pay few lanterns (per pet sent), so it's a real choice between farming the well and clearing this
- Cons: Waits for next door (past the edge, stage 3), and E1 already waits on C3's herd, so the order is risky; Reworks E2's decided doghouse (a risky adventure spot) and puts a second machine on the same page as the porch's midnight globe; The sleep bubble is a new number next to power and has to read with no words; A dog under a doghouse is a local, so it must never be shown hurt. Taken-place lore and 'wanted to play' losses sit close to the line

## Wisps: perk tree + room upgrades

### The pincushion (on the plushie machine's side card) (medium)
A fat tomato pincushion sits on the card beside the pink cabinet, and every perk is a coral-headed pin you push in. It's the sewing corner, so it's just where pins go.

NOT a fourth workbench page (the workbench is your pet | toys today, and the plushie machine will be the third). Tap the pincushion on the machine's keeper/hopper card and the card turns into the pins; tap again to go back. 16 pins in 3 rings (inner: P1, P5 hopper, P11 warm glow, P14 your own hand; middle: army, holds, nudges, pets/sec, nightlight, bell; outer: P4 lantern oil, P8 thread, P9 softer stuffing, P17 second card, plus the 2 endless tips). A pin shows once a neighbour is in, and levels stack a little tower of pins in one hole. Timing fix: until the plushie machine exists (after the hard dungeon), the entrance (P1) and the army perks are plain buys on the dungeon page's orders card. When the machine arrives they move into the pincushion as pins already pushed in.

- Pros: One sewing corner for the whole darker layer: stuffing, buttons, pins; A round web is small by nature and reads as one finished picture when full; A pincushion is an everyday object, uneasy only if you look at it that way, so it never winks; No new tab and no new page: it swaps the side card that's already there
- Cons: Two homes over time (orders card first, pincushion later) is a split tree, and moving pins across can feel odd; Dungeon earners have to walk to the workbench to spend; 16 pins plus stacks at ~28 px each is tight on a side card, so maybe it needs the full page width while open; Pins say little by themselves, so the card does all the talking

### The prize counter (tap the coral pill, from any tab) (small)
Once the currency exists a coral pill sits next to the coin pill. Tapping it opens a little arcade prize counter: shelves of perks with coral tags, and higher shelves light up as the total you've ever earned grows.

An overlay about 560x420, like B2's receipt, opened from the pill, so it's one home reachable from the dungeon and the plushie machine alike, from the first lantern. Pegboard-style rows like errands upgrades (numbers, price tags). Shelves open by currency EARNED over all time, not spent: shelf 1 at 0 (P1, P2, P3, P11, P14), then 5k (P4, P13, P16, P18), 200k (the plushie ones, shown only once the machine opens), 10M (P15, P17, the self-feeding caps), and the top shelf holds the endless tips. Spending on gambles still counts toward the next shelf, so the gamble-or-perk split never slows the reveal.

- Pros: Solves the split homes: both sources, one counter, reachable anywhere; Smallest build: a list with prices, the same pattern as the pegboard and the receipt overlay; Earned-not-spent gating treats lanterns and stuffing fairly; Easy to tune and extend in data
- Cons: The least magical option: a shop, not a picture that fills up; The top bar gains a third pill (coins, the receipt's x1.54, coral), so it needs a space check at 920 wide; A shelf can light up long before you can afford anything on it; An arcade counter is a little generic next to the sewing and well themes

## F3 spending pets

### The pillow on the new homes stall (maybe) (small)
Beside the box jar on the new homes stall sits a big soft pillow. Fill it with pets of one rarity and the next box you rip yourself gives a pet at least one step rarer.

The same tap-a-shelf, 1/10/100/all stall (C3 look A). One pillow per rarity: uncommon (to rare+), rare (to epic+), epic (to legendary+), never to mythic. Price set against the box jar so it's only a little better than trading the same pets for boxes: 150 rares = 750 points = 30 sunny boxes = about 1.2 epics expected, so a sure epic for 150 rares (placeholders). Only your own rip counts, never box tables or your pet's opening. Needs a floor in PetRoller.roll (today force_tier sets the rarity exactly): tier = max(rolled, floor), within that box's tiers.

- Pros: Turns spare rarity into a sure step on YOUR rip, so opening by hand stays worth it all game; Reuses the stall's UI, a small build; Voice: 'they made a big soft pile for the new friend to land on!'
- Cons: A pets-into-better-pets converter: set the price wrong and it becomes the pet engine; Close to new homes and the wish list (all three aim at the pull); Emilia passed on a similar force_tier rarity step (shiny pet capsules); A mythic pillow would undercut the main chase, so the cap must hold for good

## G care + the desktop pet
