# MERGE done: lanes/b1 (box tiers) into lanes/wish (test + A4 book)

`git merge --no-ff lanes/b1` (4 commits: sunny/sunset/midnight box tiers, machine odds, play.py
lane name). Merge base 9e57dd0. Resolved and tested; left staged (not committed yet).

## Conflicts and how they were resolved

- scripts/game_state.gd: kept `static var testing` (ours) and `WORKER_BOXES_MAX` (b1);
  SAVE_VERSION = 25. `_migrate` comment now says "v25 added box tiers".
- scripts/dev/dev_driver.gd: all three dev steps kept: `book <page> [left]`, `stickers off`,
  `tiers all|off`.
- scripts/ui/unlock_popup.gd: kept `_sticker_showing`, `_quiet_stickers` and b1's
  `static var up`; `_show` sets `_sticker_showing`. After review: `up` is set when a card is
  QUEUED (unlocked handler, `_queue_sticker`), `_close` leaves it on while more wait
  (`up = not _queue.is_empty()`), `quiet_stickers` recomputes it, `_exit_tree` clears it. Before,
  the boxes tab could play a new tier's one-time greeting in the frame before the card popped.
- docs/architecture.md: one save chain (v23 scout_notes, v24 stickers, v25 box tiers).

## Save chain (renumbered)

- v23 = `scout_notes` (A3), v24 = `stickers` (A4), v25 = box tiers (b1's v23).
- No migration step checks a version: all three fill missing fields with defaults, and
  `BoxShop.fix_retired` (lucky -> sunset, `boxes_bought` / `boxes_greeted`) runs on every load.
- Old saves from every version load: b1's test uses a v24 save, the book test a v23 save, and a
  new test loads a v22 save with a lucky box and a full eyes page -> sunset boxes, the eyes
  sticker, scout_notes 0, saved back at v25.

## Fixes found by the merge

- `GameState.machine_odds` (b1) used `toy_boost("luck")`, but pulls use `boost("luck")` (toys x
  book stickers) since A4. The prize card now shows the same luck as a pull, so the magnifying
  glass (eyes sticker) shows in its odds. Test: golden capsule odds go up with the eyes sticker.
- tests/flows/box_tiers.flow: `stickers off` after `view full`. Opening 9 sunset boxes (about 23
  pets) sometimes filled a book page, and the sticker card covered the `many` and `three_tiers`
  shots. That run also showed the midnight box's arrival waiting while the sticker card was up
  (`UnlockPopup.up` works with sticker cards).

## Checked, no change needed

- Part leaks: every part roll (trips, scrapyard / jobs, rummage, machine) goes through
  `Rewards.roll_part(box, ...)` / `catalog.parts_in(..., box)`. `parts_of_tier` is only used by
  `debug_give_parts` and the catalog's own default part.
- Multi-pet boxes: the book fills from `collection.add`, so every pet in a sunset box counts.
  Test: the last two eyes of a page arriving in one 2-pet add open the sticker.
- play.py: one profile suffix (`play-<flow>-<lane>`), one docstring paragraph.
- No leftover "lucky" box ids in data (machine.json `"lucky": true` is the lucky-capsule flag).

## Review fixes

- OddsCard (machine_tab.gd) also refills on `sticker_opened` (a luck sticker changes the odds
  while the card is up). docs/architecture.md OddsCard line says so.
- UnlockPopup.up is set on queue (above). box_tiers.flow checks the sunset box greeting after
  `click "lovely"` (`wait text "new boxes!*"`); the sunset_new shot now shows it.
- Rerun: test_core ALL PASSED (3550), balance clean, flows box_tiers, machine_odds, fits,
  unlock_popup, boxes PASSED; shots sunset_new, three_tiers, odds_lucky checked, nothing past
  the window.

## Results

- test_core: ALL PASSED (3550 checks). balance: runs clean (box tiers table: sunny 1.00
  pets/box, sunset 2.50, midnight 2.50).
- Flows (DESK_PETS_LANE=wish), all PASSED: fits, tutorial, boxes, box_tiers, machine_odds,
  unlock_popup, pet_box, book, errand_jobs, errand_tools, workers, errands_crowd, home_pile.
- Screenshots checked: box_tiers (sunny only, sunset new!, also inside, many, three tiers), book
  (popup, finishes page), machine_odds (prize card), pet_box, boxes, fits errands, tutorial.
  Nothing past the window.

## Text for the dev plan

> MERGE b1 into test+A4 done: box tiers + book stickers together, save chain v23 scout_notes /
> v24 stickers / v25 box tiers. The machine's prize card uses the full luck (toys x stickers).

## Text for CLAUDE.md "where we left off"

> - Merge (2026-09-29): lanes/b1 box tiers merged over A3 jobs + A4 book. Save v25 = box tiers
>   (was b1's v23; v23 scout_notes, v24 stickers). `UnlockPopup.up` is on while any card (unlock or
>   sticker) is up or queued (a new box tier's greeting waits for them). Flows with many box opens use `stickers off`.

## Question for Emilia (left as it is)

- The glitter jar (finishes) page needs glitch (sunset box) and prismatic (midnight box only)
  now, and the part pages need the better boxes' new looks (parts.json `from`). So the book is
  a later goal than before. Should a page only count what the sunny box can give?
