"""One conversation, read from its transcript.

`history.jsonl` remembers everything you have ever typed and outlives the
transcripts — which is why the sessions index is built from it. But it only
holds your half. The other half survives in
`~/.claude/projects/<project>/<sid>.jsonl`, and only while that file is on
disk, so a conversation is read on demand and never indexed: the largest one
on this machine is 17 MB and you only ever want one at a time.

What comes out is turns, not records. The file interleaves a dozen record
types and splits one reply across many lines; a reader wants *you said this,
Claude said that, and here is what it did in between*.
"""

import glob
import json
import os
import re
import time
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
PROJECTS = HOME / ".claude/projects"

MAX_TURNS = 800          # a runaway session still has to render
MAX_TEXT = 40_000        # per message; nothing real comes close
BRIEF = 150              # one line of what a tool was asked to do

# The same scrubbing the prompt index uses — literally the same list, imported
# rather than copied, because this comment used to claim that and it was not
# true: one provider-token pattern against the index's ten, applied to your
# turns only while the assistant branch assigned its text raw. Measured before
# the fix: 118 of 7,830 assistant text blocks (1.5%) matched the index's
# patterns — 51 emails, 30 opaque blobs, 25 credential assignments, 8
# authorization headers, 3 env lines, 1 connection string — and none was caught.
# A second copy of a security list is a second thing to forget to update, which
# is how the drift happened; there is now one list and one import.
try:
    from workspace import SECRET as SCRUB          # noqa: F401  (one list, not two)
except Exception:                                  # standalone, without the index
    SCRUB = [
        (re.compile(r"\b(sk-[A-Za-z0-9_-]{16,}|[sprk]k_(?:live|test)_[A-Za-z0-9]{10,}"
                    r"|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}"
                    r"|AKIA[0-9A-Z]{12,}|AIza[0-9A-Za-z_-]{20,})"), "[key]"),
    ]


def scrub(s):
    for pat, rep in SCRUB:
        s = pat.sub(rep, s)
    return s


def find(sid):
    """The transcript for a session id, wherever its project directory is."""
    if not re.fullmatch(r"[0-9a-fA-F-]{8,40}", sid or ""):
        return None
    hits = glob.glob(str(PROJECTS / "*" / f"{sid}.jsonl"))
    return Path(hits[0]) if hits else None


# ── what a tool was asked to do, in one line ─────────────────────────────────
FIELD = {
    "Bash": "command", "Read": "file_path", "Write": "file_path",
    "Edit": "file_path", "NotebookEdit": "notebook_path",
    "Grep": "pattern", "Glob": "pattern", "WebFetch": "url",
    "WebSearch": "query", "Skill": "skill", "Task": "description",
    "Agent": "description", "Artifact": "file_path", "SendMessage": "to",
    "ToolSearch": "query", "SendUserFile": "caption",
}


def brief(name, inp):
    if not isinstance(inp, dict):
        return ""
    v = inp.get(FIELD.get(name, ""), "")
    if not v:
        for k in ("description", "prompt", "command", "file_path", "path", "query"):
            if isinstance(inp.get(k), str) and inp[k]:
                v = inp[k]
                break
    if not isinstance(v, str):
        v = json.dumps(v)[:BRIEF]
    v = v.strip().split("\n")[0]
    return scrub(v[:BRIEF])


def short(path, cwd):
    if cwd and path.startswith(cwd + "/"):
        return path[len(cwd) + 1:]
    return path.replace(str(HOME), "~", 1)


def read(sid, path=None):
    """Turns, newest last. Never raises on a malformed line — a transcript that
    was being written while we read it is normal."""
    t0 = time.time()
    p = path or find(sid)
    if not p or not p.is_file():
        return {"id": sid, "error": "no transcript on disk", "turns": []}

    title, cwd = "", ""
    turns = []
    cur = None                      # the claude turn being assembled
    pending = {}                    # tool_use_id → the tool entry awaiting a result
    truncated = False

    def close():
        nonlocal cur
        if cur and (cur["text"] or cur["tools"] or cur["thinking"]):
            turns.append(cur)
        cur = None

    def mark(kind, text=""):
        close()
        turns.append({"who": "mark", "kind": kind, "text": text})

    with p.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            if len(turns) > MAX_TURNS:
                truncated = True
                break
            try:
                d = json.loads(line)
            except Exception:
                continue
            kind = d.get("type")

            if kind == "ai-title":
                title = d.get("aiTitle") or title
                continue
            if not cwd:
                cwd = d.get("cwd") or ""
            if d.get("isSidechain"):
                continue            # a subagent's own conversation, not this one

            if kind == "system":
                if d.get("subtype") == "compact_boundary":
                    mark("compact", "the conversation was compacted here")
                continue

            msg = d.get("message")
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")

            if kind == "user":
                # `promptSource` is what separates something you typed from
                # everything the harness injects wearing your name: pasted
                # images, slash-command echoes, skill preambles, the summary
                # after a compaction. Without it, this half of the transcript
                # is a third noise.
                typed = bool(d.get("promptSource"))
                if isinstance(content, str):
                    text = content.strip()
                    if not text:
                        continue
                    if typed and not bare_command(text):
                        close()
                        turns.append({"who": "you", "t": stamp(d), "text": scrub(text[:MAX_TEXT])})
                        continue
                    said_it(mark, text)
                    continue
                if isinstance(content, list):
                    said = []
                    for b in content:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "tool_result":
                            got = pending.pop(b.get("tool_use_id"), None)
                            if got is not None:
                                got["ok"] = not b.get("is_error")
                            res = d.get("toolUseResult")
                            if isinstance(res, dict) and res.get("type") in ("create", "update"):
                                fp = res.get("filePath") or ""
                                if fp and cur:
                                    cur["wrote" if res["type"] == "create" else "edited"].append(short(fp, cwd))
                        elif b.get("type") == "text":
                            said.append(b.get("text") or "")
                    text = "\n".join(x for x in said if x.strip()).strip()
                    if not text:
                        continue
                    if text.startswith("[Request interrupted"):
                        mark("interrupted", "you interrupted here")
                    elif typed:
                        close()
                        turns.append({"who": "you", "t": stamp(d), "text": scrub(text[:MAX_TEXT])})
                    else:
                        said_it(mark, text)
                continue

            if kind == "assistant" and isinstance(content, list):
                if cur is None:
                    cur = {"who": "claude", "t": stamp(d), "text": "", "thinking": 0,
                           "tools": [], "wrote": [], "edited": []}
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    bt = b.get("type")
                    if bt == "text":
                        chunk = (b.get("text") or "").strip()
                        if not chunk:
                            continue
                        # speaking again after doing something starts a new
                        # bubble: an autonomous stretch is a dozen exchanges,
                        # not one wall of prose
                        if cur["text"] or cur["tools"]:
                            close()
                            cur = {"who": "claude", "t": stamp(d), "text": "", "thinking": 0,
                                   "tools": [], "wrote": [], "edited": []}
                        # scrubbed like your half: this branch used to assign raw
                        cur["text"] = scrub(chunk[:MAX_TEXT])
                    elif bt == "thinking":
                        cur["thinking"] += 1
                    elif bt == "tool_use":
                        entry = {"n": b.get("name") or "?", "b": brief(b.get("name"), b.get("input"))}
                        cur["tools"].append(entry)
                        pending[b.get("id")] = entry
    close()

    # a reply that is only tool calls belongs with the one that explains it
    merged = []
    for t in turns:
        if (t["who"] == "mark" and merged and merged[-1]["who"] == "mark"
                and merged[-1]["text"] == t["text"]):
            continue                    # two records, one event
        if (t["who"] == "claude" and merged and merged[-1]["who"] == "claude"
                and not merged[-1]["text"]):
            prev = merged.pop()
            t["tools"] = prev["tools"] + t["tools"]
            t["thinking"] += prev["thinking"]
            t["wrote"] = prev["wrote"] + t["wrote"]
            t["edited"] = prev["edited"] + t["edited"]
            t["t"] = prev["t"]
        merged.append(t)
    for t in merged:
        if t["who"] == "claude":
            t["wrote"] = sorted(set(t["wrote"]))
            t["edited"] = sorted(set(t["edited"]) - set(t["wrote"]))

    return {"id": sid, "title": title, "project": cwd, "turns": merged,
            "you": sum(1 for t in merged if t["who"] == "you"),
            "claude": sum(1 for t in merged if t["who"] == "claude"),
            "truncated": truncated, "bytes": p.stat().st_size,
            "took": round(time.time() - t0, 2)}


def bare_command(text):
    """`/compact` is plumbing; `/goal, keep going until it is done` is an
    instruction that happens to start with a slash."""
    return text.startswith("/") and len(text) <= 40 and "\n" not in text


def said_it(mark, text):
    """A user record you did not type. Most of it is plumbing and belongs
    nowhere; two kinds are worth a line, because they explain a gap."""
    cmd = re.match(r"<command-name>([^<]+)</command-name>", text)
    name = cmd.group(1).strip() if cmd else (text.split()[0] if bare_command(text) else "")
    if name:
        # a compaction already has a boundary record of its own
        return None if name.startswith("/compact") else mark("command", name)
    if text.startswith("[Image:"):
        return mark("image", "you pasted an image")
    return None


def stamp(d):
    ts = d.get("timestamp") or ""
    try:
        return int(time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")))
    except Exception:
        return 0


if __name__ == "__main__":
    import sys
    out = read(sys.argv[1] if len(sys.argv) > 1 else "")
    out["turns"] = out["turns"][:6]
    print(json.dumps(out, indent=1)[:4000])
