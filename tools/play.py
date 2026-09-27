#!/usr/bin/env python3
"""Play a test flow (tests/flows/<name>.flow) in a test profile, out of your way.

    python3 tools/play.py tutorial            runs it, prints the log and where the shots are
    python3 tools/play.py tutorial --keep     keeps the profile's save afterwards (for new fixtures)

The game runs with --profile=play-<name> (its own save and settings, see DevProfile), starting
from the flow's "from" save, with its window parked off-screen. Your own game keeps running.
Exits with the game's result: 0 when every step passed.
"""
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
for line in flow.read_text().splitlines():
    if line.strip().startswith("from "):
        start = line.split()[1]
profile = f"play-{name}"
folder = Path.home() / ".local/share/godot/app_userdata/Desk Pets/profiles" / profile
shutil.rmtree(folder / "shots", ignore_errors=True)
(folder / "play.log").unlink(missing_ok=True)
args = ["godot", "--path", str(project), "--", f"--profile={profile}", f"--from={start}", f"--play=res://tests/flows/{name}.flow"]
try:
    result = subprocess.run(args, cwd=project, capture_output=True, text=True, timeout=300)
    code = result.returncode
    errors = [l for l in (result.stdout + result.stderr).splitlines() if "ERROR" in l or "SCRIPT ERROR" in l]
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
