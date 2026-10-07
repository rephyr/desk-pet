#!/usr/bin/env python3
"""Play a test flow (tests/flows/<name>.flow) in a test profile, out of your way.

    python3 tools/play.py tutorial            runs it, prints the log and where the shots are
    python3 tools/play.py tutorial --keep     keeps the profile's save afterwards (for new fixtures)
    python3 tools/play.py tutorial --show     runs on your real desktop instead of a hidden screen

The game runs with --profile=play-<name> (its own save and settings, see DevProfile), starting
from the flow's "from" save, on a hidden virtual screen (Xvfb, software rendering), so no window
ever shows up on your desktop and Hyprland doesn't shuffle your windows around. Shots come out at
1x scale. Your own game keeps running.
Set DESK_PETS_LANE=<name> to give the profile its own suffix, so several copies of the repo
(git worktrees) can play the same flow at once without sharing a save.
Exits with the game's result: 0 when every step passed (3 when they did but a script error was printed).
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

project = Path(__file__).resolve().parent.parent
name = sys.argv[1]
flow = project / "tests" / "flows" / f"{name}.flow"
if not flow.exists():
    sys.exit(f"no flow {flow}")
start = "new"
flags = []
for line in flow.read_text().splitlines():
    if line.strip().startswith("from "):
        start = line.split()[1]
    if line.strip().startswith("flags "):
        flags += line.split("#")[0].split()[1:]
lane = os.environ.get("DESK_PETS_LANE", "")
profile = f"play-{name}" + (f"-{lane}" if lane else "")
folder = Path.home() / ".local/share/godot/app_userdata/Desk Pets/profiles" / profile
shutil.rmtree(folder / "shots", ignore_errors=True)
(folder / "play.log").unlink(missing_ok=True)
args = ["godot", "--path", str(project), "--", f"--profile={profile}", f"--from={start}", f"--play=res://tests/flows/{name}.flow"] + flags
env = None
if "--show" not in sys.argv and shutil.which("xvfb-run"):
    # a hidden X screen: without Wayland or Hyprland in sight the game uses X11 and leaves your
    # windows alone; mesa draws it (the NVIDIA driver can't draw on Xvfb)
    env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE")}
    env["__GLX_VENDOR_LIBRARY_NAME"] = "mesa"
    env["__EGL_VENDOR_LIBRARY_FILENAMES"] = "/usr/share/glvnd/egl_vendor.d/50_mesa.json"


def free_display(n):
    """The first X display number from n up that nothing holds (no lock file, no socket)."""
    while Path(f"/tmp/.X{n}-lock").exists() or Path(f"/tmp/.X11-unix/X{n}").exists():
        n += 1
    return n


def xvfb_args(n):
    return ["xvfb-run", "-n", str(n), "-s", "-screen 0 2560x1440x24"] + args


run = [args]
if env is not None:
    # a display number of its own per lane + flow (`xvfb-run -a` races when several flows start
    # at once): the hashed one or the next free one up, and one more try past it if that fails
    import zlib
    display = free_display(100 + zlib.crc32(f"{lane}:{name}".encode()) % 800)
    run = [xvfb_args(display), xvfb_args(free_display(display + 1 + os.getpid() % 50))]
try:
    for i, cmd in enumerate(run):
        result = subprocess.run(cmd, cwd=project, capture_output=True, text=True, timeout=300, env=env)
        out = result.stdout + result.stderr
        if i + 1 < len(run) and result.returncode != 0 and "Xvfb failed to start" in out:
            continue
        break
    code = result.returncode
    (folder / "godot.log").write_text(out)  # the whole output, for grepping warnings / leaks
    errors =[l for l in out.splitlines() if "ERROR" in l or "SCRIPT ERROR" in l or "Xvfb failed" in l]
    if code == 0 and any("SCRIPT ERROR" in l for l in errors):
        code = 3  # every step passed, but a script broke along the way
except subprocess.TimeoutExpired:
    code, errors = 2, ["timed out after 300s"]
log = folder / "play.log"
print(log.read_text() if log.exists() else "(no log)")
for e in errors[:20]:
    print("  !", e)
print(f"shots: {folder / 'shots'}")
if "--keep" not in sys.argv:
    for f in ["save.json", "save.json.bak"]:
        (folder / f).unlink(missing_ok=True)
sys.exit(code)
