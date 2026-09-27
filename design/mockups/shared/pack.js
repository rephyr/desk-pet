// Card-pack art for the mockups: a crimped foil pack with a sticker heart, drawn as SVG so it
// can become a texture in Godot. Colours come from the box, not the theme (packs are objects).

const BOXES = [
  { id: "starter", name: "starter box", price: 50, bag: 2, body: "#b98ff0", dark: "#7a58b8", light: "#e6d4ff", emblem: "#ff79c6",
    tiers: { common: "60%", uncommon: "25%", rare: "11%", epic: "3.2%", legendary: "0.70%", mythic: "0.10%" },
    finishes: { shiny: "15%", holo: "3.8%", ghost: "0.90%", glitch: "0.25%", prismatic: "0.05%" } },
  { id: "lucky", name: "lucky box", price: 250, bag: 0, body: "#ffc46b", dark: "#c98a2e", light: "#fff0c9", emblem: "#ff5f9e",
    tiers: { common: "30%", uncommon: "33%", rare: "23%", epic: "10%", legendary: "3.2%", mythic: "0.80%" },
    finishes: { shiny: "25%", holo: "10%", ghost: "3.5%", glitch: "1.2%", prismatic: "0.30%" } },
];

// width 100, height 130 in its own units; the top 20 is the strip you rip off
function packSvg(box, w = 100, opts = {}) {
  const h = w * 1.3;
  const crimp = (y, down) => {
    let d = `M4 ${y}`;
    for (let x = 4; x < 96; x += 6) d += ` L${x + 3} ${y + (down ? 4 : -4)} L${x + 6} ${y}`;
    return d;
  };
  const strip = opts.ripped ? "" : `
    <g class="strip">
      <path d="${crimp(6, true)} L96 22 L4 22 Z" fill="${box.dark}"/>
      <path d="M8 22 L92 22" stroke="${box.light}" stroke-width="2" stroke-dasharray="3 4" stroke-linecap="round"/>
    </g>`;
  return `
  <svg class="pack-art" width="${w}" height="${h}" viewBox="0 0 100 130" aria-hidden="true">
    ${strip}
    <path d="M4 24 Q3 70 5 118 L6 124 ${crimp(124, false).replace("M4 124", "L4 124")} L95 118 Q97 70 96 24 Z" fill="${box.body}" stroke="${box.dark}" stroke-width="3" stroke-linejoin="round"/>
    <path d="M18 30 L34 30 L14 104 L6 104 Z" fill="${box.light}" opacity=".35"/>
    <g transform="translate(50 72)">
      <circle r="21" fill="${box.light}" stroke="${box.dark}" stroke-width="2.5"/>
      <path d="M0 11 Q-13 2 -12 -5 Q-10 -12 -4 -10 Q-1 -9 0 -5 Q1 -9 4 -10 Q10 -12 12 -5 Q13 2 0 11 Z" fill="${box.emblem}" stroke="${box.dark}" stroke-width="1.5" stroke-linejoin="round"/>
    </g>
    <path d="M22 108 Q50 104 78 108" stroke="${box.dark}" stroke-width="2.5" fill="none" stroke-linecap="round" opacity=".6"/>
  </svg>`;
}

const TIER_ORDER = ["common", "uncommon", "rare", "epic", "legendary", "mythic"];

// who comes out, per rarity (the mockup's pick of pet for each tier)
const PULLS = {
  common: { pet: "peach-cat", name: "peach cat", finish: "", fresh: [] },
  uncommon: { pet: "mint-bear", name: "mint bear", finish: "shiny", fresh: ["leaf accessory"] },
  rare: { pet: "sky-bunny", name: "sky bunny", finish: "", fresh: ["bunny body", "stripes pattern"] },
  epic: { pet: "bubblegum-fox", name: "bubblegum fox", finish: "holo", fresh: ["fox body"] },
  legendary: { pet: "gold-dragon", name: "gold dragon", finish: "holo", fresh: ["dragon body", "gold palette", "crown"] },
  mythic: { pet: "abyss-void", name: "abyss void", finish: "ghost", fresh: ["void body", "abyss palette", "halo"] },
};
