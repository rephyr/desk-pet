#!/usr/bin/env python3
"""Every sound of the capsule machine: the lever, the capsule, the lucky lights and the prizes.

Pulling the lever is the thing you do hundreds of times, so the sounds you hear on every pull are
short, soft at the top (nothing much above 7 kHz) and dry, and the musical ones are in F major at
100 bpm like the pack sounds, so they sit with the room music.

The mechanical ones are made with numpy (damped sine pings, shaped noise bursts, thumps whose
pitch drops, a few early reflections for a small room); the musical ones are General MIDI sounds
from FluidR3, written as LMMS projects and rendered with lmms:

    tick        one ratchet notch: a tiny plastic "tk" (a pawl hitting a tooth and a softer
                catch 4 ms later); dry and pitch-neutral, the game plays it higher per notch
    clunk       the lever hitting the bottom: a low thump dropping from 170 to 80 Hz, a hollow
                plastic body (320/520/780 Hz), a metal latch click and its catch 28 ms later,
                a tiny rebound; warmed with a soft saturation
    spring      the lever going back up: a cartoon boing, a tone wobbling at 16 Hz that settles
    rattle      capsules jostling in the globe: a dozen random plastic-on-plastic taps and a
                few softer, ringier taps on glass, thinning out, spread in stereo
    plonk       the capsule dropping out: a hollow ball hitting the floor and bouncing (0, 170,
                285 ms and a tiny roll), each hit a floor thump and a hollow "plonk" ring
    pop         the capsule popping open: a pitch-dropping "pok" with a puff, then a small
                celesta sparkle (C7, F7)
    coin        a coin clinking on another: two inharmonic metal pings on F6 and C7
    light       a lucky light turning on: a celesta and vibraphone F5 (the game pitches it up)
    prize       a nice prize: music box and celesta running C F A C up into an F chord
    jackpot     the golden capsule: trumpet ta-ta-TAAA over brass, strings and timpani, with a
                glockenspiel run, a triangle and a soft cymbal
    fever       all lucky lights lit: a harp glissando F4 to F7 over a shaker swell, into a bright
                F chord (strings, brass, celesta, glockenspiel, triangle)
    fever_loop  4 bars (9.6 s) that loop seamlessly while fever lasts: marimba oom-pah, pizzicato
                bass, a music-box tune and a soft shaker (chords F F Bb F, like the pack loop;
                the tune stays on F major pentatonic plus Bb so it doesn't fight the room music)

    python3 tools/music/machine_sounds.py            writes assets/sounds/machine/*.ogg and previews
    python3 tools/music/machine_sounds.py --preview  only remixes the previews

The LMMS projects land in tools/music/machine/ (running this again writes over them). Previews of
a whole pull (machine_pull), a prize pull then a golden one (machine_jackpot), and ten lights
into fever (machine_fever) land in assets/sounds/_preview/ (Godot ignores that folder).

Loudness is integrated LUFS, measured on the sound padded with silence to 0.5 s (ffmpeg can't
measure anything shorter than its 400 ms block), so a short tick at -30 is as loud as that much
energy spread over half a second.
"""
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lmms import BAR, BEAT, RATE, Track, db, drum, limit, loudness, project, read, render, render_tracks, trim_tail, write_ogg  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent / "machine"
OUT = ROOT / "assets" / "sounds" / "machine"
PREVIEW = ROOT / "assets" / "sounds" / "_preview"
WORK = SRC / "_work"

BPM = 100
LOOP_BARS = 4
LOOP_FRAMES = round(LOOP_BARS * 4 * 60.0 / BPM * RATE)
E = BEAT // 2  # an eighth
S = BEAT // 4  # a sixteenth
T = BEAT // 3  # an eighth-note triplet

LOUDNESS = {"tick": -30.0, "clunk": -20.0, "spring": -28.0, "rattle": -29.0, "plonk": -24.0, "pop": -22.0,
            "coin": -24.0, "light": -26.0, "prize": -21.0, "jackpot": -16.0, "fever": -18.0, "fever_loop": -26.0}


# ---- small synth helpers (mono float arrays) ---------------------------------------

def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * RATE), dtype=np.float64)


def times(n: int) -> np.ndarray:
    return np.arange(n) / RATE


def ping(freq: float, decay: float, seconds: float, amp: float = 1.0, drop: float = 0.0) -> np.ndarray:
    """A damped sine (a struck resonance). `drop` bends the pitch down by that fraction as it rings."""
    t = times(int(seconds * RATE))
    f = freq * (1.0 - drop * (1.0 - np.exp(-t / max(decay, 1e-4))))
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / decay)


def sweep(f0: float, f1: float, glide: float, decay: float, seconds: float, amp: float = 1.0) -> np.ndarray:
    """A sine whose pitch falls from f0 towards f1 (a thump or a pok)."""
    t = times(int(seconds * RATE))
    f = f1 + (f0 - f1) * np.exp(-t / glide)
    env = np.exp(-t / decay) * np.minimum(1.0, t / 0.0006 + 0.05)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * env


def shape(a: np.ndarray, lo: float = 0.0, hi: float = 0.0, order: int = 2) -> np.ndarray:
    """Gentle zero-phase high/low cut (Butterworth-shaped magnitude, done with an FFT)."""
    n = len(a)
    size = 1 << int(np.ceil(np.log2(n + 4096)))
    spec = np.fft.rfft(a, size)
    f = np.maximum(np.fft.rfftfreq(size, 1.0 / RATE), 1e-3)
    gain = np.ones_like(f)
    if lo:
        gain /= np.sqrt(1.0 + (lo / f) ** (2 * order))
    if hi:
        gain /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    return np.fft.irfft(spec * gain, size)[:n]


def burst(seconds: float, decay: float, lo: float, hi: float, amp: float, seed: int) -> np.ndarray:
    """A noise burst shaped to a band, dying away."""
    rng = np.random.default_rng(seed)
    n = int(seconds * RATE)
    return amp * shape(rng.normal(size=n), lo, hi) * np.exp(-times(n) / decay) / 0.35


def place(mix: np.ndarray, a: np.ndarray, at: float) -> np.ndarray:
    i = int(at * RATE)
    if i + len(a) > len(mix):
        mix = np.concatenate([mix, np.zeros((i + len(a) - len(mix),) + mix.shape[1:], dtype=mix.dtype)])
    mix[i:i + len(a)] += a
    return mix


def room(a: np.ndarray, amount: float = 0.25) -> np.ndarray:
    """A few darkened early reflections: sounds like a small room, no long tail."""
    wet = np.zeros(len(a) + int(0.05 * RATE))
    for ms, g in [(6.7, 0.55), (11.3, 0.4), (17.9, 0.32), (23.1, 0.22), (31.7, 0.16), (41.3, 0.1)]:
        i = int(ms / 1000 * RATE)
        wet[i:i + len(a)] += g * a
    wet = shape(wet, 120, 3500)
    out = np.zeros_like(wet)
    out[:len(a)] = a
    return out + amount * wet


def stereo(a: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """Mono to stereo, pan -1..1 (equal power)."""
    ang = (pan + 1.0) * np.pi / 4
    return np.stack([a * np.cos(ang), a * np.sin(ang)], axis=1) * np.sqrt(2)


# ---- tidying up ---------------------------------------------------------------------

def trim_head(a: np.ndarray, floor_db: float = -40.0) -> np.ndarray:
    """Cuts everything before the attack (relative to the peak), so the sound starts on the frame
    the game plays it."""
    level = np.max(np.abs(a), axis=1)
    start = int(np.argmax(level > level.max() * db(floor_db)))
    start = max(0, start - 16)
    a = a[start:].copy()
    a[:16] *= np.linspace(0.0, 1.0, 16)[:, None]
    return a


def cut(a: np.ndarray, seconds: float, fade: float) -> np.ndarray:
    """Keeps at most `seconds`, fading the last `fade` out."""
    n = min(len(a), int(seconds * RATE))
    a = a[:n].copy()
    f = min(n, int(fade * RATE))
    a[n - f:] *= (np.linspace(1.0, 0.0, f) ** 2)[:, None]
    return a


def measure(a: np.ndarray) -> float:
    pad = max(0, int(0.5 * RATE) - len(a))
    return loudness(np.concatenate([a, np.zeros((pad, 2))]) if pad else a, WORK)


def finish_shot(name: str, a: np.ndarray) -> np.ndarray:
    a = trim_tail(trim_head(a), floor_db=-60.0, fade=0.03)
    a = limit(a * db(LOUDNESS[name] - measure(a)))
    write_ogg(OUT / f"{name}.ogg", a, WORK)
    return a


def lmms(name: str, tracks: list, bars: int) -> np.ndarray:
    """Renders the tracks as one LMMS project (kept in tools/music/machine/), attack trimmed."""
    mmp = SRC / f"{name}.mmp"
    mmp.write_text(project(tracks, BPM, bars))
    wav = WORK / f"{name}.wav"
    render(mmp, wav)
    return trim_head(read(wav).astype(np.float64), -50.0)


# ---- the mechanical sounds (numpy) ----------------------------------------------------

def tick() -> np.ndarray:
    def notch(amp: float, seed: int) -> np.ndarray:
        a = burst(0.05, 0.0025, 900, 6000, 0.5, seed)
        a += ping(1850, 0.006, 0.05, 0.5) + ping(3100, 0.004, 0.05, 0.25) + ping(950, 0.009, 0.05, 0.35)
        return amp * a
    a = place(silence(0.06), notch(1.0, 1), 0.0)
    a = place(a, notch(0.3, 2), 0.004)
    a = shape(a, 300, 7000)
    return stereo(a)


def clunk() -> np.ndarray:
    n = 0.4
    a = sweep(170, 80, 0.03, 0.08, n, 0.9)                        # the thump
    a += ping(320, 0.06, n, 0.55) + ping(520, 0.04, n, 0.35) + ping(780, 0.025, n, 0.15)  # the body
    a += burst(n, 0.012, 150, 2500, 0.45, 3)                         # the knock itself
    latch = ping(2700, 0.010, 0.08, 0.18) + ping(3900, 0.007, 0.08, 0.10) + ping(5200, 0.005, 0.08, 0.05)
    latch += burst(0.08, 0.002, 2000, 7000, 0.12, 4)
    a = place(a, latch, 0.0)
    a = place(a, 0.6 * latch, 0.028)                                  # the latch catching
    a = place(a, sweep(120, 80, 0.02, 0.03, 0.12, 0.15), 0.07)        # a tiny rebound
    a = np.tanh(1.6 * a) / np.tanh(1.6)
    a = shape(room(a, 0.3), 30, 7500)
    return stereo(a)


def spring() -> np.ndarray:
    n = 0.34
    t = times(int(n * RATE))
    f = 250 * (1.0 + 0.06 * t / n) * (1.0 + 0.22 * np.sin(2 * np.pi * 16 * t) * np.exp(-t / 0.1))
    ph = 2 * np.pi * np.cumsum(f) / RATE
    tone = np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph) + 0.05 * np.sin(4.6 * ph)  # coil: a bit off
    env = np.minimum(1.0, t / 0.004) * np.exp(-t / 0.1)
    a = tone * env + burst(n, 0.004, 600, 4000, 0.15, 5)
    a = shape(a, 120, 5000)
    return stereo(a)


def rattle() -> np.ndarray:
    rng = np.random.default_rng(11)
    mix = np.zeros((int(0.5 * RATE), 2))
    hits = np.sort(np.concatenate([[0.0, 0.018], 0.38 * rng.random(12) ** 1.5]))
    for i, at in enumerate(hits):
        amp = np.exp(-at / 0.16) * rng.uniform(0.45, 1.0)
        f = rng.uniform(1600, 2600)
        if rng.random() < 0.3:  # a ball against the glass: higher, ringier, softer
            hit = ping(rng.uniform(3200, 4200), 0.022, 0.06, 0.3) + ping(f * 0.6, 0.01, 0.06, 0.2)
        else:  # plastic on plastic: short and hollow
            hit = ping(f, 0.005, 0.06, 0.6) + ping(f * 0.43, 0.008, 0.06, 0.4)
        hit += burst(0.06, 0.0015, 1000, 6000, 0.35, 100 + i)
        mix = place(mix, stereo(amp * shape(hit, 400, 7000), rng.uniform(-0.5, 0.5)), at)
    return mix


def plonk() -> np.ndarray:
    def bounce(amp: float, pitch: float, seed: int) -> np.ndarray:
        a = sweep(210 * pitch, 120 * pitch, 0.012, 0.035, 0.2, 0.9)              # the floor
        a += ping(620 * pitch, 0.03, 0.2, 0.5, drop=0.05)                         # the hollow ball
        a += ping(1450 * pitch, 0.015, 0.2, 0.22, drop=0.04)
        a += burst(0.2, 0.002, 500, 5000, 0.25, seed)
        return amp * a
    a = silence(0.5)
    for at, amp, pitch, seed in [(0.0, 1.0, 1.0, 6), (0.17, 0.55, 1.03, 7), (0.285, 0.3, 1.05, 8), (0.345, 0.12, 1.07, 9)]:
        a = place(a, bounce(amp, pitch, seed), at)
    a = shape(room(a, 0.22), 60, 7000)
    return stereo(a)


def pok() -> np.ndarray:
    a = sweep(1600, 650, 0.008, 0.025, 0.12, 0.9)
    a += 0.2 * sweep(3200, 1300, 0.008, 0.012, 0.12, 1.0)
    a += burst(0.12, 0.004, 600, 5000, 0.3, 10)
    a += sweep(260, 160, 0.01, 0.015, 0.12, 0.35)   # the puff of air
    return shape(a, 120, 7500)


def coin() -> np.ndarray:
    def clink(f: float, amp: float, seed: int) -> np.ndarray:
        a = ping(f, 0.09, 0.22, 1.0) + ping(f * 2.32, 0.04, 0.22, 0.35) + ping(f * 3.87, 0.02, 0.22, 0.12)
        return amp * (a + burst(0.22, 0.001, 2000, 7000, 0.15, seed))
    a = place(silence(0.24), clink(1396.9, 1.0, 12), 0.0)   # F6
    a = place(a, clink(2093.0, 0.55, 13), 0.055)            # C7
    a = shape(a, 400, 7000)
    return stereo(a)


# ---- the musical sounds (LMMS) --------------------------------------------------------

def sparkle_tracks() -> list:
    celesta = Track("celesta", 8, vol=60, reverb=0.5)
    celesta.add("C7", 0, BEAT, 70).add("F7", 3, BEAT, 80)
    return [celesta]


def light_tracks() -> list:
    celesta = Track("celesta", 8, vol=78, reverb=0.3)
    vibes = Track("vibraphone", 11, vol=46, reverb=0.3)
    celesta.add("F5", 0, BEAT, 90)
    vibes.add("F5", 0, E, 80)
    return [celesta, vibes]


def prize_tracks() -> list:
    box = Track("music box", 10, vol=76, reverb=0.5)
    celesta = Track("celesta", 8, vol=56, reverb=0.5, pan=-15)
    pizz = Track("pizz", 45, vol=60, reverb=0.3)
    step = T // 2 + 1  # 9 ticks, about 110 ms
    for i, (hi, lo) in enumerate([("C6", "C5"), ("F6", "F5"), ("A6", "A5")]):
        box.add(hi, i * step, step, 72 + i * 6)
        celesta.add(lo, i * step, step, 64 + i * 4)
    land = 3 * step
    box.add("C7", land, BEAT, 92)
    celesta.add("F5 A5 C6", land, BEAT, 70)
    pizz.add("F3", land, E, 88)
    return [box, celesta, pizz]


def jackpot_tracks() -> list:
    trumpet = Track("trumpet", 56, vol=66, reverb=0.5)
    brass = Track("brass", 61, vol=58, reverb=0.5)
    strings = Track("strings", 48, vol=56, reverb=0.5)
    timpani = Track("timpani", 47, vol=68, reverb=0.4)
    glock = Track("glock", 9, vol=52, reverb=0.6, pan=25)
    box = Track("music box", 10, vol=50, reverb=0.5, pan=-25)
    kit = Track("kit", 48, vol=52, bank=128, reverb=0.5)  # orchestra kit
    trumpet.add("C5", 0, T - 3, 84).add("C5", T, T - 3, 84)
    timpani.add("C2", 0, T, 60).add("C2", T, T, 66)
    land = 2 * T
    trumpet.add("F5", land, E, 94).add("A5", land + E, E, 90).add("C6", land + BEAT, 2 * BEAT, 100)
    brass.add("F3 C4 F4 A4", land, BEAT, 86).add("F3 C4 F4 A4 C5", land + BEAT, 2 * BEAT, 92)
    strings.add("F2 F3 C4 A4", land, 3 * BEAT, 80)
    timpani.add("F2", land, E, 100).add("C2", land + E + S, S, 70).add("F2", land + BEAT, BEAT, 96)
    for i, n in enumerate(["F6", "A6", "C7", "F7", "C7", "A6", "C7", "F7"]):
        glock.add(n, land + i * S, S * 2, 64 + (i == 3) * 16 + (i == 7) * 16)
    for i, n in enumerate(["C6", "F6", "A6", "C7"]):
        box.add(n, land + BEAT + i * S, S * 2, 70)
    kit.add(drum(81), land, 2 * BEAT, 76)       # open triangle
    kit.add(drum(49), land + BEAT, 2 * BEAT, 52)  # a soft crash
    return [trumpet, brass, strings, timpani, glock, box, kit]


def fever_tracks() -> list:
    harp = Track("harp", 46, vol=66, reverb=0.5)
    strings = Track("strings", 48, vol=58, reverb=0.5)
    brass = Track("brass", 61, vol=46, reverb=0.5)
    celesta = Track("celesta", 8, vol=62, reverb=0.6, pan=-20)
    glock = Track("glock", 9, vol=50, reverb=0.6, pan=20)
    kit = Track("kit", 0, vol=48, bank=128, reverb=0.4)
    gliss = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5", "G5", "A5", "Bb5", "C6", "D6", "E6", "F6",
             "G6", "A6", "Bb6", "C7", "D7", "E7", "F7"]
    for i, n in enumerate(gliss):
        harp.add(n, i * 2, BEAT, 56 + i * 2)
    for i in range(11):
        kit.add(drum(82), i * 4, 4, 30 + i * 5)  # shaker swelling
    land = len(gliss) * 2
    strings.add("F3 C4 F4 A4 C5", land, 3 * BEAT, 86)
    brass.add("F4 A4 C5", land, 2 * BEAT, 76)
    celesta.add("F5 A5 C6 F6", land, BEAT, 84)
    for i, n in enumerate(["F6", "A6", "C7", "F7"]):
        glock.add(n, land + i * S // 2, BEAT, 70 + i * 4)
    kit.add(drum(81), land, 2 * BEAT, 80)
    harp.add("F3 C4 F4", land, BEAT, 84)
    return [harp, strings, brass, celesta, glock, kit]


def fever_loop_tracks() -> list:
    marimba = Track("fl-marimba", 12, vol=64, reverb=0.3)
    pizz = Track("fl-pizz", 45, vol=62, reverb=0.3)
    box = Track("fl-box", 10, vol=58, reverb=0.45, pan=15)
    kit = Track("fl-shaker", 0, vol=40, bank=128, reverb=0.2, pan=-20)
    # (marimba root, marimba fifth, marimba dyad, pizzicato on 1, pizzicato on 3)
    chords = [("F3", "C4", "A4 C5", "F2", "C3"), ("F3", "C4", "A4 C5", "F2", "C3"),
              ("Bb2", "F3", "Bb4 D5", "Bb2", "F2"), ("F3", "C4", "A4 C5", "F2", "C3")]
    tune = [["C6", None, "A5", "C6", "D6", None, "C6", "A5"],
            ["F6", None, "D6", "C6", "A5", None, "G5", "A5"],
            ["D6", None, "Bb5", "D6", "F6", None, "D6", "C6"],
            ["A5", "C6", "A5", "G5", "F5", None, None, None]]
    for rep in range(3):
        for bar in range(LOOP_BARS):
            at = (rep * LOOP_BARS + bar) * BAR
            root, fifth, dyad, low, low5 = chords[bar]
            for i in range(8):  # oom-pah in eighths
                pos = at + i * E
                if i % 2 == 0:
                    marimba.add(root if i % 4 == 0 else fifth, pos, E, 80 if i == 0 else 70)
                else:
                    marimba.add(dyad, pos, S, 60)
            pizz.add(low, at, E, 84).add(low5, at + 2 * BEAT, E, 70)
            for i, n in enumerate(tune[bar]):
                if n:
                    box.add(n, at + i * E, E, 74 if i % 2 == 0 else 64)
            for i in range(16):  # shaker sixteenths, pushing the off-beats
                kit.add(drum(82), at + i * S, S, 64 if i % 4 == 2 else (44 if i % 2 else 34))
    return [marimba, pizz, box, kit]


# ---- making the files -------------------------------------------------------------

def make_fever_loop() -> np.ndarray:
    tracks = fever_loop_tracks()
    (SRC / "fever_loop.mmp").write_text(project(tracks, BPM, LOOP_BARS * 3))
    stems = render_tracks(tracks, BPM, LOOP_BARS * 3, WORK / "fever_loop")
    a = np.zeros((LOOP_FRAMES, 2))
    for path in stems.values():
        middle = read(path)[LOOP_FRAMES:2 * LOOP_FRAMES]
        a[:len(middle)] += middle
    a = limit(a * db(LOUDNESS["fever_loop"] - loudness(np.tile(a, (2, 1)), WORK)))
    write_ogg(OUT / "fever_loop.ogg", a, WORK)
    return a


def make_all() -> dict:
    jobs = {"sparkle": (sparkle_tracks, 1), "light": (light_tracks, 1), "prize": (prize_tracks, 1),
            "jackpot": (jackpot_tracks, 2), "fever": (fever_tracks, 2)}
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {name: pool.submit(lmms, name, fn(), bars) for name, (fn, bars) in jobs.items()}
        loop = pool.submit(make_fever_loop)
        rendered = {name: f.result() for name, f in futures.items()}
        loop.result()

    out = {}
    out["tick"] = finish_shot("tick", tick())
    out["clunk"] = finish_shot("clunk", clunk())
    out["spring"] = finish_shot("spring", spring())
    out["rattle"] = finish_shot("rattle", rattle())
    out["plonk"] = finish_shot("plonk", plonk())
    sparkle = cut(rendered["sparkle"], 0.3, 0.15)
    p = place(np.zeros((int(0.35 * RATE), 2)), stereo(pok()), 0.0)
    p = place(p, db(-9) * sparkle / np.max(np.abs(sparkle)), 0.035)
    out["pop"] = finish_shot("pop", cut(p, 0.34, 0.12))
    out["coin"] = finish_shot("coin", coin())
    out["light"] = finish_shot("light", cut(rendered["light"], 0.4, 0.2))
    out["prize"] = finish_shot("prize", cut(rendered["prize"], 0.95, 0.4))
    out["jackpot"] = finish_shot("jackpot", cut(rendered["jackpot"], 2.2, 0.6))
    out["fever"] = finish_shot("fever", cut(rendered["fever"], 1.6, 0.5))
    return out


# ---- previews -------------------------------------------------------------------

def decode(path: Path) -> np.ndarray:
    tmp = WORK / (path.stem + ".dec.wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-ar", str(RATE), "-ac", "2", str(tmp)], check=True)
    a = read(tmp).astype(np.float64)
    tmp.unlink()
    return a


def pitched(a: np.ndarray, ratio: float) -> np.ndarray:
    """Plays faster and higher, like AudioStreamPlayer.pitch_scale."""
    n = int(len(a) / ratio)
    x = np.arange(n) * ratio
    return np.stack([np.interp(x, np.arange(len(a)), a[:, c]) for c in range(2)], axis=1)


def pull(mix: np.ndarray, at: float, s: dict, prize: str) -> tuple:
    """One pull from `at`: six ticks rising, clunk, rattle, spring, plonk, pop, then the prize."""
    for i in range(6):
        mix = place(mix, pitched(s["tick"], 1.0 + 0.07 * i), at + i * 0.06)
    t = at + 6 * 0.06
    mix = place(mix, s["clunk"], t)
    mix = place(mix, s["rattle"], t + 0.06)
    mix = place(mix, s["spring"], t + 0.18)
    t += 0.25
    mix = place(mix, s["plonk"], t)
    t += 0.4
    mix = place(mix, s["pop"], t)
    mix = place(mix, s[prize], t + 0.12)
    return mix, t + 0.12 + len(s[prize]) / RATE


def previews() -> None:
    names = list(LOUDNESS)
    s = {n: decode(OUT / f"{n}.ogg") for n in names}
    PREVIEW.mkdir(parents=True, exist_ok=True)
    (PREVIEW / ".gdignore").touch()

    mix, end = pull(np.zeros((RATE, 2)), 0.1, s, "coin")
    mix, end = pull(mix, end + 0.5, s, "coin")
    write_ogg(PREVIEW / "machine_pull.ogg", limit(cut(mix, end + 0.3, 0.05), -0.5), WORK)
    print(f"  preview machine_pull    {end + 0.3:4.1f} s")

    mix, end = pull(np.zeros((RATE, 2)), 0.1, s, "prize")
    mix, end = pull(mix, end + 0.6, s, "jackpot")
    write_ogg(PREVIEW / "machine_jackpot.ogg", limit(cut(mix, end + 0.3, 0.05), -0.5), WORK)
    print(f"  preview machine_jackpot {end + 0.3:4.1f} s")

    # ten lights coming on up the scale (a light per pull, sped up), fever, then pulls over the loop
    mix = np.zeros((RATE, 2))
    scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
    for i, semis in enumerate(scale):
        mix = place(mix, pitched(s["light"], 2 ** (semis / 12)), 0.1 + i * 0.25)
    t = 0.1 + 10 * 0.25 + 0.1
    mix = place(mix, s["fever"], t)
    loop_at = t + 1.0
    mix = place(mix, s["fever_loop"], loop_at)
    end = t
    for k in range(4):
        mix, end = pull(mix, loop_at + 0.3 + k * 2.3, s, "coin" if k % 2 else "prize")
    mix = cut(mix, loop_at + LOOP_FRAMES / RATE, 0.8)
    write_ogg(PREVIEW / "machine_fever.ogg", limit(mix, -0.5), WORK)
    print(f"  preview machine_fever   {len(mix) / RATE:4.1f} s")


if __name__ == "__main__":
    SRC.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if "--preview" not in sys.argv:
        print("sounds:")
        for name, a in make_all().items():
            print(f"  {name:10s} {len(a) / RATE:5.2f} s")
    print("previews:")
    previews()
