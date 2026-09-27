// Pixel icons and sample content for the mockups.
// Icons are row strings, like UiTheme.lock_icon() in the game, so they port straight to Godot.
// "o" = currentColor (recolours with hover/active), other letters come from the icon's palette.

const ICONS = {
  coin: { pal: { w: "#e8fbff", a: "#8be9fd", b: "#4fa9c9" }, rows: [
    "....w....", "...wab...", "..waaab..", ".waaaaab.", "waaaaaaab", ".aaaaabb.", "..aaabb..", "...abb...", "....b...."] },
  xp: { pal: { g: "#ffe08a", w: "#fff6d6" }, rows: [
    "....g....", "....g....", "...ggg...", "..ggwgg..", "gggwwwggg", "..ggwgg..", "...ggg...", "....g....", "....g...."] },
  heart: { pal: { p: "#ff79c6", w: "#ffd1ea", d: "#d4559f" }, rows: [
    ".pp...pp.", "pwpp.pppp", "pwppppppp", "ppppppppd", ".pppppdd.", "..pppdd..", "...pdd...", "....d....", "........."] },
  lock: { pal: {}, rows: [
    ".........", "...ooo...", "..o...o..", "..o...o..", ".ooooooo.", ".ooo.ooo.", ".ooo.ooo.", ".ooooooo.", "........."] },
  home: { pal: {}, rows: [
    "....o....", "...o.o...", "..o...o..", ".o.....o.", "ooooooooo", ".o.....o.", ".o.oo..o.", ".o.oo..o.", ".ooooooo."] },
  boxes: { pal: {}, rows: [
    ".oo...oo.", "..o.o.o..", "ooooooooo", "o...o...o", "ooooooooo", ".o..o..o.", ".o..o..o.", ".o..o..o.", ".ooooooo."] },
  collection: { pal: {}, rows: [
    ".ooooo...", ".o...oo..", ".o.o.o.o.", ".o...o.o.", ".o.o.o.o.", ".o...o.o.", ".ooooo.o.", "..o....o.", "..oooooo."] },
  adventures: { pal: {}, rows: [
    "..o...o..", ".ooo.ooo.", "..o...o..", "o.......o", "oo.ooo.oo", "..ooooo..", ".ooooooo.", ".ooooooo.", "..ooooo.."] },
  upgrades: { pal: {}, rows: [
    "..oooo...", "..o..o...", "..o..o...", "..o..o...", "..o..ooo.", ".o......o", "o.......o", "ooooooooo", ".o.o.o.o."] },
  inventory: { pal: {}, rows: [
    "...ooo...", "..o...o..", ".ooooooo.", "o.......o", "o..ooo..o", "o.......o", "o.......o", "o.......o", ".ooooooo."] },
  settings: { pal: {}, rows: [
    "...o.o...", ".ooooooo.", ".o.....o.", "oo..o..oo", "o..ooo..o", "oo..o..oo", ".o.....o.", ".ooooooo.", "...o.o..."] },
};

// Doodle icons: hand-drawn crayon outlines (24x24, round ends, slightly wobbly on purpose).
// Plain ones use currentColor; coin, xp and heart are filled with their fixed colours.
const DOODLES = {
  home: `<path d="M3.8 11.6 L12 4.1 L20.3 11.2"/><path d="M6 10.2 Q5.8 15 6.3 19.6 Q12 20.4 17.8 19.4 Q18.3 14.8 18 10.1"/><path d="M10.2 19.5 L10.4 15.2 Q12.1 13.7 13.9 15.1 L13.9 19.4"/>`,
  boxes: `<path d="M4.6 10.8 Q4.4 15.5 5 19.8 Q12 20.6 19.2 19.7 Q19.7 15 19.5 10.5"/><path d="M3.4 7.4 Q12 6.8 20.5 7.1 L20.4 10.5 Q12 11 3.6 10.7 Z"/><path d="M12 7.3 L12.1 20.1"/><path d="M12 7 Q8.3 2.4 6.9 5.3 Q7.2 7.6 12 7 Q15.8 2.3 17.2 5.2 Q16.8 7.6 12 7"/>`,
  collection: `<path d="M5 9.2 L5.4 4.4 L9 7.1 Q12 6.2 15.1 7.1 L18.6 4.3 L19.1 9.1 Q20.1 15.2 16.4 18.1 Q12 20.6 7.6 18 Q3.9 15.1 5 9.2 Z"/><circle cx="9.4" cy="12.4" r="0.9" fill="currentColor"/><circle cx="14.6" cy="12.4" r="0.9" fill="currentColor"/><path d="M10.9 15.2 Q12 16.4 13.1 15.2"/>`,
  adventures: `<path d="M3.5 6.6 L9 4.4 L15 6.6 L20.6 4.5 L20.4 17.7 L15 19.6 L9 17.4 L3.7 19.5 Z"/><path d="M9 4.5 L9.1 17.3 M15 6.7 L14.9 19.4"/><path d="M5.8 15.2 Q7.8 11.5 11 12.6 Q13.9 13.4 16 9.6" stroke-dasharray="1.6 2.2"/>`,
  upgrades: `<path d="M8.1 3.7 L14 3.8 L14.2 11.9 Q19.9 12.5 20.3 16.9 L20.2 19.7 L6.8 19.8 Q5.8 15.1 7.8 12.1 Z"/><path d="M8.4 7.1 L13.7 7 M8.3 9.7 L13.8 9.6 M6.9 17.1 L20.2 17.2"/>`,
  inventory: `<path d="M8.4 8.2 Q8.5 3.7 12 3.8 Q15.5 3.8 15.6 8.1"/><path d="M4.7 8.3 Q12 7.6 19.3 8.2 L18.7 19.6 Q12 20.5 5.3 19.7 Z"/><path d="M9.5 12.5 Q12 14.1 14.5 12.4"/>`,
  lock: `<path d="M7.4 11 Q7 4.3 12 4.2 Q17 4.2 16.7 11"/><path d="M5 11.1 Q12 10.5 19 10.9 L18.7 19.8 Q12 20.5 5.3 19.9 Z"/><path d="M12 14.2 L12 16.4"/>`,
  settings: `<circle cx="12" cy="12" r="2.4"/><path d="M12 3.6 Q14.6 3.8 13.9 7.2 M12 3.6 Q9.4 3.8 10.1 7.2 M19.3 7.8 Q20.4 10.2 17.1 11.1 M19.3 7.8 Q17.7 5.7 15.3 8.3 M19.3 16.2 Q17.9 18.4 15.3 15.8 M19.3 16.2 Q20.5 13.9 17.1 12.9 M12 20.4 Q9.4 20.2 10.1 16.8 M12 20.4 Q14.6 20.2 13.9 16.8 M4.7 16.2 Q3.6 13.8 6.9 12.9 M4.7 16.2 Q6.3 18.3 8.7 15.7 M4.7 7.8 Q6.1 5.6 8.7 8.2 M4.7 7.8 Q3.5 10.1 6.9 11.1"/>`,
  coin: `<path d="M12 3 L19.6 10.4 L12 21.2 L4.4 10.4 Z" fill="var(--cyan)" stroke="var(--cyan)"/><path d="M5 10.4 L19 10.4 M9.2 10.4 L12 4.2 L14.8 10.4 L12 19.8 L9.2 10.4" stroke="var(--page)" stroke-width="1.1"/>`,
  xp: `<path d="M12 2.6 Q13.1 10 21.4 12 Q13.1 14 12 21.4 Q10.9 14 2.6 12 Q10.9 10 12 2.6 Z" fill="var(--gold)" stroke="var(--gold)"/>`,
  heart: `<path d="M12 20.1 Q3.4 13.6 4.3 8.4 Q5.4 4.2 9.3 5.1 Q11.2 5.7 12 8 Q12.9 5.6 14.8 5.1 Q18.7 4.3 19.7 8.4 Q20.6 13.5 12 20.1 Z" fill="var(--pink)" stroke="var(--pink)"/>`,
};

function doodleSvg(name, size) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${DOODLES[name]}</svg>`;
}

function iconSvg(name, scale = 2) {
  const icon = ICONS[name];
  const h = icon.rows.length, w = icon.rows[0].length;
  let rects = "";
  icon.rows.forEach((row, y) => [...row].forEach((ch, x) => {
    if (ch === ".") return;
    const fill = ch === "o" ? "currentColor" : icon.pal[ch];
    rects += `<rect x="${x}" y="${y}" width="1" height="1" fill="${fill}"/>`;
  }));
  return `<svg width="${w * scale}" height="${h * scale}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges" aria-hidden="true">${rects}</svg>`;
}

function paintIcons(root = document) {
  root.querySelectorAll("[data-icon]").forEach(el => {
    el.classList.add("icon");
    // the nearest data-icons wins, so a preview tile can show the other icon style
    const style = el.closest("[data-icons]")?.dataset.icons;
    const doodle = style === "doodle" && DOODLES[el.dataset.icon];
    el.innerHTML = doodle ? doodleSvg(el.dataset.icon, Math.round(9 * Number(el.dataset.px || 2)))
                          : iconSvg(el.dataset.icon, Number(el.dataset.px || 2));
  });
}

const PET_ART = "../assets/pets/";
const PETS = [
  { id: "lilac-blob", name: "lilac blob", tier: "rare", active: true,
    parts: { body: "blob", palette: "lilac", pattern: "plain", eyes: "sleepy", accessory: "headphones" },
    trait: "greedy", does: "earns more coins", stats: [10, 9, 5] },
  { id: "gold-dragon", name: "gold dragon", tier: "legendary", glow: true,
    parts: { body: "dragon", palette: "gold", pattern: "circuit", eyes: "sparkle", accessory: "crown" },
    trait: "brave", does: "risky things go well", stats: [16, 12, 9] },
  { id: "peach-cat", name: "peach cat", tier: "common",
    parts: { body: "cat", palette: "peach", pattern: "plain", eyes: "round", accessory: "none" },
    trait: "curious", does: "spots new places", stats: [6, 7, 8] },
  { id: "mint-bear", name: "mint bear", tier: "uncommon",
    parts: { body: "bear", palette: "mint", pattern: "spots", eyes: "happy", accessory: "leaf" },
    trait: "sturdy", does: "shrugs off bumps", stats: [11, 5, 4] },
  { id: "sky-bunny", name: "sky bunny", tier: "rare",
    parts: { body: "bunny", palette: "sky", pattern: "stripes", eyes: "round", accessory: "bow" },
    trait: "quick", does: "walks faster", stats: [5, 8, 12] },
  { id: "abyss-void", name: "abyss void", tier: "mythic", glow: true,
    parts: { body: "void", palette: "abyss", pattern: "stars", eyes: "x", accessory: "halo" },
    trait: "???", does: "it hums quietly", stats: [20, 20, 20] },
  { id: "bubblegum-fox", name: "bubblegum fox", tier: "epic",
    parts: { body: "fox", palette: "bubblegum", pattern: "stars", eyes: "sparkle", accessory: "none" },
    trait: "lucky", does: "finds more parts", stats: [9, 14, 10] },
  { id: "midnight-bear", name: "midnight bear", tier: "rare",
    parts: { body: "bear", palette: "midnight", pattern: "checker", eyes: "sleepy", accessory: "none" },
    trait: "sleepy", does: "naps between events", stats: [12, 6, 3] },
  { id: "toxic-cat", name: "toxic cat", tier: "epic",
    parts: { body: "cat", palette: "toxic", pattern: "spots", eyes: "cyclops", accessory: "horns" },
    trait: "odd", does: "strange things happen", stats: [10, 11, 9] },
  { id: "lilac-cat", name: "lilac cat", tier: "common",
    parts: { body: "cat", palette: "lilac", pattern: "stripes", eyes: "happy", accessory: "bow" },
    trait: "cheerful", does: "keeps spirits up", stats: [6, 8, 7] },
  { id: "mint-blob", name: "mint blob", tier: "common",
    parts: { body: "blob", palette: "mint", pattern: "plain", eyes: "round", accessory: "none" },
    trait: "calm", does: "never panics", stats: [7, 6, 6] },
  { id: "peach-bear", name: "peach bear", tier: "uncommon",
    parts: { body: "bear", palette: "peach", pattern: "plain", eyes: "happy", accessory: "halo" },
    trait: "kind", does: "heals friends a little", stats: [9, 7, 6] },
];

function petImg(pet, w, h) {
  return `<img class="px" src="${PET_ART}${pet.id}.png" width="${w}" height="${h}" alt="${pet.name}">`;
}

function renderDetail(el, pet) {
  el.innerHTML = `
    ${petImg(pet, 96, 108)}
    <h2>${pet.name}</h2>
    <div class="tier" style="color: var(--tier-${pet.tier})">${pet.tier}</div>
    <dl>
      ${Object.entries(pet.parts).map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("")}
      <dt>trait</dt><dd>${pet.trait}<div class="does">${pet.does}</div></dd>
      <dt>power</dt><dd>${pet.stats[0]}</dd>
      <dt>luck</dt><dd>${pet.stats[1]}</dd>
      <dt>speed</dt><dd>${pet.stats[2]}</dd>
    </dl>
    <button class="btn primary">${pet.active ? `your active pet <span data-icon="heart" data-px="1.5"></span>` : "make active"}</button>`;
  paintIcons(el);
}

function renderCollection(el) {
  el.innerHTML = `
    <div class="collection">
      <div class="coll-main">
        <div class="coll-bar">
          <div class="seg"><button class="on">pets</button><button onclick="location.href='book.html'+location.search">book</button></div>
          <div class="seg sort"><button class="on">newest</button><button>rarest</button><button>a to z</button></div>
          <span class="count">52 pets</span>
          <span class="pager"><button class="link" title="previous page">‹</button>page 1 of 3<button class="link" title="next page">›</button></span>
        </div>
        <div class="filters">${["all", "common", "uncommon", "rare", "epic", "legendary", "mythic"].map((t, i) =>
          `<button class="fchip${i === 0 ? " on" : ""}" style="--tier: ${i ? `var(--tier-${t})` : "var(--pink)"}">${t}</button>`).join("")}
          <button class="fchip fin" style="--tier: var(--gold)">sparkly</button>
        </div>
        <div class="grid">${PETS.map((p, i) => `
          <div class="pet-card${i === 0 ? " on" : ""}${p.glow ? " glow" : ""}" data-i="${i}" style="--tier: var(--tier-${p.tier})">
            ${petImg(p, 48, 54)}
            <div class="name">${p.name}</div>
            <div class="tier">${p.tier}</div>
          </div>`).join("")}
        </div>
      </div>
      <div class="detail sticker"></div>
    </div>`;
  el.querySelectorAll(".seg.sort button").forEach(b => b.addEventListener("click", () => {
    el.querySelectorAll(".seg.sort button").forEach(x => x.classList.remove("on")); b.classList.add("on");
  }));
  el.querySelectorAll(".fchip").forEach(b => b.addEventListener("click", () => b.classList.toggle("on")));
  const detail = el.querySelector(".detail");
  renderDetail(detail, PETS[0]);
  el.querySelectorAll(".pet-card").forEach(card => card.addEventListener("click", () => {
    el.querySelectorAll(".pet-card").forEach(c => c.classList.remove("on"));
    card.classList.add("on");
    renderDetail(detail, PETS[card.dataset.i]);
  }));
}

// tabs just switch the highlight in the frame mockups
function wireTabs(root = document) {
  root.querySelectorAll("[data-tab]").forEach(tab => tab.addEventListener("click", () => {
    root.querySelectorAll("[data-tab]").forEach(t => t.classList.remove("on"));
    tab.classList.add("on");
  }));
}
