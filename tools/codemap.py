#!/usr/bin/env python3
"""Godot digest probe (CodeMap step 1: index -> compact digest, no retrieval yet).

Goal: give an AI coding agent ONE small artifact to read instead of running a
grep/read sweep across a 300-file project.

Outputs (default dir .codemap_probe/):
    map.sym.txt      GREP TARGET: one self-describing line per symbol
                     (path:line kind name). Never read it whole.
    map.refs.txt     GREP TARGET: every reference as
                     `target <- file:line kind [func] detail`
    refs.json        the same references as JSON
    map.txt          per script: class / extends / signals / exports /
                     funcs with line numbers / %unique refs / preloads
    map.mid.txt      funcs + line numbers only (smaller)
    map.t0.txt       func names only, no line numbers (smallest)
    map.scripts-*.txt  the three levels above, scripts/ only
    scenes.txt       .tscn trees: nodes -> type -> script, instances, connections

Usage:
    python tools/codemap.py index --root . [--godot <Godot_*_console.exe>]
    python tools/codemap.py refs <symbol> [--kind call] [--json] [--limit N]

Symbol names come from an indentation scan; `--godot` additionally cross-checks
them against Godot's own parser (`--doctool --gdscript-docs`, which is partial and
carries no line numbers, so the scanner stays the primary source).
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

GD_EXT = ".gd"
SCENE_EXT = ".tscn"
RES_EXT = ".tres"

DEFAULT_EXCLUDES = (
    "addons", "archive", ".godot", ".git", ".idea", ".claude",
    ".codemap", ".codemap_probe", "__pycache__",
)

# --- GDScript top-level declarations (indent 0 only) -------------------------
ANNOT = r"(?:@[A-Za-z_]\w*(?:\([^()]*\))?\s+)*"
DECLS: list[tuple[str, re.Pattern[str]]] = [
    ("class_name", re.compile(r"^" + ANNOT + r"class_name\s+([A-Za-z_]\w*)")),
    ("extends", re.compile(r"^" + ANNOT + r"extends\s+(.+?)\s*$")),
    ("func", re.compile(r"^" + ANNOT + r"(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")),
    ("signal", re.compile(r"^" + ANNOT + r"signal\s+([A-Za-z_]\w*)")),
    ("var", re.compile(r"^" + ANNOT + r"(?:static\s+)?var\s+([A-Za-z_]\w*)")),
    ("const", re.compile(r"^" + ANNOT + r"const\s+([A-Za-z_]\w*)")),
    ("enum", re.compile(r"^" + ANNOT + r"enum(?:\s+([A-Za-z_]\w*))?")),
    ("class", re.compile(r"^" + ANNOT + r"class\s+([A-Za-z_]\w*)")),
]
VAR_TYPE = re.compile(r"^" + ANNOT + r"(?:static\s+)?var\s+([A-Za-z_]\w*)\s*:\s*([^=\n]+)")
VAR_NODE = re.compile(r"%(?:[A-Za-z_]\w*)|\$([A-Za-z_][\w/]*)")
RES_PATH = re.compile(r"(preload|load)\s*\(\s*\"res://([^\"]+)\"")
INSTANTIATE = re.compile(r"\.instantiate\s*\(")

# --- call extraction --------------------------------------------------------
KEYWORDS = {
    "if", "elif", "else", "for", "while", "match", "return", "and", "or", "not",
    "in", "is", "as", "await", "assert", "break", "continue", "pass", "func",
    "var", "const", "signal", "enum", "class", "extends", "class_name", "static",
    "when", "super",
}
CALL = re.compile(r"(?<![\w.])(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*\(")
LEAD_KW = re.compile(r"^(?:elif|if|while|for|match|return|assert|else)\b\s*")

# chain-aware call/reference matcher: captures the whole dotted receiver chain
CALLABLE = re.compile(r"(?:([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.)?([A-Za-z_]\w*)\s*\(")
AWAIT = re.compile(r"\bawait\s+([A-Za-z_][\w.]*)")
STR_LIT = re.compile(r"\"([^\"\n]*)\"|'([^'\n]*)'")
NODE_STR = re.compile(r'\$"([^"]+)"')
NODE_PATH = re.compile(r"\$([A-Za-z_][\w/]*)")
NODE_GETNODE = re.compile(r'get_node(?:_or_null)?\(\s*"([^"]+)"')
NODE_UNIQUE = re.compile(r"%([A-Za-z_]\w*)")
STRING_CALLERS = ("call", "callv", "has_method", "is_connected", "emit_signal")


def bracket_delta(line: str) -> int:
    """Net bracket depth of one physical line, ignoring strings and comments."""
    depth = 0
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        i += 1
    return depth


def logical_lines(lines: list[str]) -> list[tuple[int, str]]:
    """Join statements that span several physical lines, keeping the start line.

    GDScript lets a call or a `signal.connect(handler)` chain wrap across lines;
    scanning raw lines would miss those entirely.
    """
    out: list[tuple[int, str]] = []
    buf: list[str] = []
    start = 0
    depth = 0
    for i, line in enumerate(lines):
        if not buf:
            start = i
        buf.append(line)
        depth += bracket_delta(line)
        if depth <= 0:
            out.append((start, " ".join(x.strip() for x in buf)))
            buf = []
            depth = 0
    if buf:
        out.append((start, " ".join(x.strip() for x in buf)))
    return out


def split_args(text: str, open_idx: int) -> list[str]:
    """Top-level comma split of the argument list starting at text[open_idx] == '('."""
    if open_idx >= len(text) or text[open_idx] != "(":
        return []
    args: list[str] = []
    cur: list[str] = []
    depth = 0
    quote = None
    i = open_idx
    while i < len(text):
        ch = text[i]
        if quote:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                i += 1
                cur.append(text[i])
            elif ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            if depth > 1:
                cur.append(ch)
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                args.append("".join(cur).strip())
                return args
            cur.append(ch)
        elif ch == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    return args


def _handler_name(raw: str) -> str:
    """`_on_x`, `self._on_x`, `_on_x.bind(y)`, `Callable(self, "x")` -> `_on_x`."""
    raw = raw.strip()
    if not raw:
        return ""
    if raw.startswith("Callable"):
        m = re.search(r'"([A-Za-z_]\w*)"', raw)
        return m.group(1) if m else ""
    if raw.startswith(("func", "\\")):
        return "<lambda>"
    raw = raw.split(".bind", 1)[0].strip()
    segs = [x for x in raw.split(".") if x and x != "self"]
    return segs[-1] if segs else ""


def _segments(chain: str) -> list[str]:
    return [x for x in chain.split(".") if x and x != "self"]


def est_tokens(text: str) -> int:
    """Deterministic estimate only: characters / 4. Label it as an estimate."""
    return len(text) // 4


# =============================================================================
# GDScript scan
# =============================================================================
def scan_script(path: Path, rel: str) -> dict:
    """Indentation scan. Never raises: returns what it could read."""
    out = {
        "path": rel, "lines": 0, "class_name": None, "extends": None,
        "funcs": [], "signals": [], "exports": [], "vars": [], "consts": [],
        "enums": [], "inner_classes": [], "unique_refs": [], "resources": [],
        "calls": [], "refs": [], "strings": [], "errors": [],
    }
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001 - one bad file must not stop the index
        out["errors"].append(f"read: {exc}")
        return out

    lines = text.splitlines()
    out["lines"] = len(lines)

    tops: list[tuple[int, str, str]] = []   # (index, kind, name)
    raw: list[str] = []
    for i, line in enumerate(lines):
        raw.append(line)
        if not line or line[0] in " \t#":
            continue
        for kind, pat in DECLS:
            m = pat.match(line)
            if not m:
                continue
            name = (m.group(1) or "").strip()
            if kind == "extends":
                name = name.strip().strip('"').strip("'")
            if kind == "func":
                pass
            tops.append((i, kind, name))
            break

    # attributes
    for i, kind, name in tops:
        line = raw[i]
        if kind == "class_name":
            out["class_name"] = name
        elif kind == "extends":
            out["extends"] = name
        elif kind == "func":
            out["funcs"].append({"name": name, "line": i + 1, "end": 0,
                                 "static": "static " in line})
        elif kind == "signal":
            out["signals"].append({"name": name, "line": i + 1})
        elif kind == "enum":
            out["enums"].append(name or "(anonymous)")
        elif kind == "class":
            out["inner_classes"].append({"name": name, "line": i + 1})
        elif kind == "const":
            out["consts"].append({"name": name, "line": i + 1})
        elif kind == "var":
            if "@export" in line:
                tm = VAR_TYPE.match(line)
                out["exports"].append({"name": name, "line": i + 1,
                                       "type": (tm.group(2).strip() if tm else "")})
            else:
                out["vars"].append(name)
            if "@onready" in line:
                for ref in VAR_NODE.findall(line):
                    if ref and "/" not in ref:
                        out["unique_refs"].append(ref)

    # function end lines = next top-level declaration - 1 (trim trailing blanks)
    top_idx = [i for i, _, _ in tops]
    for n, (i, kind, name) in enumerate(tops):
        if kind != "func":
            continue
        stop = top_idx[n + 1] if n + 1 < len(top_idx) else len(lines)
        end = stop
        while end > i + 1 and (not lines[end - 1].strip() or lines[end - 1].lstrip().startswith("#")):
            end -= 1
        for f in out["funcs"]:
            if f["line"] == i + 1 and f["name"] == name:
                f["end"] = end
                break

    # resources
    for kw, res in RES_PATH.findall(text):
        out["resources"].append({"kind": kw, "path": res,
                                 "instantiate": bool(INSTANTIATE.search(text))})

    # ---- references (scanned on LOGICAL lines: a wrapped call or an
    # `obj.signal.connect(handler)` chain is one statement, not several lines)
    func_ranges = [(f["line"], f["end"] or f["line"], f["name"]) for f in out["funcs"]]

    def owner(line_no: int) -> str:
        for a, b, nm in func_ranges:
            if a <= line_no <= b:
                return nm
        return ""

    for start, joined in logical_lines(lines):
        line_no = start + 1
        stmt = joined.split("#", 1)[0]
        fn = owner(line_no)

        for m in STR_LIT.finditer(stmt):
            txt = m.group(1) if m.group(1) is not None else m.group(2)
            out["strings"].append({"line": line_no, "text": txt})

        for rx in (NODE_STR, NODE_PATH, NODE_GETNODE, NODE_UNIQUE):
            for m in rx.finditer(stmt):
                out["refs"].append({"kind": "node_ref", "target": m.group(1),
                                    "line": line_no, "func": fn, "detail": ""})

        m = AWAIT.search(stmt)
        if m and stmt[m.end():m.end() + 1] != "(":
            segs = _segments(m.group(1))
            if segs:
                out["refs"].append({"kind": "await", "target": segs[-1],
                                    "line": line_no, "func": fn, "detail": ""})

        # a declaration is not a call: `func x()` / `signal x(...)` also look like
        # `name(`, so remember where the declared identifier sits and skip it
        decl_spans = []
        for _kind, _pat in DECLS:
            dm = _pat.match(stmt)
            if dm and dm.group(1):
                decl_spans.append((dm.start(1), dm.end(1)))

        for m in CALLABLE.finditer(stmt):
            chain = m.group(1) or ""
            callee = m.group(2)
            segs = _segments(chain)
            last = segs[-1] if segs else ""
            recv = ".".join(segs[:-1])
            if callee in KEYWORDS:
                continue
            if any(a <= m.start(2) < b for a, b in decl_spans):
                continue
            args = split_args(stmt, m.end() - 1)
            first = args[0] if args else ""

            if callee == "emit" and last:
                out["refs"].append({"kind": "emit", "target": last, "line": line_no,
                                    "func": fn, "detail": ("on " + recv) if recv else ""})
            elif callee == "connect":
                # `recv.sig.connect(handler)` | `sig.connect(handler)` |
                # `recv.connect("sig", handler)` | `expr[i].connect(handler)`
                if first.startswith(("\"", "'")):
                    sig, recv, hraw = (first.strip("\"'"), ".".join(segs),
                                       (args[1] if len(args) > 1 else ""))
                elif segs:
                    sig, recv, hraw = segs[-1], ".".join(segs[:-1]), first
                else:
                    sig, recv, hraw = "", "", first
                handler = _handler_name(hraw)
                if sig:
                    out["refs"].append({"kind": "connect_signal", "target": sig,
                                        "line": line_no, "func": fn,
                                        "detail": ("handler=" + (handler or "?")) +
                                                  ((" on " + recv) if recv else "")})
                if handler and handler != "<lambda>":
                    out["refs"].append({"kind": "connect_handler", "target": handler,
                                        "line": line_no, "func": fn,
                                        "detail": "for signal " + (sig or "?")})
            elif callee in STRING_CALLERS and first.startswith(("\"", "'")):
                out["refs"].append({"kind": "string_call", "target": first.strip("\"'"),
                                    "line": line_no, "func": fn, "detail": callee})
            elif callee in ("preload", "load") and first.startswith(("\"", "'")):
                out["refs"].append({"kind": "preload", "target": short_res(first.strip("\"'")),
                                    "line": line_no, "func": fn, "detail": callee})
            elif callee == "instantiate":
                out["refs"].append({"kind": "instantiate", "target": last or chain,
                                    "line": line_no, "func": fn, "detail": "on " + recv})
            else:
                out["calls"].append({
                    "from_func": fn, "line": line_no,
                    "receiver": recv, "callee": callee,
                })
                out["refs"].append({"kind": "call", "target": callee, "line": line_no,
                                    "func": fn, "detail": ("on " + recv) if recv else ""})
    return out


# =============================================================================
# Godot doctool (engine's own parser) - optional cross-check / resolved inherits
# =============================================================================
def run_doctool(root: Path, godot: str, out_dir: Path) -> str | None:
    out_dir.mkdir(parents=True, exist_ok=True)
    log = out_dir / "_doctool.log"
    try:
        with open(log, "w", encoding="utf-8") as fh:  # file handles, never pipes
            subprocess.run(
                [godot, "--headless", "--doctool", str(out_dir),
                 "--gdscript-docs", "res://", "--no-docbase"],
                cwd=str(root), stdout=fh, stderr=fh, timeout=600, check=False,
            )
    except Exception as exc:  # noqa: BLE001
        return f"doctool failed: {exc}"
    return None


def read_doctool(xml_dir: Path) -> dict[str, dict]:
    """{res-relative script path: {inherits, methods, signals, members, enums}}"""
    result: dict[str, dict] = {}
    if not xml_dir.is_dir():
        return result
    for xml in xml_dir.glob("*.xml"):
        try:
            root = ET.parse(xml).getroot()
        except Exception:
            continue
        name = (root.get("name") or "").strip().strip('"')
        if not name.endswith(GD_EXT):
            continue
        result[name] = {
            "inherits": root.get("inherits") or "",
            "methods": [m.get("name") for m in root.findall("./methods/method")],
            "signals": [s.get("name") for s in root.findall("./signals/signal")],
            "members": [m.get("name") for m in root.findall("./members/member")],
            "enums": [e.get("name") for e in root.findall("./enums/enum")],
        }
    return result


# =============================================================================
# .tscn scan
# =============================================================================
ATTR = re.compile(r'([A-Za-z_]\w*)\s*=\s*("(?:[^"\\]|\\.)*"|\[[^\]]*\]|[^,\s\]]+)')
EXT_RES = re.compile(r'^\[ext_resource\b([^\]]*)\]')
NODE = re.compile(r'^\[node\b([^\]]*)\]')
CONN = re.compile(r'^\[connection\b([^\]]*)\]')
PROP = re.compile(r'^([A-Za-z_]\w*) = (.+)$')


def _attrs(blob: str) -> dict[str, str]:
    out = {}
    for k, v in ATTR.findall(blob):
        out[k] = v.strip('"')
    return out


def _ext_id(value: str) -> str:
    m = re.search(r'ExtResource\(\s*"([^"]+)"\s*\)', value)
    return m.group(1) if m else ""


def scan_scene(path: Path, rel: str) -> dict:
    out = {"path": rel, "root": None, "nodes": [], "connections": [],
            "ext": {}, "instances": [], "errors": []}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception as exc:  # noqa: BLE001
        out["errors"].append(f"read: {exc}")
        return out

    cur = None
    for i, line in enumerate(lines):
        m = EXT_RES.match(line)
        if m:
            a = _attrs(m.group(1))
            out["ext"][a.get("id", "")] = {"type": a.get("type", ""),
                                           "path": a.get("path", "")}
            cur = None
            continue
        m = NODE.match(line)
        if m:
            a = _attrs(m.group(1))
            node = {
                "name": a.get("name", "?"), "type": a.get("type", ""),
                "line": i + 1,
                "parent": a.get("parent", None), "scene_file": "",
                # in Godot 4 `script` is a PROPERTY LINE below the node header,
                # not a header attribute - resolved from the prop lines below.
                "script": out["ext"].get(_ext_id(a.get("script", "")), {}).get("path", ""),
                "instance": out["ext"].get(_ext_id(a.get("instance", "")), {}).get("path", ""),
                "unique": a.get("unique_name_in_owner", "") == "true",
                "groups": a.get("groups", ""),
            }
            out["nodes"].append(node)
            cur = node
            continue
        m = CONN.match(line)
        if m:
            a = _attrs(m.group(1))
            out["connections"].append({
                "signal": a.get("signal", ""), "from": a.get("from", ""),
                "to": a.get("to", ""), "method": a.get("method", ""),
                "flags": a.get("flags", ""), "line": i + 1,
            })
            cur = None
            continue
        m = PROP.match(line)
        if m and cur is not None:
            key, value = m.group(1), m.group(2).strip()
            if key == "script":
                cur["script"] = out["ext"].get(_ext_id(value), {}).get("path", "")
            elif key == "unique_name_in_owner":
                cur["unique"] = value == "true"
            elif key == "scene_file_path":
                cur["scene_file"] = value.strip('"')
            continue

    for node in out["nodes"]:
        if node["instance"]:
            out["instances"].append({"node": node["name"], "path": node["instance"]})
    if out["nodes"]:
        out["root"] = out["nodes"][0]["name"]
    return out


# =============================================================================
# Rendering
# =============================================================================
def short_res(target: str) -> str:
    return target[len("res://"):] if target.startswith("res://") else target


def render_script_block(s: dict, level: str, with_lines: bool) -> list[str]:
    """level: full (everything) | mid (funcs+lines) | t0 (func names only)."""
    head = s["path"].split("/")[-1]
    meta = []
    if s["class_name"]:
        meta.append(s["class_name"])
    if s["extends"]:
        meta.append("<" + s["extends"].replace("res://", ""))
    if s["inner_classes"] and level == "full":
        meta.append("+%dinner" % len(s["inner_classes"]))
    meta.append("%dL" % s["lines"])
    lines = ["  " + head + " " + " ".join(meta)]

    if s["funcs"]:
        parts = []
        for f in s["funcs"]:
            tag = "!" if f["static"] else ""
            num = (":%d" % f["line"]) if with_lines else ""
            parts.append(tag + f["name"] + num)
        lines.append("    f " + " ".join(parts))
    if level == "full":
        if s["signals"]:
            lines.append("    s " + " ".join(x["name"] for x in s["signals"]))
        if s["exports"]:
            ex = []
            for e in s["exports"]:
                ex.append(e["name"] + ((":" + e["type"].replace(" ", "")) if e["type"] else ""))
            lines.append("    e " + " ".join(ex))
        if s["unique_refs"]:
            lines.append("    u " + " ".join(sorted(set("%" + r for r in s["unique_refs"]))))
        res = sorted({short_res(r["path"]) + ("*" if r["instantiate"] else "")
                      for r in s["resources"]})
        if res:
            lines.append("    p " + " ".join(res))
    if s["errors"]:
        lines.append("    ! " + "; ".join(s["errors"]))
    return lines


def render_scene_block(sc: dict) -> list[str]:
    lines = ["  " + sc["path"].split("/")[-1]]
    if not sc["nodes"]:
        return lines
    depth: dict[str, int] = {}
    root = sc["nodes"][0]
    depth["."] = 0
    depth[root["name"]] = 0
    for node in sc["nodes"]:
        parent = node["parent"]
        d = depth.get(parent if parent is not None else ".", depth.get(".", 0))
        if parent not in (None, "."):
            d = depth.get(parent, 0)
        depth[node["name"]] = d
        tag = ""
        if node["unique"]:
            tag += "%"
        if node["instance"]:
            tag += "*"
        typ = (":" + node["type"]) if node["type"] else ""
        lines.append("    " + "  " * d + tag + node["name"] + typ)
        if node["script"]:
            lines.append("    " + "  " * d + "  gd=" + short_res(node["script"]))
        elif node["instance"]:
            lines.append("    " + "  " * d + "  inst=" + short_res(node["instance"]))
        depth[node["name"]] = d + 1
        if parent in (None, "."):
            depth["."] = 1
    for c in sc["connections"]:
        lines.append("    conn %s.%s -> %s.%s" % (c["from"], c["signal"], c["to"], c["method"]))
    return lines


# =============================================================================
# references
# =============================================================================
def classify_strings(script_data: list[dict]) -> set[str]:
    """Names carried inside string literals.

    `player.call("is_movement_locked")` is a real reference that no syntax-based
    call graph sees. Anything already captured as a typed reference is skipped;
    whatever is left is tagged weak, because a literal can coincidentally equal a
    symbol name (UI text, dictionary keys).
    """
    syms: set[str] = set()
    for s in script_data:
        syms.update(f["name"] for f in s["funcs"])
        syms.update(x["name"] for x in s["signals"])
        syms.update(e["name"] for e in s["exports"])
        syms.update(c["name"] for c in s["consts"])
        if s["class_name"]:
            syms.add(s["class_name"])
    typed = ("string_call", "connect_signal", "emit", "await", "call")
    for s in script_data:
        seen = {(r["target"], r["line"]) for r in s["refs"] if r["kind"] in typed}
        for lit in s["strings"]:
            t = lit["text"]
            if not t or len(t) < 3 or t not in syms or (t, lit["line"]) in seen:
                continue
            s["refs"].append({"kind": "string_ref", "target": t, "line": lit["line"],
                              "func": "", "detail": "weak"})
    return syms


def build_refs(script_data: list[dict], scene_data: list[dict]) -> list[dict]:
    refs: list[dict] = []

    def add(target, kind, file, line, func="", detail=""):
        if target:
            refs.append({"target": target, "kind": kind, "file": file,
                         "line": line, "func": func, "detail": detail})

    for s in script_data:
        p = s["path"]
        if s["class_name"]:
            add(s["class_name"], "class", p, 0)
        if s["extends"]:
            add(s["extends"].replace("res://", ""), "extends", p, 0)
        for f in s["funcs"]:
            add(f["name"], "def", p, f["line"], "", "func")
        for x in s["signals"]:
            add(x["name"], "def", p, x["line"], "", "signal")
        for x in s["exports"]:
            add(x["name"], "def", p, x["line"], "", "export")
        for x in s["consts"]:
            add(x["name"], "def", p, x["line"], "", "const")
        for r in s["refs"]:
            add(r["target"], r["kind"], p, r["line"], r.get("func", ""), r.get("detail", ""))
    for sc in scene_data:
        for node in sc["nodes"]:
            if node["script"]:
                add(short_res(node["script"]), "scene_node", sc["path"],
                    node.get("line", 0), "", "node " + node["name"])
            if node["instance"]:
                add(short_res(node["instance"]), "scene_instance", sc["path"],
                    node.get("line", 0), "", "node " + node["name"])
        for c in sc["connections"]:
            add(c["method"], "scene_connect", sc["path"], c.get("line", 0), "",
                "signal %s from %s" % (c["signal"], c["from"]))
    return refs


def render_refs(refs: list[dict]) -> str:
    lines = ["#GODOT REFS  target <- file:line kind [func] detail",
             "#grep '^<symbol> ' for every indexed reference; textual only, not a proof"]
    for r in sorted(refs, key=lambda r: (r["target"], r["file"], r["line"])):
        parts = [r["target"], " <- ", "%s:%d" % (r["file"], r["line"]), " ", r["kind"]]
        if r["func"]:
            parts.append(" [" + r["func"] + "]")
        if r["detail"]:
            parts.append(" " + r["detail"])
        lines.append("".join(parts))
    return "\n".join(lines) + "\n"


def scan_project(root: Path, excludes: tuple[str, ...]):
    files = gather(root, excludes)
    scripts = [f for f in files if f.suffix == GD_EXT]
    scenes = [f for f in files if f.suffix == SCENE_EXT]
    script_data = [scan_script(f, f.relative_to(root).as_posix()) for f in scripts]
    scene_data = [scan_scene(f, f.relative_to(root).as_posix()) for f in scenes]
    classify_strings(script_data)
    return files, script_data, scene_data


def cmd_refs(args) -> int:
    root = Path(args.root).resolve()
    _, script_data, scene_data = scan_project(root, DEFAULT_EXCLUDES)
    refs = build_refs(script_data, scene_data)
    if args.kind:
        refs = [r for r in refs if r["kind"] == args.kind]

    if not args.symbol:
        counts = collections.Counter(r["kind"] for r in refs)
        print("references=%d" % len(refs))
        for k, v in counts.most_common():
            print("  %-16s %d" % (k, v))
        return 0

    q = args.symbol
    exact = [r for r in refs if r["target"] == q]
    hits = exact or [r for r in refs if q in r["target"]]
    if args.json:
        print(json.dumps(hits, indent=1))
        return 0

    order = {"def": 0, "class": 1, "extends": 2}
    hits.sort(key=lambda r: (order.get(r["kind"], 5), r["file"], r["line"]))
    counts = collections.Counter(r["kind"] for r in hits)
    print("refs: %s  hits=%d  exact=%d%s"
          % (q, len(hits), len(exact), "  [substring match]" if hits and not exact else ""))
    if counts:
        print("kinds: " + " ".join("%s=%d" % (k, v) for k, v in counts.most_common()))
    if not hits:
        print("  NOT INDEXED under this name.")
        print("  This index sees textual references only. Before concluding a symbol is")
        print("  unused, grep the sources: dynamic names are invisible to it.")
        return 1
    for r in hits[:args.limit]:
        extra = ("  [" + r["func"] + "]") if r["func"] else ""
        print("  %s:%d  %s%s%s" % (r["file"], r["line"], r["kind"], extra,
                                   ("  " + r["detail"]) if r["detail"] else ""))
    if len(hits) > args.limit:
        print("  ... %d more (raise --limit)" % (len(hits) - args.limit))
    print("COVERAGE: calls / emit / connect+handler / await / string-carried names /")
    print("$node paths / preload / scene edges - all textual. Invisible: names computed")
    print("at runtime (call(var), a Callable built from a variable) and wiring that is")
    print("not written in the .tscn text. Confirm with a source grep before any rename,")
    print("signature change or signal removal.")
    return 0


# =============================================================================
# index
# =============================================================================
def gather(root: Path, excludes: tuple[str, ...]) -> list[Path]:
    found = []
    ex = set(excludes)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ex]
        for fn in filenames:
            if fn.endswith((GD_EXT, SCENE_EXT, RES_EXT)):
                found.append(Path(dirpath) / fn)
    return sorted(found)


def cmd_index(args) -> int:
    root = Path(args.root).resolve()
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = root / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    excludes = tuple(args.exclude.split(",")) if args.exclude else DEFAULT_EXCLUDES
    files = gather(root, excludes)
    scripts = [f for f in files if f.suffix == GD_EXT]
    scenes = [f for f in files if f.suffix == SCENE_EXT]
    tres = [f for f in files if f.suffix == RES_EXT]

    doc: dict[str, dict] = {}
    doc_note = "skipped"
    if args.doctool_dir:
        doc = read_doctool(Path(args.doctool_dir))
        doc_note = f"reused {len(doc)} xml"
    elif args.godot:
        dd = out_dir / "_doctool"
        err = run_doctool(root, args.godot, dd)
        if err:
            doc_note = err
        else:
            doc = read_doctool(dd)
            doc_note = f"{len(doc)} xml in {dd.name}/"

    script_data = []
    for f in scripts:
        rel = f.relative_to(root).as_posix()
        try:
            script_data.append(scan_script(f, rel))
        except Exception as exc:  # noqa: BLE001
            script_data.append({"path": rel, "lines": 0, "class_name": None,
                                "extends": None, "funcs": [], "signals": [],
                                "exports": [], "vars": [], "consts": [], "enums": [],
                                "inner_classes": [], "unique_refs": [], "resources": [],
                                "calls": [], "refs": [], "strings": [],
                                "errors": [f"scan: {exc}"]})

    scene_data = [scan_scene(f, f.relative_to(root).as_posix()) for f in scenes]

    # ---- cross-check scanner vs engine parser
    scan_names = {s["path"] for s in script_data}
    doc_names = set(doc)
    only_doc = doc_names - scan_names
    miss_methods, extra_methods = [], []
    for s in script_data:
        d = doc.get(s["path"])
        if not d:
            continue
        a = {f["name"] for f in s["funcs"]}
        b = set(d["methods"])
        miss_methods += sorted(b - a)
        extra_methods += sorted(a - b)

    # ---- render
    def render(level: str, with_lines: bool, scope: str = "") -> str:
        files_in = [s for s in script_data if not scope or s["path"].startswith(scope)]
        dirs: dict[str, list[dict]] = {}
        for s in files_in:
            dirs.setdefault(os.path.dirname(s["path"]) or ".", []).append(s)
        out = ["#GODOT DIGEST level=%s files=%d funcs=%d  (tools/codemap.py)"
               % (level, len(files_in), sum(len(s["funcs"]) for s in files_in)),
               "#f=func(:line) s=signal e=export u=%unique p=preload * =instantiate ! =static"]
        for d in sorted(dirs):
            out.append("== " + d)
            for s in dirs[d]:
                out += render_script_block(s, level, with_lines)
        return "\n".join(out) + "\n"

    variants = [
        ("map.txt", render("full", True)),
        ("map.mid.txt", render("mid", True)),
        ("map.t0.txt", render("t0", False)),
        ("map.scripts-t0.txt", render("t0", False, "scripts/")),
        ("map.scripts-mid.txt", render("mid", True, "scripts/")),
        ("map.scripts-full.txt", render("full", True, "scripts/")),
    ]

    # ---- symbol-level index: one self-describing line per symbol.
    # Purpose: be GREPPED, not read. On-disk size does not matter (only matching
    # lines enter an agent's context), so every line repeats its path and a hit is
    # self-contained. This is what makes a source grep (250 lines) become 3 lines.
    sym = ["#GODOT SYMBOLS  path:line kind name  -- grep this file, do not read it"]
    for s in script_data:
        p = s["path"]
        if s["class_name"]:
            sym.append("%s class_name %s" % (p, s["class_name"]))
        if s["extends"]:
            sym.append("%s extends %s" % (p, s["extends"]))
        for f in s["funcs"]:
            sym.append("%s:%d func %s" % (p, f["line"], f["name"]))
        for x in s["signals"]:
            sym.append("%s:%d signal %s" % (p, x["line"], x["name"]))
        for x in s["exports"]:
            sym.append("%s:%d export %s" % (p, x["line"], x["name"]))
        for x in s["consts"]:
            sym.append("%s:%d const %s" % (p, x["line"], x["name"]))
        for r in s["resources"]:
            sym.append("%s preload %s" % (p, short_res(r["path"])))
    for sc in scene_data:
        for node in sc["nodes"]:
            if node["script"]:
                sym.append("%s node %s -> %s"
                           % (sc["path"], node["name"], short_res(node["script"])))
            if node["instance"]:
                sym.append("%s inst %s -> %s"
                           % (sc["path"], node["name"], short_res(node["instance"])))
    variants.append(("map.sym.txt", "\n".join(sym) + "\n"))

    scene_lines = ["#GODOT SCENES tscn=%d" % len(scene_data),
                   "#indent=depth % =unique_name * =instanced gd=attached script conn=signal connection"]
    for sc in scene_data:
        scene_lines += render_scene_block(sc)
    scene_txt = "\n".join(scene_lines) + "\n"

    # ---- references
    func_names: dict[str, int] = {}
    for s in script_data:
        for f in s["funcs"]:
            func_names[f["name"]] = func_names.get(f["name"], 0) + 1
    resolved = ambiguous = unknown = 0
    for s in script_data:
        for c in s["calls"]:
            n = func_names.get(c["callee"], 0)
            if n == 1:
                resolved += 1
            elif n > 1:
                ambiguous += 1
            else:
                unknown += 1
    classify_strings(script_data)
    refs = build_refs(script_data, scene_data)
    refs_txt = render_refs(refs)
    variants.append(("map.refs.txt", refs_txt))

    for name, txt in variants:
        (out_dir / name).write_text(txt, encoding="utf-8")
    (out_dir / "scenes.txt").write_text(scene_txt, encoding="utf-8")
    (out_dir / "map.refs.txt").write_text(refs_txt, encoding="utf-8")
    (out_dir / "refs.json").write_text(json.dumps(refs, separators=(",", ":")),
                                       encoding="utf-8")

    # ---- report (short stdout only)
    total_chars = 0
    for f in files:
        try:
            total_chars += f.stat().st_size
        except OSError:
            pass

    print("root       : %s" % root)
    print("excluded   : %s" % ",".join(excludes))
    print("files      : gd=%d tscn=%d tres=%d" % (len(scripts), len(scenes), len(tres)))
    print("doctool    : %s" % doc_note)
    print("symbols    : funcs=%d signals=%d exports=%d consts=%d enums=%d inner=%d unique=%d"
          % (sum(len(s["funcs"]) for s in script_data),
             sum(len(s["signals"]) for s in script_data),
             sum(len(s["exports"]) for s in script_data),
             sum(len(s["consts"]) for s in script_data),
             sum(len(s["enums"]) for s in script_data),
             sum(len(s["inner_classes"]) for s in script_data),
             sum(len(s["unique_refs"]) for s in script_data)))
    print("scenes     : nodes=%d scripts=%d instances=%d conns=%d"
          % (sum(len(s["nodes"]) for s in scene_data),
             sum(1 for s in scene_data for n in s["nodes"] if n["script"]),
             sum(len(s["instances"]) for s in scene_data),
             sum(len(s["connections"]) for s in scene_data)))
    print("call edges : total=%d name_resolved=%d ambiguous=%d unresolved=%d"
          % (resolved + ambiguous + unknown, resolved, ambiguous, unknown))
    print("references : total=%d %s" % (len(refs), " ".join(
        "%s=%d" % kv for kv in collections.Counter(r["kind"] for r in refs).most_common(8))))
    print("doctool x  : scanned_with_xml=%d/%d  xml_only=%d  scanner_missing=%d  scanner_extra=%d"
          % (len(doc_names & scan_names), len(scan_names), len(only_doc),
             len(miss_methods), len(extra_methods)))
    if miss_methods:
        print("  scanner missed (first 12): %s" % ",".join(sorted(set(miss_methods))[:12]))
    if extra_methods:
        print("  scanner extra  (first 12): %s" % ",".join(sorted(set(extra_methods))[:12]))
    print("errors     : files_with_errors=%d" % sum(1 for s in script_data if s["errors"]))
    print("source     : chars=%d est_tokens=%d" % (total_chars, total_chars // 4))
    src_tokens = max(1, total_chars // 4)
    for name, txt in variants + [("scenes.txt", scene_txt)]:
        print("out %-20s chars=%-7d est_tokens=%-7d of_source=%.1f%%"
              % (name, len(txt), len(txt) // 4, 100.0 * (len(txt) // 4) / src_tokens))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="codemap", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    ix = sub.add_parser("index", help="build the digest")
    ix.add_argument("--root", default=".")
    ix.add_argument("--out", default=".codemap_probe")
    ix.add_argument("--godot", default="", help="Godot console exe for --doctool")
    ix.add_argument("--doctool-dir", default="", help="reuse an existing doctool XML dir")
    ix.add_argument("--exclude", default="", help="comma list, replaces defaults")
    ix.set_defaults(func=cmd_index)
    rf = sub.add_parser("refs", help="every indexed reference to a symbol")
    rf.add_argument("symbol", nargs="?", default="")
    rf.add_argument("--root", default=".")
    rf.add_argument("--kind", default="")
    rf.add_argument("--limit", type=int, default=60)
    rf.add_argument("--json", action="store_true")
    rf.set_defaults(func=cmd_refs)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
