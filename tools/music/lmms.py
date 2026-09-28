"""Small helpers for writing LMMS projects from Python and turning the renders into game audio.

Notes are (key, pos, len, vol) with LMMS keys (C0 = 0, A4 = 57; MIDI is 12 higher) and LMMS ticks
(192 to a 4/4 bar). Instruments are General MIDI sounds from the FluidR3 soundfont (sf2player):
bank 0 = instruments by GM program (0-based), bank 128 = drum kits (their notes are GM drum notes
minus 12).
"""
import re
import subprocess
import wave
from pathlib import Path

import numpy as np

BAR = 192
BEAT = 48
SF2 = "/usr/share/soundfonts/FluidR3_GM.sf2"
RATE = 44100
NOTE = {"C": 0, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "Gb": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11}


def key(name: str) -> int:
    """'A4' -> 57."""
    return NOTE[name[:-1]] + 12 * int(name[-1])


def drum(gm_note: int) -> int:
    return gm_note - 12


class Track:
    def __init__(self, name: str, patch: int, vol: int = 70, bank: int = 0, reverb: float = 0.4, pan: int = 0):
        self.name, self.patch, self.vol, self.bank, self.reverb, self.pan = name, patch, vol, bank, reverb, pan
        self.notes: list = []

    def add(self, note, pos: int, length: int, vol: int = 80) -> "Track":
        """`note` is a name ('F4'), a key, or a space-separated chord ('F4 A4 C5')."""
        if isinstance(note, str):
            for n in note.split():
                self.notes.append((key(n), pos, length, vol))
        else:
            self.notes.append((note, pos, length, vol))
        return self

    def xml(self, length: int) -> str:
        rev = (f'reverbOn="{1 if self.reverb > 0 else 0}" reverbLevel="{self.reverb}" reverbRoomSize="0.75" '
               f'reverbDamping="0.35" reverbWidth="1"')
        notes = "\n".join(f'        <note pan="0" key="{k}" vol="{v}" pos="{p}" len="{l}"/>'
                          for k, p, l, v in sorted(self.notes, key=lambda n: n[1]))
        return f'''    <track type="0" name="{self.name}" muted="0" solo="0">
      <instrumenttrack vol="{self.vol}" pan="{self.pan}" pitch="0" pitchrange="1" basenote="57" usemasterpitch="1" fxch="0">
        <instrument name="sf2player">
          <sf2player src="{SF2}" bank="{self.bank}" patch="{self.patch}" gain="1" {rev} chorusOn="0" chorusNum="3" chorusLevel="2" chorusSpeed="0.3" chorusDepth="8"/>
        </instrument>
        <chordcreator chord="0" chordrange="1" chord-enabled="0"/>
        <arpeggiator arp-enabled="0" arp="0" arprange="1" arptime="100" arpgate="100" arpdir="0" arpmode="0" syncmode="0" arptime_numerator="4" arptime_denominator="4"/>
        <fxchain enabled="0" numofeffects="0"/>
      </instrumenttrack>
      <pattern type="1" name="{self.name}" pos="0" len="{length}" muted="0" steps="16">
{notes}
      </pattern>
    </track>'''


def project(tracks: list, bpm: int, bars: int) -> str:
    length = bars * BAR
    return f'''<?xml version="1.0"?>
<!DOCTYPE lmms-project>
<lmms-project version="1.0" creator="LMMS" creatorversion="1.2.2" type="song">
  <head bpm="{bpm}" timesig_numerator="4" timesig_denominator="4" mastervol="100" masterpitch="0"/>
  <song>
    <trackcontainer type="song" visible="1" x="5" y="5" width="600" height="300" maximized="0" minimized="0">
{chr(10).join(t.xml(length) for t in tracks if t.notes)}
    </trackcontainer>
    <timeline lpstate="0" lp0pos="0" lp1pos="{length}"/>
    <controllers/>
  </song>
</lmms-project>
'''


def render(mmp: Path, out_wav: Path) -> None:
    subprocess.run(["lmms", "render", str(mmp), "-f", "wav", "-o", str(out_wav)], check=True, capture_output=True)


def render_tracks(tracks: list, bpm: int, bars: int, out_dir: Path, workers: int = 12) -> dict:
    """One wav per track (each rendered as its own little project, all at once): name -> path."""
    from concurrent.futures import ThreadPoolExecutor
    out_dir.mkdir(parents=True, exist_ok=True)

    def one(track: Track) -> Path:
        mmp = out_dir / f"{track.name}.mmp"
        mmp.write_text(project([track], bpm, bars))
        wav = out_dir / f"{track.name}.wav"
        render(mmp, wav)
        return wav

    with ThreadPoolExecutor(max_workers=workers) as pool:
        paths = list(pool.map(one, [t for t in tracks if t.notes]))
    return {p.stem: p for p in paths}


# ---- audio as numpy arrays (frames x 2, float) --------------------------------------

def read(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        assert w.getframerate() == RATE, path
        raw = w.readframes(w.getnframes())
        width, channels = w.getsampwidth(), w.getnchannels()
    if width == 2:
        a = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif width == 4:
        a = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"{path}: {width * 8}-bit")
    a = a.reshape(-1, channels)
    return np.repeat(a, 2, axis=1) if channels == 1 else a


def write_wav(path: Path, a: np.ndarray) -> None:
    pcm = (np.clip(a, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def write_ogg(path: Path, a: np.ndarray, tmp_dir: Path) -> None:
    tmp = tmp_dir / (path.stem + ".tmp.wav")
    write_wav(tmp, a)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "6", str(path)], check=True)
    tmp.unlink()


def loudness(a: np.ndarray, tmp_dir: Path) -> float:
    """Integrated loudness (LUFS), measured by ffmpeg."""
    import uuid
    tmp = tmp_dir / f"_measure_{uuid.uuid4().hex}.wav"
    write_wav(tmp, a)
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(tmp), "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    tmp.unlink()
    found = re.findall(r"I:\s+(-?[\d.]+) LUFS", out)
    return float(found[-1]) if found else -70.0


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def trim_tail(a: np.ndarray, floor_db: float = -60.0, fade: float = 0.25) -> np.ndarray:
    """Cuts the silence off the end, with a short fade so it doesn't click."""
    loud = np.nonzero(np.max(np.abs(a), axis=1) > db(floor_db))[0]
    end = int(loud[-1]) + 1 if loud.size else 1
    a = a[:end].copy()
    n = min(int(fade * RATE), end)
    a[end - n:] *= np.linspace(1.0, 0.0, n)[:, None]
    return a


def limit(a: np.ndarray, ceiling_db: float = -1.0) -> np.ndarray:
    """A gentle safety: scales down only if a peak would pass the ceiling."""
    peak = float(np.max(np.abs(a))) if a.size else 0.0
    return a * (db(ceiling_db) / peak) if peak > db(ceiling_db) else a
