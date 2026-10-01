---
name: Desk Pets
description: A sticker book at midnight - cute pets and collectible cards on a dark violet page.
colors:
  bubblegum-pink: "#ff79c6"
  lilac-glow: "#c9a0ff"
  ice-cyan: "#8be9fd"
  star-gold: "#ffe08a"
  mint-leaf: "#8fe8c0"
  petal-text: "#f5dcec"
  dusk-muted: "#9a88ad"
  midnight-page: "#1a1024"
  deep-night: "#120a19"
  raised-plum: "#241634"
  trail-paper: "#1b1324"
  lilac-seam: "#6f588c"
  pink-seam: "#a64f81"
  pink-pressed: "#592a45"
  tier-common: "#8a7f99"
  tier-uncommon: "#6fe3a8"
  tier-rare: "#5cc8ff"
  tier-epic: "#b77dff"
  tier-legendary: "#ffc857"
  tier-mythic: "#ff4f9a"
typography:
  display:
    fontFamily: "Coiny, Maple Mono, sans-serif"
    fontSize: "30px"
    lineHeight: 1
  headline:
    fontFamily: "Coiny, Maple Mono, sans-serif"
    fontSize: "20px"
    lineHeight: 1.1
  title:
    fontFamily: "Coiny, Maple Mono, sans-serif"
    fontSize: "16px"
    lineHeight: 1.3
  body:
    fontFamily: "Maple Mono, monospace"
    fontSize: "13px"
    lineHeight: 1.45
  label:
    fontFamily: "Maple Mono, monospace"
    fontSize: "11px"
    lineHeight: 1.4
rounded:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "10px"
  xl: "12px"
  panel: "14px"
spacing:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "10px"
  xl: "12px"
  xxl: "14px"
components:
  button:
    backgroundColor: "{colors.deep-night}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.md}"
    padding: "6px 14px"
  button-hover:
    backgroundColor: "{colors.deep-night}"
    textColor: "{colors.bubblegum-pink}"
    rounded: "{rounded.md}"
  button-pressed:
    backgroundColor: "{colors.pink-pressed}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.md}"
  card:
    backgroundColor: "{colors.raised-plum}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.xl}"
    padding: "12px"
  panel:
    backgroundColor: "{colors.midnight-page}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.panel}"
    padding: "12px"
  speech-bubble:
    backgroundColor: "{colors.raised-plum}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.panel}"
    padding: "14px"
  pet-card:
    backgroundColor: "{colors.raised-plum}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.lg}"
    padding: "6px"
  tab-active:
    backgroundColor: "{colors.pink-pressed}"
    textColor: "{colors.petal-text}"
    rounded: "{rounded.md}"
---

# Design System: Desk Pets

## Overview

**Creative North Star: "Sticker book at midnight"**

Desk Pets looks like a well-loved sticker book opened under the covers at night. The page is a
dark violet (in the current plum theme), and everything on it is a sticker: outlined cards that
lift off the page, pixel-art pets with crisp edges, crayon doodles on the map and the trail.
Collecting is the point, so things you own look like things worth keeping: each card carries
its rarity as the colour of its outline, and rare things get their own glow.

The mood is cute and upbeat at every depth. The palette is soft pastel neon on dark plum: pink
leads, lilac holds the structure, cyan means coins, gold means sparkles and xp. Density is
cozy rather than packed; the home panel is tiny and quiet, the expanded view is roomy.

Direction from here (chosen, not fully built yet): cards and panels become **soft lifted
stickers** with a gentle dark shadow, and everything you press feels **squishy and tactile**,
with chunky rounded outlines and a small squash on press, like the pets do.

These are browser mockups for a Godot game, so only looks Godot can draw belong here: flat
colour, borders, rounded corners, drop shadows, glow, drawn doodles, pixel art at whole-number
scales. No blur, glass or gradient-mesh tricks.

**Key Characteristics:**
- Colour themes are open (light and dark being explored); plum is the current default
- Outlined, rounded sticker cards that lift off the page
- Rarity lives in outline colour; glow is saved for rewards and rare pulls
- Pixel-art pets with nearest-neighbour scaling, beside crayon-style doodles
- Coiny for moments, Maple Mono for everything else; colours, font and icons are player settings
- Lowercase, friendly copy; the pet talks in speech bubbles

## Colors

Soft pastel neon on dark plum: three accents with fixed meanings, one gold for sparkles, and a
set of rarity colours that belong to the collection.

### Primary
- **Bubblegum Pink** (#ff79c6): the voice of the game. Titles, hover and selected states,
  the speech-bubble outline, the active tab, anything that says "look here". Pressed states
  use a deep pink (#592a45); resting outlines use a muted seam (#a64f81).

### Secondary
- **Lilac Glow** (#c9a0ff): structure. Card and button outlines at rest (as the darker seam
  #6f588c), hints and secondary text on drawn scenes, the scroll grabber.

### Tertiary
- **Ice Cyan** (#8be9fd): coins, always. The ◆ counter, coin pickups, prices.
- **Star Gold** (#ffe08a): sparkles, xp and streaks; the twinkle on good pulls.
- **Mint Leaf** (#8fe8c0): healing, growth and grass on the drawn scenes.

### Neutral
- **Petal Text** (#f5dcec): all body text; a warm pink-white, never pure white.
- **Dusk Muted** (#9a88ad): secondary text, disabled things, the padlock.
- **Midnight Page** (#1a1024): the main window background.
- **Deep Night** (#120a19): wells and buttons, sunk below the page.
- **Raised Plum** (#241634): cards, bubbles and panels on top of the page.
- **Trail Paper** (#1b1324): the paper behind drawn scenes (trail, map).

### Themes (a player setting)
The palette above is the default theme, **midnight plum**. Players pick a theme in settings
("the look"); every theme sets every colour role, so screens only ever use roles. The full
values live in `design/mockups/shared/themes.css`.
- **midnight plum** (dark, default): the colours above.
- **blueberry night** (dark): deep indigo page (#151a33), periwinkle structure (#a9b4ff).
- **cocoa strawberry** (dark): warm cocoa page (#1e1417), strawberry pink (#ff7e9d), peach
  structure (#f2b8a0).
- **lilac milk** (light): milky lilac page (#efe5f6), raised stickers #faf5fd, plum text
  (#3b2750), deeper pink (#d9468f).
- **peach sorbet** (light): peach page (#fbece4), cream stickers #fff7f2, cocoa text (#4a2b35),
  coral pink (#e05a7e).
Light themes darken coins, xp, mint and the rarity colours so they stay readable on a light
page; the meanings never change.

### Rarity
Owned by the collection (`data/rarities.json`): common #8a7f99, uncommon #6fe3a8, rare #5cc8ff,
epic #b77dff, legendary #ffc857, mythic #ff4f9a. Shown as outline and label colour, and as the
glow of a reveal.

### Named Rules
**The Fixed Meaning Rule.** Cyan is coins, gold is sparkles and xp, mint is healing. Never use
them decoratively; the player reads them before the words.

**The Roles Not Colours Rule.** Screens use colour roles (page, raised, deep, text, pink, lilac,
coins, xp), never raw colours, so any theme, light or dark, can swap the whole palette.

**The Rarity Belongs To Pets Rule.** Tier colours only ever mean rarity; UI chrome never
borrows them.

## Typography

**Default Fonts:** Coiny for display (with Maple Mono fallback), Maple Mono for body text

**Character:** Coiny is round, bouncy and loud, like a sticker title; Maple Mono is soft,
rounded and readable at small sizes. Coiny is for moments, Maple Mono for everything else.

**Font is a player setting** ("the look" in settings): Coiny + Maple Mono (default), or one
bold soft family for everything: Fredoka, Baloo 2, Nunito or M PLUS Rounded 1c. Every screen uses
the display and body roles, never a named font, so all five work everywhere.

### Hierarchy
- **Display** (30px): one-word exclamations on scenes, e.g. the "!" when a pet stops.
- **Headline** (20px): place names on the trail and map, streaks, big reveals.
- **Title** (16px): section headers.
- **Body** (13px): default text, buttons, speech bubbles, trip stories.
- **Label** (11px): small print: tags, rarity labels, odds, timers.

### Named Rules
**The Lowercase Voice Rule.** UI and pet copy is lowercase and friendly ("say welcome back").
Numbers and names keep their own case.

**The No Dot Separator Rule.** Never join bits of text with a dot or bullet separator
("52 pets · page 1 of 3", "greedy · earns more coins"). Give each piece its own element, line or
label instead, or use plain words and punctuation (a colon, a comma, "and").

**The Show Don't Explain Rule.** Never spell out a rule the game can teach by playing. No
"one thing at a time", "after you teach them", "your pet learns it first": the player finds out
when moving the pet stops the job it left. Labels name things; they don't describe the mechanics.

**The Hidden Until Earned Rule.** Anything not unlocked yet is fully hidden: no locked rows, no
"???" slots, no greyed-out columns, no "unlocks at…" hints. A new thing appears when it's earned
(the unlock popup is its introduction). Exception: something the player is already working
towards, like the next node on the machine tree.

**The Carrot Rule** (Emilia, playtest 1, 2026-10-01). What earns the next few unlocks is shown,
with its progress and the reward named: "next up" on the home wall (GoalsNote: the closest 3) and a
"→ errands  0/3" tag on the place card it's about. Only goals in reach (Goals: their other unlocks
open, their place open, their machine node on the tree). It names what to do ("trips to the
meadow", "pets sent to the old well 37/100"), never how the reward works. Unlocks don't come from
luck alone: a find's event turns up for sure on the 3rd trip that could meet it. A gold dot on a
tab also means a new upgrade there you can afford.

**The Display Is A Moment Rule.** The display size (headline and up) never sets a paragraph
or a button row; one or two uses per screen.

## Layout

Two canvases with fixed sizes: the home panel (300px wide, one column, tiny and quiet) and
the expanded view (920x600 logical px; 1.5x on the 4K screen).

The expanded view is an open book with a **starry spine** on the left (80px): a strip of night
sky sewn to the page with a row of stitches. Tiny dim stars dot the sky, one per pet that never
came back, tinted from that pet; never explained or counted. Your active pet sits on a little
moon at the top. Under it the tabs stand in a column (icon with the name below), settings at the
bottom. The active tab is a stitched-on patch (dashed pink border, tilted -3deg); a small gold
dot on a tab means news (or a new upgrade you can afford). The page on the right starts
with the pet's speech bubble, then coins, xp and the window buttons, then the tab's content.
Content often uses a wide main area and a narrower sticker on the right (about 248px, e.g. the
chosen pet).
Reference: `design/mockups/screens/`. Spacing moves in small steps (4, 6, 8, 10, 12, 14px); inner padding is usually 10-12px
on cards and 6px on buttons. Drawn scenes (map, trail) fill their area edge to edge.

## Elevation & Depth

Three tonal layers: Deep Night (sunk: buttons, wells), Midnight Page (the page), Raised Plum
(stickers on the page). Today the game is flat; the chosen direction adds a soft dark shadow
under raised stickers so they lift off the page, and keeps glow only for rewards.

### Shadow Vocabulary
- **Sticker lift** (`box-shadow: 0 6px 14px rgba(6, 2, 12, 0.6)`): cards, bubbles and panels
  resting on the page. Godot: StyleBoxFlat shadow_size 7, shadow_offset (0, 6).
- **Sticker lift, hover** (`box-shadow: 0 9px 18px rgba(6, 2, 12, 0.6)`): a card under the cursor
  rises slightly.
- **Reward glow** (`box-shadow: 0 0 18px <tier or accent colour at 45%>`): new pulls, good
  finds, the tutorial highlight. Never on plain chrome.

### Named Rules
**The Glow Is Earned Rule.** Glows mean "something good happened here". A glow on anything
routine teaches the player to ignore it.

## Shapes

Everything is rounded and outlined, like die-cut stickers. Borders are 2px (3px for reveals and
highlights); corners run from 8px on buttons to 12-14px on cards, bubbles and panels. Drawn
scenes use loose crayon lines (2-3px, rounded caps) and simple doodles: triangles for trees,
arcs for hills, tufts and dots for flowers. Pixel art stays pixel art: whole-number scales,
never smoothed.

## Components

### Buttons
Squishy and tactile: chunky outlines, sunk into the page.
- **Shape:** gently rounded (8px), 2px outline.
- **Default:** Deep Night fill, Lilac seam outline (#6f588c), Petal Text.
- **Hover:** outline and text turn Bubblegum Pink.
- **Pressed:** deep pink fill (#592a45), pink outline, and a small squash (scale about 0.95
  for 80ms) in the chosen direction.
- **Flat / small:** text-only links such as "watch ›" and "‹ map", pink on hover.
- **Disabled:** dark muted outline (#4d4457), Dusk Muted text.

### Cards / Containers
- **Corner Style:** 10-12px.
- **Background:** Raised Plum.
- **Border:** 2px, Lilac seam at rest; rarity colour on pet and part cards; pink when it's the
  pet talking.
- **Shadow Strategy:** sticker lift (see Elevation).
- **Internal Padding:** 10-12px (6px on small pet cards).

### Navigation
A row of tab buttons in the header. The active tab has the pressed style (deep pink fill, pink
outline). Locked tabs show a tiny pixel padlock in Dusk Muted until found.

### Speech Bubble (signature)
The active pet's voice: Raised Plum, pink seam outline (#a64f81), 14px corners, Body text in
lowercase, next to the pet's pixel portrait. Short, sincere, never shows odds.

### Pet Card (signature)
A small sticker with the pixel pet, its name and a rarity label; the outline is the rarity
colour (common and uncommon slightly darkened). Rare pulls glow in their tier colour on reveal.

### Icons
Two sets, a player setting: **doodle** (default: hand-drawn outlines on a 24px grid, 2px
strokes with round ends, slightly wobbly, drawn in the text colour; coins, xp and the heart are
filled with their fixed colours) and **pixel** (9x9 row-string pixel art, like the game's
padlock). Both sets have the same names: home, boxes, pets, trips, errands, gear, inventory,
lock, settings, coin, xp, heart.

### Errands: the corkboard
Jobs are sticky notes taped to a cork-speckled board, each tinted by its job colour, with a
meter, what it brings, and the crew pinned on as polaroids (a light frame, a pin on top). Past 6
pets a note shows a stacked pile of 3 polaroids, the count in the display font and a bobbing
crowd of tiny pets. Resting pets wait in a shoebox sticker on the right. A meter that fills
faster than you can see becomes a flowing stripe with "N coins a minute".

### Automation: job cards
A raised card per job (172 px wide, tinted by its job colour; the picked one gets the pink
stitched outline) with a deep well holding a drawn picture of the job: your pet's little capsule
machine with its crank going round, the box table with its lid hopping, the adventure gate with
its flag. Your pet sits in the well of the job it's doing; the others are faded and say "nobody
here". The side card (236 px) teaches, moves or takes your pet off, and lists the job's tools.
A pill top right says what your pet is doing. No hint text: moving your pet teaches the rest.
The workers page (a your pet | workers switch, there once the others know a job): the same cards,
the well filled with small machines (60%) each with its worker, 6 shown then "+N"; the side card
counts spots, working and resting pets, buys a spot, and puts pets on (− / + / fill up).

### Settings: the look (signature)
Colour themes show as tiny windows drawn in their own theme; fonts show "Aa" and a pet name
written in that font; icons show four icons in that set. The chosen one gets a dashed pink
outline and a small tilt. Choosing applies right away.

### Progress Bars
Rounded pill (5px) in Deep Night with a darkened outline of the fill colour: pink for food,
lilac for mood and trip progress.

## Do's and Don'ts

### Do:
- **Do** keep every surface on the violet ladder: Deep Night #120a19, Midnight Page #1a1024,
  Raised Plum #241634.
- **Do** outline stickers with 2px borders and 8-14px corners.
- **Do** keep colour meanings fixed: cyan coins, gold xp/sparkles, mint healing, tiers for
  rarity.
- **Do** scale pixel art by whole numbers with nearest-neighbour sampling.
- **Do** write UI copy in lowercase, short and friendly.

### Don't:
- **Don't** hardcode a colour in a screen; use the theme's roles so every theme works.
- **Don't** use blur, frosted glass, gradients across panels or other effects Godot can't
  draw.
- **Don't** glow routine chrome; glow is for rewards and rare pulls.
- **Don't** show odds, percentages or anything that hints the game is dark in pet speech.
- **Don't** set paragraphs or button rows in the display size.
- **Don't** over-explain: no hint lines about how a mechanic works; let play teach it.
- **Don't** show later features in plain sight (locked tabs, columns, "???" slots) before they unlock;
  a goal on "next up" names one only once it's in reach (the Carrot Rule).
- **Don't** use a dot or bullet (·, •) as a separator between pieces of text.
- **Don't** let anything spill past the window: one-line labels shrink with "…" or wrap, and
  layouts drop columns instead of growing wider.
- **Don't** use dropdowns (popups open behind the always-on-top window on Linux); use a row of
  choices.
