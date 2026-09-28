// Capsule toys for the mockups: the first set ("backyard friends"), each toy a little doodled
// figurine on a stand. toySvg(id, finish, size) draws one; finishes: normal, holo, foil, ghost.

const TOY_SET = {
  id: "backyard", name: "backyard friends", bonus: "+1 coin in every capsule, forever",
  toys: [
    { id: "snail", name: "snail", tier: "common", does: "capsules pop open sooner", per: "-0.05 s a level" },
    { id: "ladybug", name: "ladybug", tier: "common", does: "the lucky lights fill faster", per: "1 light a level" },
    { id: "mushroom", name: "mushroom", tier: "common", does: "more xp in capsules", per: "+10% a level" },
    { id: "acorn", name: "acorn", tier: "common", does: "+1 coin in every capsule", per: "+1 a level" },
    { id: "bee", name: "bumble bee", tier: "uncommon", does: "fever lasts longer", per: "+2 s a level" },
    { id: "frog", name: "frog", tier: "uncommon", does: "toys come out more often", per: "+8% a level" },
    { id: "gnome", name: "garden gnome", tier: "rare", does: "adventures bring home more coins", per: "+10% a level" },
    { id: "moth", name: "moon moth", tier: "secret", does: "golden capsules come more often", per: "+15% a level" },
  ],
};

const TOY_TIERS = { common: "var(--tier-common)", uncommon: "var(--tier-uncommon)", rare: "var(--tier-rare)", secret: "var(--tier-mythic)" };
const TOY_FINISHES = {
  normal: { name: "normal" },
  holo: { name: "holo" },
  foil: { name: "gold foil" },
  ghost: { name: "ghost" },
};

// the toys themselves, on a 48 grid (the stand is drawn under them)
const TOY_ART = {
  snail: `<path d="M8 36 Q8 30 16 30 L34 30 Q40 30 40 36 Z" fill="var(--mint)" stroke="var(--deep)" stroke-width="2"/>
    <circle cx="25" cy="23" r="10" fill="var(--pink)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M25 23 m0 -5 a5 5 0 1 1 -5 5 a3 3 0 1 1 3 -3" fill="none" stroke="var(--deep)" stroke-width="1.8" stroke-linecap="round"/>
    <path d="M11 30 L9 21 M14 30 L14 21" stroke="var(--deep)" stroke-width="1.8" stroke-linecap="round"/><circle cx="9" cy="20" r="1.8" fill="var(--deep)"/><circle cx="14" cy="20" r="1.8" fill="var(--deep)"/>`,
  ladybug: `<path d="M10 34 Q10 16 24 16 Q38 16 38 34 Z" fill="var(--pink)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M24 16 L24 34" stroke="var(--deep)" stroke-width="2"/>
    <circle cx="17" cy="24" r="2.6" fill="var(--deep)"/><circle cx="31" cy="24" r="2.6" fill="var(--deep)"/><circle cx="18" cy="30" r="2" fill="var(--deep)"/><circle cx="30" cy="30" r="2" fill="var(--deep)"/>
    <path d="M17 17 Q24 9 31 17 Z" fill="var(--deep)"/><circle cx="21" cy="14" r="1.2" fill="var(--text)"/><circle cx="27" cy="14" r="1.2" fill="var(--text)"/>`,
  mushroom: `<path d="M20 26 L19 36 L29 36 L28 26 Z" fill="var(--text)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M8 27 Q8 11 24 11 Q40 11 40 27 Z" fill="var(--lilac)" stroke="var(--deep)" stroke-width="2"/>
    <circle cx="17" cy="19" r="2.6" fill="var(--text)"/><circle cx="29" cy="17" r="3" fill="var(--text)"/><circle cx="24" cy="23" r="1.8" fill="var(--text)"/>`,
  acorn: `<path d="M15 22 Q15 37 24 37 Q33 37 33 22 Z" fill="var(--gold)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M12 22 Q12 13 24 13 Q36 13 36 22 Z" fill="color-mix(in srgb, var(--gold) 45%, var(--deep))" stroke="var(--deep)" stroke-width="2"/>
    <path d="M24 13 L25 8" stroke="var(--deep)" stroke-width="2.2" stroke-linecap="round"/>
    <path d="M16 18 L32 18" stroke="var(--deep)" stroke-width="1.2" opacity=".5"/>`,
  bee: `<path d="M15 14 Q9 6 16 7 Q21 9 20 16" fill="var(--text)" stroke="var(--deep)" stroke-width="1.8" opacity=".9"/><path d="M29 14 Q35 6 30 6 Q25 8 26 16" fill="var(--text)" stroke="var(--deep)" stroke-width="1.8" opacity=".9"/>
    <ellipse cx="23" cy="25" rx="12" ry="10" fill="var(--gold)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M18 16 Q16 25 18 34 M25 15 Q23 25 25 35" stroke="var(--deep)" stroke-width="3.2" fill="none"/>
    <circle cx="31" cy="23" r="1.6" fill="var(--deep)"/><path d="M11 25 L7 26" stroke="var(--deep)" stroke-width="2" stroke-linecap="round"/>`,
  frog: `<path d="M9 34 Q7 20 24 20 Q41 20 39 34 Z" fill="var(--mint)" stroke="var(--deep)" stroke-width="2"/>
    <circle cx="16" cy="18" r="6" fill="var(--mint)" stroke="var(--deep)" stroke-width="2"/><circle cx="32" cy="18" r="6" fill="var(--mint)" stroke="var(--deep)" stroke-width="2"/>
    <circle cx="16" cy="18" r="2.4" fill="var(--deep)"/><circle cx="32" cy="18" r="2.4" fill="var(--deep)"/>
    <path d="M17 28 Q24 32 31 28" stroke="var(--deep)" stroke-width="2" fill="none" stroke-linecap="round"/><circle cx="13" cy="28" r="1.6" fill="var(--pink)"/><circle cx="35" cy="28" r="1.6" fill="var(--pink)"/>`,
  gnome: `<path d="M14 36 Q13 27 24 27 Q35 27 34 36 Z" fill="var(--cyan)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M16 28 Q17 38 24 38 Q31 38 32 28 Q24 33 16 28 Z" fill="var(--text)" stroke="var(--deep)" stroke-width="1.8"/>
    <circle cx="24" cy="24" r="6" fill="#f3c4b4" stroke="var(--deep)" stroke-width="2"/><circle cx="24" cy="26" r="2" fill="var(--pink)"/>
    <path d="M15 22 Q20 4 27 3 Q27 12 34 22 Z" fill="var(--pink)" stroke="var(--deep)" stroke-width="2" stroke-linejoin="round"/>`,
  moth: `<path d="M24 22 Q10 6 6 14 Q4 24 22 26 Z" fill="var(--lilac)" stroke="var(--deep)" stroke-width="2"/><path d="M24 22 Q38 6 42 14 Q44 24 26 26 Z" fill="var(--lilac)" stroke="var(--deep)" stroke-width="2"/>
    <path d="M22 27 Q12 30 12 36 Q18 37 23 30 Z" fill="color-mix(in srgb, var(--lilac) 60%, var(--deep))" stroke="var(--deep)" stroke-width="1.8"/><path d="M26 27 Q36 30 36 36 Q30 37 25 30 Z" fill="color-mix(in srgb, var(--lilac) 60%, var(--deep))" stroke="var(--deep)" stroke-width="1.8"/>
    <ellipse cx="24" cy="26" rx="3" ry="8" fill="var(--text)" stroke="var(--deep)" stroke-width="1.8"/>
    <path d="M14 13 Q10 17 14 20 Q11 16 14 13 Z" fill="var(--gold)"/><path d="M34 13 Q38 17 34 20 Q37 16 34 13 Z" fill="var(--gold)"/>
    <path d="M22 18 Q19 11 17 10 M26 18 Q29 11 31 10" stroke="var(--deep)" stroke-width="1.6" fill="none" stroke-linecap="round"/>`,
};

let _toyUid = 0;
// one toy on its little plastic stand; finish changes the look; missing = a silhouette
// style "vinyl" adds soft shading, like a glossy vinyl figure
function toySvg(id, finish = "normal", size = 64, missing = false, style = "doodle") {
  const u = "t" + (_toyUid++);
  const art = TOY_ART[id];
  const defs = `<defs>
    <linearGradient id="${u}holo" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ff79c6"/><stop offset=".25" stop-color="#ffe08a"/><stop offset=".5" stop-color="#8fe8c0"/><stop offset=".75" stop-color="#8be9fd"/><stop offset="1" stop-color="#c9a0ff"/>
      <animateTransform attributeName="gradientTransform" type="translate" values="-1 0; 1 0; -1 0" dur="4s" repeatCount="indefinite"/>
    </linearGradient>
    <linearGradient id="${u}foil" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#8a6a1f"/><stop offset=".35" stop-color="#ffe08a"/><stop offset=".5" stop-color="#fff6d6"/><stop offset=".65" stop-color="#ffe08a"/><stop offset="1" stop-color="#8a6a1f"/>
      <animateTransform attributeName="gradientTransform" type="translate" values="-.6 0; .6 0; -.6 0" dur="3s" repeatCount="indefinite"/>
    </linearGradient>
    <radialGradient id="${u}shine" cx=".3" cy=".22" r=".6"><stop offset="0" stop-color="#fff" stop-opacity=".6"/><stop offset=".5" stop-color="#fff" stop-opacity=".08"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
    <linearGradient id="${u}shade" x1="0" y1="0" x2="0" y2="1"><stop offset=".45" stop-color="#120a19" stop-opacity="0"/><stop offset="1" stop-color="#120a19" stop-opacity=".45"/></linearGradient>
    <mask id="${u}m"><g fill="#fff" stroke="#fff">${art.replace(/fill="[^"]*"/g, 'fill="#fff"').replace(/stroke="[^"]*"/g, 'stroke="#fff"')}</g></mask>
  </defs>`;
  const stand = `<ellipse cx="24" cy="41" rx="13" ry="3.6" fill="color-mix(in srgb, var(--text) 18%, var(--page))" stroke="var(--deep)" stroke-width="1.6"/><path d="M11 41 L11 43 Q24 48 37 43 L37 41" fill="color-mix(in srgb, var(--text) 10%, var(--page))" stroke="var(--deep)" stroke-width="1.6"/>`;
  let body;
  if (missing) {
    body = `<g opacity=".9"><g mask="url(#${u}m)"><rect width="48" height="48" fill="var(--line)"/></g></g>`;
  } else if (finish === "holo") {
    body = `${art}<g mask="url(#${u}m)" style="mix-blend-mode: screen"><rect width="48" height="48" fill="url(#${u}holo)" opacity=".55"/></g>`;
  } else if (finish === "foil") {
    body = `${art}<g mask="url(#${u}m)" style="mix-blend-mode: overlay"><rect width="48" height="48" fill="url(#${u}foil)" opacity=".95"/></g><g mask="url(#${u}m)"><rect width="48" height="48" fill="url(#${u}foil)" opacity=".35"/></g>`;
  } else if (finish === "ghost") {
    body = `<g opacity=".5" style="filter: drop-shadow(0 0 3px var(--cyan))">${art}</g>`;
  } else {
    body = art;
  }
  if (style === "vinyl" && !missing) {
    body += `<g mask="url(#${u}m)"><rect width="48" height="48" fill="url(#${u}shade)"/><rect width="48" height="48" fill="url(#${u}shine)"/></g>`;
  }
  return `<svg width="${size}" height="${size}" viewBox="0 0 48 48" aria-hidden="true" style="overflow: visible">${defs}${stand}${body}</svg>`;
}
