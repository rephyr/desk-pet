# POSTCARD lane: done

## Built

1. Unlock popups vs the trip postcard. The "welcome back" postcard already held unlock cards
   (AdventuresTab.busy(), commit 4f9fd0b, flow postcard_wait). The hole left: a trip the **bell
   rope** welcomed back pops its postcard from AdventuresTab._process, and that didn't wait for an
   unlock card that was already up, so the card sat on top of the postcard. The bell postcard now
   also waits for `UnlockPopup.up` (one condition, same as BoxesTab does). Both orders are covered
   now: postcard up -> card waits; card up -> postcard waits.
   New flow: `postcard_bell` (bell built, a card up, trip comes home: no postcard until "lovely",
   then it shows). It failed before the fix (shot showed the card over the postcard), passes after.
   postcard, postcard_wait, unlock_popup, workshop flows pass.
2. Flaky core test "v21 and v23 saves load the same". Cause: the test's old-save fixture rolls its
   pets with PetRoller, which stamps `pulled_at` with the wall clock (whole seconds). Each save in
   that check is built a moment apart, so when a second ticked over between them the pets'
   `pulled_at` differed (reproduced 3 times in 120 tight-loop comparisons). The game's load is
   fine; the fixture wasn't fixed. Test pets now get a fixed `pulled_at`. 0 diffs in 180
   loop comparisons after; core tests passed 10 runs in a row (6117 checks).

## Save version

No bump.

## Merge notes

- scripts/ui/adventures_tab.gd: one line in _process (bell postcard condition).
- tests/test_core.gd: one line in _collection_dict.
- New tests/flows/postcard_bell.flow (add to the flows list).

## Questions for Emilia

None.
