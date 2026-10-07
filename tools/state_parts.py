#!/usr/bin/env python3
"""GameState's parts: moves functions out of scripts/game_state.gd into a part (scripts/state/*.gd)
and keeps GameState's forwarders up to date.

GameState (the autoload) keeps all the state (every var, signal and const: the save, the UI and the
tests read them there) and the frame loop; the code lives in parts by area, each a RefCounted that
GameState owns (`var machine_part := MachinePart.new(self)`) and that reaches the state through
`gs` (typed GameStateNode, the class_name of game_state.gd). GameState keeps a one-line forwarder for
every public function of a part and for every private one something outside that part calls, so
`GameState.pull_lever()` and the rest work as they always did.

    python3 tools/state_parts.py move <file stem> <ClassName> <part var> <func> [func...]
        moves those functions (with their ## docs) from game_state.gd into scripts/state/<stem>.gd
        (made if it isn't there), rewriting them for the part: GameState's vars, signals and
        functions become gs.<name>, its consts and statics GameStateNode.<NAME>; then forwarders
    python3 tools/state_parts.py forwarders
        writes GameState's forwarder block again from the parts (after moving code by hand, or
        merging a part)
    python3 tools/state_parts.py check
        every gs.<name> in the parts is on GameState (Godot only finds a wrong one when it runs)
    python3 tools/state_parts.py names <func> [...]
        prints which part (or GameState) has each function

A function name may be @file: one name per line. After a move run the core tests: Godot checks
every gs.<name> (gs is typed), so a name the rewrite got wrong is a parse error, not a surprise.
New parts are new class names: run `godot --headless --import` once before the tests.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GS = ROOT / "scripts" / "game_state.gd"
PARTS = ROOT / "scripts" / "state"
GS_CLASS = "GameStateNode"
FWD_START = "# ---- forwarders: the parts' functions, so GameState.<name>() works as before (tools/state_parts.py writes this block) ----"
FWD_END = "# ---- end of the forwarders ----"
REG_START = "# ---- GameState's parts, by area (scripts/state/): the code lives there, the state stays here ----"
REG_END = "# ---- end of the parts ----"

# Object/Node methods and properties moved code may use bare (they belong to GameState, a Node)
NODE_NAMES = set("""
get_tree is_inside_tree get_node get_node_or_null add_child remove_child set_process set_physics_process
queue_free get_viewport emit_signal call call_deferred callv connect disconnect is_connected get set
has_method has_signal get_script notification get_instance_id get_parent get_window get_children
is_queued_for_deletion set_process_input propagate_call tr name owner process_mode set_deferred
is_processing get_meta set_meta has_meta
""".split())
KEYWORDS = set("""
var func for in if elif else return match while break continue pass and or not is as true false null
self super await static const signal extends class_name void when breakpoint enum class PI TAU INF NAN
""".split())

TOKEN = re.compile(r'''
  (?P<comment>\#[^\n]*)
| (?P<string>[r&^]?(?:"""(?:\\.|[^\\])*?"""|\'\'\'(?:\\.|[^\\])*?\'\'\'|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))
| (?P<number>0x[0-9a-fA-F_]+|0b[01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?)
| (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
| (?P<nl>\n)
| (?P<other>.)
''', re.X | re.S)


def tokens(text):
    """(kind, text, offset) for every token."""
    for m in TOKEN.finditer(text):
        yield m.lastgroup, m.group(), m.start()


# ---- the file's top-level blocks -----------------------------------------------------------

def top_level(lines):
    """Every top-level declaration: dicts { kind, name, static, start, head, end } with line indexes:
    start = its first ## doc line (or head), head = the declaration line, end = one past its last line."""
    out = []
    n = len(lines)
    i = 0
    while i < n:
        line = lines[i]
        m = re.match(r'^(static\s+)?(func|var|const|signal)\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        m2 = re.match(r'^@\w+\s+(var)\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        if m or m2:
            if m:
                static, kind, name = bool(m.group(1)), m.group(2), m.group(3)
            else:
                static, kind, name = False, m2.group(1), m2.group(2)
            start = i
            while start > 0 and lines[start - 1].startswith("#") and not lines[start - 1].startswith("# ----"):
                start -= 1
            end = i + 1
            while end < n:
                l = lines[end]
                if l.strip() == "" or l[0] in " \t":
                    end += 1
                    continue
                if l.startswith("#") and not l.startswith("# ----"):
                    # a column-0 comment inside a body: the body goes on after it
                    k = end
                    while k < n and (lines[k].startswith("#") or lines[k].strip() == ""):
                        k += 1
                    if k < n and lines[k][:1] in (" ", "\t"):
                        end = k
                        continue
                break
            while end > i + 1 and lines[end - 1].strip() == "":
                end -= 1
            out.append({"kind": kind, "name": name, "static": static, "start": start, "head": i, "end": end})
            i = end
            continue
        i += 1
    return out


def members(lines):
    """GameState's names: { name: kind } where kind is var, signal, const, static (static var or
    func: reached through the class) or func."""
    names = {}
    for b in top_level(lines):
        if b["kind"] == "const" or b["static"]:
            names[b["name"]] = "static"
        else:
            names[b["name"]] = b["kind"]
    return names


# ---- signatures ----------------------------------------------------------------------------

def split_top(s, sep=","):
    """Splits on sep outside brackets and strings."""
    parts, depth, cur, i = [], 0, "", 0
    quote = None
    while i < len(s):
        c = s[i]
        if quote:
            cur += c
            if c == "\\":
                cur += s[i + 1]
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        parts.append(cur)
    return parts


def signature(head):
    """(name, params text, [param names], return type or None) of a `func` line."""
    m = re.match(r'^(?:static\s+)?func\s+(\w+)\s*\(', head)
    name = m.group(1)
    i = m.end()
    depth = 1
    j = i
    while depth:
        c = head[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c in "\"'":
            q = c
            j += 1
            while head[j] != q:
                j += 2 if head[j] == "\\" else 1
        j += 1
    params = head[i:j - 1]
    rest = head[j:]
    rm = re.match(r'\s*->\s*([^:]+?)\s*:', rest)
    ret = rm.group(1) if rm else None
    names = [re.match(r'\s*(\w+)', p).group(1) for p in split_top(params)]
    return name, params, names, ret


# ---- rewriting a function for a part ---------------------------------------------------------

def indent_of(line):
    return len(line) - len(line.lstrip("\t "))


def rewrite(text, gs_names, own, report):
    """Rewrites one function's text for a part: bare GameState names -> gs.<name> (vars, signals,
    functions, Node methods), GameStateNode.<NAME> (consts, statics), self -> gs. Locals (params,
    var, const, for, lambda params) in scope and the part's own functions stay."""
    lines = text.split("\n")
    line_starts = []
    pos = 0
    for l in lines:
        line_starts.append(pos)
        pos += len(l) + 1

    def line_of(off):
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo

    toks = [t for t in tokens(text)]
    code = [t for t in toks if t[0] not in ("comment", "nl") and not t[1].isspace()]

    # scopes: name -> list of (from offset, to offset)
    scopes = {}

    def block_end(line_idx, ind, strict):
        """Offset where the block of lines after line_idx at indent >= ind (> ind if strict) ends."""
        k = line_idx + 1
        last = line_idx
        while k < len(lines):
            l = lines[k]
            if l.strip() == "" or l.lstrip().startswith("#"):
                k += 1
                continue
            li = indent_of(l)
            if (li > ind) if strict else (li >= ind):
                last = k
                k += 1
                continue
            break
        return line_starts[last] + len(lines[last])

    def add_scope(name, frm, to):
        scopes.setdefault(name, []).append((frm, to))

    # the function's own params: everywhere
    head_line = next(i for i, l in enumerate(lines) if re.match(r'^(static\s+)?func\s', l))
    head_name, _, pnames, _ = signature(lines[head_line])
    for p in pnames:
        add_scope(p, 0, len(text))

    for idx, (kind, t, off) in enumerate(code):
        if kind != "ident":
            continue
        li = line_of(off)
        ind = indent_of(lines[li])
        if t in ("var", "const") and idx + 1 < len(code) and code[idx + 1][0] == "ident":
            if li == head_line:
                continue
            add_scope(code[idx + 1][1], code[idx + 1][2], block_end(li, ind, False))
        elif t == "for" and idx + 1 < len(code) and code[idx + 1][0] == "ident":
            add_scope(code[idx + 1][1], code[idx + 1][2], block_end(li, ind, True))
        elif t == "func" and li != head_line:
            # a lambda: func(params) or func name(params)
            j = idx + 1
            if j < len(code) and code[j][0] == "ident":
                j += 1
            if j < len(code) and code[j][1] == "(":
                depth = 0
                k = j
                params = []
                expect = True
                while k < len(code):
                    tt = code[k][1]
                    if tt in "([{":
                        depth += 1
                    elif tt in ")]}":
                        depth -= 1
                        if depth == 0:
                            break
                    elif tt == "," and depth == 1:
                        expect = True
                    elif expect and depth == 1 and code[k][0] == "ident":
                        params.append(code[k])
                        expect = False
                    k += 1
                for p in params:
                    add_scope(p[1], p[2], block_end(li, ind, True))

    def is_local(name, off):
        for frm, to in scopes.get(name, []):
            if frm <= off <= to:
                return True
        return False

    for name in scopes:
        if name in gs_names and name not in ("_",):
            report.append(f"{head_name}: local '{name}' has a GameState name (check by hand)")

    out = []
    last = 0
    prev_sig = None  # the previous code token
    for kind, t, off in toks:
        if kind in ("comment", "nl") or t.isspace():
            continue
        if kind == "ident":
            after_dot = prev_sig is not None and prev_sig[1] in (".", "@")
            if not after_dot and not is_local(t, off) and t not in own:
                rep = None
                if t == "self":
                    rep = "gs"
                elif t in gs_names:
                    rep = (GS_CLASS + "." + t) if gs_names[t] == "static" else ("gs." + t)
                elif t in NODE_NAMES:
                    rep = "gs." + t
                if rep:
                    out.append(text[last:off])
                    out.append(rep)
                    last = off + len(t)
        prev_sig = (kind, t, off)
    out.append(text[last:])
    return "".join(out)


# ---- parts -------------------------------------------------------------------------------------

def part_header(cls):
    return (f"class_name {cls}\nextends RefCounted\n"
            f"## GameState's code for <what this area is>.\n"
            f"## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState\n"
            f"## forwards to it, so callers use GameState.<name>() as before.\n\n"
            f"var gs: {GS_CLASS}\n\n\nfunc _init(state: {GS_CLASS}) -> void:\n\tgs = state\n")


def read_parts():
    """[{ path, cls, var, funcs: [(name, head line)] }] from the registry in game_state.gd."""
    text = GS.read_text()
    reg = {}
    for m in re.finditer(r'^var (\w+) := (\w+)\.new\(self\)', text, re.M):
        reg[m.group(2)] = m.group(1)
    parts = []
    for p in sorted(PARTS.glob("*.gd")):
        t = p.read_text()
        cm = re.search(r'^class_name (\w+)', t, re.M)
        if not cm or cm.group(1) not in reg:
            continue
        lines = t.split("\n")
        funcs = []
        for b in top_level(lines):
            if b["kind"] == "func" and b["name"] != "_init":
                if b["static"]:
                    sys.exit(f"{p.name}: static func {b['name']} (keep statics on GameState)")
                funcs.append((b["name"], lines[b["head"]]))
        parts.append({"path": p, "cls": cm.group(1), "var": reg[cm.group(1)], "funcs": funcs, "text": t})
    return parts


def strip_block(text, start, end):
    a = text.find(start)
    if a < 0:
        return text, -1
    b = text.find(end, a)
    return text[:a] + text[b + len(end):], a


def outside_words():
    """Every word in the game's scripts, tests and tools, per file (to see who calls a private)."""
    words = {}
    for folder in ("scripts", "tests", "tools"):
        for f in (ROOT / folder).rglob("*.gd"):
            t = f.read_text()
            if f == GS:
                t, _ = strip_block(t, FWD_START, FWD_END)
            words[f] = set(re.findall(r'[A-Za-z_]\w*', t))
    return words


def forwarders():
    parts = read_parts()
    text = GS.read_text()
    text, at = strip_block(text, FWD_START, FWD_END)
    text = text.rstrip("\n") + "\n"
    words = outside_words()
    gs_own = members(text.split("\n"))
    seen = {}
    blocks = []
    for part in parts:
        lines_out = []
        for name, head in part["funcs"]:
            if name in seen:
                sys.exit(f"{name} is in {seen[name]} and {part['path'].name}")
            seen[name] = part["path"].name
            if name in gs_own:
                sys.exit(f"{name} is in {part['path'].name} and still in game_state.gd")
            if name.startswith("_"):
                used = any(name in w for f, w in words.items() if f != part["path"])
                if not used:
                    continue
            fname, params, pnames, ret = signature(head)
            if "gs." in params:
                sys.exit(f"{name}: a default value reads GameState state ({params})")
            call = f"{part['var']}.{name}({', '.join(pnames)})"
            sig = f"func {name}({params})" + (f" -> {ret}" if ret else "")
            body = call if ret == "void" else "return " + call
            lines_out.append(f"{sig}: {body}")
        if lines_out:
            blocks.append(f"# {part['path'].name}\n" + "\n".join(lines_out))
    block = FWD_START + "\n\n" + "\n\n".join(blocks) + "\n" + FWD_END + "\n"
    GS.write_text(text + "\n\n" + block)


def register(cls, var):
    text = GS.read_text()
    line = f"var {var} := {cls}.new(self)"
    if line in text:
        return
    if REG_START not in text:
        # after the consts, before the first var of the state
        anchor = "\nvar save_path"
        i = text.index(anchor)
        text = text[:i] + "\n" + REG_START + "\n" + REG_END + "\n" + text[i:]
    i = text.index(REG_END)
    text = text[:i] + line + "\n" + text[i:]
    GS.write_text(text)


def expand(names):
    out = []
    for n in names:
        if n.startswith("@"):
            out += [l.split("#")[0].strip() for l in Path(n[1:]).read_text().splitlines() if l.split("#")[0].strip()]
        else:
            out.append(n)
    return out


def move(stem, cls, var, names):
    names = expand(names)
    text = GS.read_text()
    text, _ = strip_block(text, FWD_START, FWD_END)
    lines = text.split("\n")
    blocks = {b["name"]: b for b in top_level(lines) if b["kind"] == "func"}
    gs_names = members(GS.read_text().split("\n"))  # forwarders count: they're callable on gs
    missing = [n for n in names if n not in blocks]
    if missing:
        sys.exit("not in game_state.gd: " + " ".join(missing))
    for n in names:
        if blocks[n]["static"]:
            sys.exit(f"{n} is static: keep it on GameState")
    path = PARTS / f"{stem}.gd"
    existing = path.read_text() if path.exists() else part_header(cls)
    # the part's code called these through GameState: now they're its own
    for n in names:
        existing = re.sub(r'\bgs\.' + n + r'\b', n, existing)
    own = set(names)
    for b in top_level(existing.split("\n")):
        if b["kind"] == "func":
            own.add(b["name"])
    report = []
    moved = []
    for n in sorted(names, key=lambda n: blocks[n]["start"]):
        b = blocks[n]
        body = "\n".join(lines[b["start"]:b["end"]])
        moved.append(rewrite(body, gs_names, own, report))
    # take them out of game_state.gd (bottom up), with the blank lines after them
    for n in sorted(names, key=lambda n: -blocks[n]["start"]):
        b = blocks[n]
        end = b["end"]
        while end < len(lines) and lines[end].strip() == "":
            end += 1
        del lines[b["start"]:end]
    text = "\n".join(lines)
    text = re.sub(r'\n{4,}', "\n\n\n", text)
    GS.write_text(text)
    PARTS.mkdir(exist_ok=True)
    path.write_text(existing.rstrip("\n") + "\n\n\n" + "\n\n\n".join(moved) + "\n")
    register(cls, var)
    forwarders()
    for r in report:
        print("CHECK", r)
    print(f"moved {len(names)} functions to {path.relative_to(ROOT)}")
    check()


def check():
    """Every gs.<name> in the parts is something GameState has, every GameStateNode.<NAME> a const or
    static (Godot doesn't check names on a typed script's instance: a wrong one fails only when run)."""
    names = members(GS.read_text().split("\n"))
    bad = 0
    for p in sorted(PARTS.glob("*.gd")):
        t = p.read_text()
        code = "".join(tt for k, tt, o in tokens(t) if k not in ("comment", "string"))
        for m in re.finditer(r'\bgs\.(\w+)', code):
            n = m.group(1)
            if names.get(n) in (None, "static") and n not in NODE_NAMES:
                print(f"BAD {p.name}: gs.{n}")
                bad += 1
        for m in re.finditer(r'\b' + GS_CLASS + r'\.(\w+)', code):
            if names.get(m.group(1)) != "static":
                print(f"BAD {p.name}: {GS_CLASS}.{m.group(1)}")
                bad += 1
    # and what other scripts call on GameState (or on a GameState a test or tool made: gs, gs2, ...)
    for folder in ("scripts", "tests", "tools"):
        for f in sorted((ROOT / folder).rglob("*.gd")):
            if f == GS or f.parent == PARTS:
                continue
            t = f.read_text()
            code = "".join(tt for k, tt, o in tokens(t) if k not in ("comment", "string"))
            pat = r'\b(?:GameState|gs\d?|old_gs)\.(\w+)'
            if f.name == "quiet_paws.gd":
                pat = r'\b(?:GameState|gs|state)\.(\w+)'
            for m in re.finditer(pat, code):
                n = m.group(1)
                if n not in names and n not in NODE_NAMES and n not in ("new", "set", "get", "free", "queue_free", "SAVE_VERSION"):
                    print(f"BAD {f.relative_to(ROOT)}: {m.group(0)}")
                    bad += 1
    if bad:
        sys.exit(f"{bad} bad names")
    print("names ok")


def where(names):
    parts = read_parts()
    gs = {b["name"] for b in top_level(GS.read_text().split("\n")) if b["kind"] == "func"}
    for n in expand(names):
        found = [p["path"].name for p in parts if any(f == n for f, _ in p["funcs"])]
        print(n, found[0] if found else ("game_state.gd" if n in gs else "?"))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "move" and len(sys.argv) > 5:
        move(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif cmd == "forwarders":
        forwarders()
    elif cmd == "check":
        check()
    elif cmd == "names":
        where(sys.argv[2:])
    else:
        sys.exit(__doc__)
