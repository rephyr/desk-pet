# GIFTS (care C): presents, done

Built as planned in GIFTS.md, with small changes noted below.

## What was built

- One present every 3 h of wall clock, open or closed (only the unix time counts), into a pocket
  of 3. No streak, no calendar. Nothing (not even the clock) until the boxes tab opens; the first
  comes 3 h after that. While the pocket is full the clock waits, so taking one out starts a fresh
  3 h. A clock set backwards never holds a present back more than 3 h.
- Opened, a present is rolled then: 1 box of `GameState.newest_box_id()`, a second box 1 in 5,
  and (once toys are open) a toy capsule as well 1 in 5. Never bits, never a pet.
- Home tab: your pet holds it wrapped in its paws while it sits on its spot; when it's busy (working
  the pile, even resting between packs, rummaging, holding up a good pull) the present waits on the floor by its spot, more stack small
  beside it (no number, no text). Tap the pet holding it, or the floor presents: a shake (0.4 s),
  a gold pop, the box flies to the pile with "+1 box" / "+2 boxes"; a toy shows the machine's
  prize card (same title, tag, "new!"). Unlock cards wait while a present opens or its toy card is
  up (`HomeTab.busy()`, like the machine).
- Desktop (QuietPaws): at big things and everything, standing on a window edge (not the bottom of
  the screen) with a present in the pocket, it digs (1.6 s: dirt flung behind it, the present rising
  out of a little heap) and wears the present on its head (follows its bob and squash, nestled
  between its ears) in every pose, walking and falling. A good pull is held up over the present.
  A tap on it (the present is part of the tap area) opens it instead of a pat: a burst of paper
  bits, a tiny pack (or a capsule for a toy) hops up and fades. It then waits 30 s before digging
  up the next. At off it doesn't dig; the present waits on the home tab. If the pocket is emptied
  on the home tab the present on its head just goes. Priority: hold > dig > wait > stint.

## Files

- new `scripts/pets/gifts.gd` (`Gifts`: fresh, every, cap, tick, roll, clean, per_day)
- new `data/gifts.json` (every, first_after, pocket, two_boxes, toy, dig, dig_again, pop), loaded as `catalog.gifts` (scripts/core/catalog.gd)
- `scripts/game_state.gd`: `gifts`, `gifts_changed`, `newest_box_id()`, `gifts_waiting()`, `gifts_open()`, `_tick_gifts()`, `open_gift()`, `debug_set_gifts()`, `debug_gift_clock()`, `debug_gift_roll`; save/load/new game; SAVE_VERSION 25
- `scripts/pets/quiet_paws.gd`: `Pose.DIG`, `worn`, `dig_left`, `pop`, `pop_toy`, `can_dig()`, `dig_progress()`, `popped()`; `step()` takes `window_edge := false`
- `scripts/pets/paws_view.gd`: `draw_present()` (static, shared with the home tab), `present_zoom()`, `PRESENT_H`, dig dirt and heap, worn present, pop; `draw_pack()` takes an optional `alpha`
- `scripts/pets/pet_look.gd`: `top_row(parts, sewn)` (the first row of the art with anything in it,
  worked out once from the Image when the picture is made, kept next to the texture)
- `scripts/pets/pet_view.gd`: `top()` (the top of the pet's art, with bob and squash; looks up
  `PetLook.top_row` only when first asked, so only the desktop pet pays)
- `scripts/desktop_pet.gd`: `tap()` (present first, else a pat), passes `window_edge`, tap area grows with the present, a held pull sits over it
- `scripts/ui/home_tab.gd`: presents in paws / on the floor, `tap_gift()`, shake, pop, flying boxes, toy card, `busy()`
- `scripts/ui/machine_tab.gd`: `MachineTab.show_toy()` (the toy prize card, shared by the machine and presents)
- `scripts/home.gd`: unlock popups also wait for `_expanded.home.busy()`
- `scripts/dev/dev_driver.gd`: dev steps below
- `tests/test_core.gd`: `_test_gifts` (44 checks); `tools/balance.gd`: `_gifts`
- new `tests/flows/gifts.flow`

## Data shape

Save field `"gifts": { "next_at": float (unix, 0 = not started), "pocket": int 0..3 }`.

## Save bump (for the merge renumbering)

SAVE_VERSION 24 -> 25. Migration: nothing to convert (a comment in `_migrate`); `_load_save` reads
`gifts` with `Gifts.clean` and ticks the clock at the end of loading, so older saves with the boxes
tab open start the clock on load (first present 3 h later). Renumber this to whatever comes next.
v25 is already taken by other lanes (merge: reserve_capsules, wish: box tiers, sewing: plushie,
workshop: herd, house: scout_notes; merge is at v27). At the merge move it to the next free number
and update the "Save v25 adds `gifts`" line in docs/architecture.md, the `# v25 added presents`
comment in `_migrate` and the `# v25:` comment on the `gifts` load line. No conversion code needed:
the load path doesn't look at the version.

## Merge note: newest_box_id

`GameState.newest_box_id()` returns `FIRST_PET_BOX` ("starter") here. B1's box tiers live in another
branch: swap this one helper for the newest open tier. Nothing else names the box.

## Flows

- `gifts` (new, from pile_full): the 3 h step (2.9 h: 0, 3.1 h: 1), the pocket cap (20 h: 3), the
  present in paws, three presents, shake, pop, opened, a toy card, the unlock card waiting for it,
  the dig, worn, a good pull over the present, the desktop tap pop, the wait
  after a tap, off (no dig), then back home busy with the pile (the present stays on the floor, also while
  it rests between packs; at the end so the pile counts above don't depend on its timing).
  `expect fits` at the start, middle and end. Shots in
  `profiles/play-gifts-<lane>/shots`.
- Re-run: fits, paws, care, home_pile (all pass).

## Dev steps

- `gift <n>`: n presents in the pocket now (up to 3; starts the clock)
- `gift-clock <hours>`: the present clock moves that many hours on
- `gift-roll one|two|toy`: what the next present holds
- `desk tap`: a click on the pretend desktop pet
- `home gift`: taps the present on the home tab
- `expect gifts <n>`; `wait dig` / `wait worn` (the desktop pet digging / wearing one)

## Text to add

### docs/design.md (done, in Care)

Added the **Presents** bullet under Care (active side).

### docs/architecture.md (done)

Added the presents paragraph under Platform (after quiet paws) and "Save v25 adds `gifts`" under Saving.

### docs/dev-plan.md

Under care C: "done (lane care, GIFTS): presents every 3 h of wall clock, pocket of 3, from the
boxes tab; newest box (starter until B1: swap `GameState.newest_box_id`), sometimes 2, sometimes a
toy capsule; home tab paws/floor, desktop dig + worn + tap. Save v25 `gifts`. Flow gifts."

### CLAUDE.md "where we left off"

- Presents (care C): `Gifts` (scripts/pets/gifts.gd, data/gifts.json): one every 3 h of wall clock
  (open or closed the same), a pocket of 3, from when the boxes tab opens. Opened (`GameState.open_gift`):
  a box of `newest_box_id()` (starter until box tiers: the merge swaps that helper), 1 in 5 two,
  1 in 5 a toy capsule as well once toys are open; never bits or a pet. Home tab: your pet holds
  it in its paws (on the floor while busy), tap: shake, pop, box to the pile, toy card. Out on your
  windows (QuietPaws `DIG`, `worn`): digs one up on a window edge and wears it until you tap it
  (`DesktopPet.tap()`), not at off. Save v25 field "gifts". Dev steps `gift <n>`, `gift-clock <h>`,
  `gift-roll one|two|toy`, `desk tap`, `home gift`, `expect gifts <n>`, `wait dig|worn`. Flow gifts.

## Questions for Emilia (smallest safe pick taken)

- The first present comes 3 h after the boxes tab opens (not straight away). OK?
- A toy capsule comes **with** a box (1 box + toy), not instead of it. OK?
- A toy capsule opens right away (its picture card on the home tab), not at the machine. OK?
- Out on your windows, "off" hides the digging too (the present waits on the home tab). OK?
- It only digs on window edges, not on the bottom of the screen. OK?
- The "+1 box" floater over the pile when a present opens: keep it, or just the box flying over?
