# Polish pass 1 (2026-10-05): done notes

Lane `lanes/polish`. Late-game performance, scale and UI fixes, measured on a copy of Emilia's
playtest-1 save (tests/saves/late_playtest.json, 968 cards, 2.2k herd, 6.1Qa coins) and on that
save plus 30k cards and 5M herd pets (flow perf_huge). No new features, no balance changes, no
save version bump.

## How it was measured

- Dev step `frames <seconds> [label]`: frame times (avg / p95 / worst) and every frame over 25 ms.
  On Xvfb a frame includes slow software drawing, so the spikes matter more than the averages.
- Flows `perf_late` (every tab + the corner panel, with shots and `expect fits`), `perf_corner`
  (40 s of the corner panel) and `perf_huge` (30k more cards, 5M more herd pets).
- A throwaway profiler (not committed): a copy of the lane with a timing object at the top of
  every function, dumping the slowest functions of each spike frame.

## Performance, late save (worst frame, ms)

| where | before | after |
| --- | --- | --- |
| corner panel | 31-68, every second | 18-30 |
| machine upgrades | 26-50, every frame | 24 (avg 12.7 -> 7.5) |
| collection | 99-110 | 22 |
| adventures | 60-72 | 33-36 |
| dungeon page | 54-81 | 30-38 |
| errands | 40-75 | 26-30, every 3 s |

30k more cards (perf_huge): the 120 ms hitch every few seconds (errand speeds over 30k crew pets)
and the 250-500 ms collection spikes are gone; what's left is one ~120-170 ms frame per autosave.

## What changed

- **GameState tick:** the once-a-second work runs a quarter on each of four frames (runs and
  dungeon; errands; your pet's crank and machine workers; the workers' boxes). Crank and boxes
  keep their own clocks (`_auto_at`, `_boxes_at`); `_work_automation(now)` still does everything.
- **Machine.mult / add** are kept per upgrades bought (they walked the whole tree per capsule).
- **Machine upgrades page:** the tree draws only when something changes; the breathing ring of the
  next node is a small overlay. The card catches up on GameState.changed every 0.5 s (and right
  after a buy).
- **Adventures:** pets coming and going only rebuild the open picker, at most every 3 s.
- **Errands:** pets coming and going rebuild only the resting box; crews changing by themselves
  (new pets joining, `GameState.crews_by_themselves`) rebuild the board at most every 3 s. Your own
  moves still rebuild right away.
- **Collection:** rebuilds at most once a second from background churn; only planks whose look
  changed are built again.
- **Scale (tens of thousands of cards):** errand speed and tip sums are kept per crew and only
  added to as pets join (`_crew_sum`); `cards_of` is cached by rarity; the new homes stall's face
  uses the plain cards only; `spare_pick` goes through the cards once; spare counts are kept 3 s
  above 5000 cards.
- **Saves:** JSON and the file are written on a worker thread (late saves are megabytes, ~300 ms
  of JSON at 30k cards). The data is copied first; one write at a time; quitting waits for it.
- **Coins:** payouts are clamped under int's top (`COINS_MAX`, `coins_int`), so a huge payout
  can never wrap round to minus coins.

## UI fixes

- Automation tab: with 4 jobs (crank, adventures, boxes, the army) the cards needed 1082 px of a
  920 px window. More than 3 job cards now sit in a grid two wide.
- Corner panel: coins were written in full (6,133,081,954,988,431) and pushed the panel wider than
  its window. `expect fits` now checks the corner panel too when it's showing.
- Numbers: past T they go Qa, Qi, Sx, Sp, Oc, No, Dc (was 3.11e+15); `NumFormat` (scripts/core)
  holds the formatting. Raw counts now short: home notes (201473 boxes, 4832837 parts), the pile
  and part-tile badges (x158427), trail and home coin floaters, box reveal titles, postcards, the
  xp pill.
- Machine tree level pills used the display font, whose slash leans back at night ("3\3").
- Book marks beside the wishing jar are slimmer, so six full pages with a star each still fit
  (the wish flow spilled by 2 px when every page was full).
- Your pet said "all 1 home! perfect day!" for one pet: new voice situation `back_one` with two
  lines per personality (data/voice.json).
- Sewing a rarer part on moves your pet to its new shelf (`Collection.retier`; the shelf counts
  were already off before this).

## Round 2 (same day)

- `frames` also fails when the UI needed more room than the window in any frame, even one. It
  found two: the collection tab grew to 620 px for a frame on every rebuild (a new shelf plank
  went in before the old one left; fixed), and errands with 5M pets resting wrote "5,000,000" in
  the display font and pushed the window to 930 px (big pile counts are short now: 5M).
- The night sky (behind the panel and on the spine) painted itself again from scratch on every
  resize signal, several times a frame; now at most once a frame, and only for a real new size.
- The open book catches up on new pets at most every 3 s (it rebuilt every second, ~30 ms).
- The cushion's "best cards" works out each finish once, not once per card.
- The new homes stall's counts: one pass over the cards, counts only (it built lists of every
  card for six rarities).
- Errand upgrades: "a minute 4.2T → 4.2T" shows enough decimals to see the change (4.21T →
  4.23T, `NumFormat.apart`).
- Corner panel: "busy managing" hides while your pet holds up a good pull (they overlapped).
- Tried and dropped: opening the workers' boxes in four smaller batches a second. Every batch
  tells the views, so it cost more.

## Flows and tests

- Every flow passes; test_core ALL PASSED (6114 checks: number format, back_one lines, the
  crank/boxes clocks).
- `dungeon` flow: the deep run's orders come home at 90% (was 30%), so random losses can't turn
  it home before floor 22 (it failed once in the baseline).
- New fixture `tests/saves/late_playtest.json` (a copy of the save from before the 2026-10-02 new
  game) and flows `perf_late`, `perf_corner`, `perf_huge`.

## Merge notes

- New class `NumFormat` (scripts/core/num_format.gd): the editor picks it up on its own; a
  headless run needs `godot --headless --import` once.
- `_work_for_automation(seconds, show, boxes := true, rest := true)`: tools/pace_player.gd's copy
  of its lines is unchanged (it calls the whole thing).

## Questions for Emilia

- **Cards at scale (C1):** holo and up are always cards. At 30k cards the autosave still costs
  one ~150 ms frame every 30 s (copying the pets for the save thread), and ~150k cards would be ~5x
  that. Keep "holo+ are always cards", or only holo+ with something extra (a new part, a trait)?
- The machine upgrades page early on: three nodes sit at the bottom of a big empty tree. Frame
  the part of the tree that shows (it would grow as you fix things)?
