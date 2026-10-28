"""One conversation, read from its transcript.

`history.jsonl` remembers everything you have ever typed and outlives the
transcripts — which is why the sessions index is built from it. But it only
holds your half. The other half survives in
`~/.claude/projects/<project>/<sid>.jsonl`, and only while that file is on
disk, so a conversation is read on demand and never indexed.

What comes out is turns, not records. The file interleaves a dozen record
types and splits one reply across many lines; a reader wants *you said this,
Claude said that, and here is what it did in between*.

It is read from the end. A working session's transcript runs past a gigabyte
— most of it the requests Claude Code logs and the output of tools — and what
you open a session for is where it stands now, so the latest turns are the
ones kept: the last eight megabytes first, then as much more as the turns
found so far say it takes, until there are `MAX_TURNS` of them or the file is
read. Records of a kind no turn is made of are skipped by their first bytes,
unparsed, and a tool's output is dropped as soon as it is parsed. On this
machine's largest, 1.4 GB, the last 800 turns are its last 686 MB, read in
1.6 s; a 160 MB one is read whole in 0.8 s.

Not every record that wears the user's role is the user's. Another session's
message, an agent's report, a background task's notice and the harness's own
notes arrive as `type: user` too, and `voice` says which each is; they become
turns of their own, never yours. The shapes are in `voice`'s comment.
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
TAIL_FIRST = 8 * 1024 * 1024
# a record that opens on a type no turn is made of — the logged API requests,
# the snapshots, the mode lines — is skipped before it is parsed
TOP_TYPE = re.compile(rb'\{"type":"([a-z-]+)"')
READ = {b"user", b"assistant", b"system", b"ai-title"}

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
    return v[:BRIEF]                      # scrubbed with the turn it belongs to


def short(path, cwd):
    if cwd and path.startswith(cwd + "/"):
        return path[len(cwd) + 1:]
    return path.replace(str(HOME), "~", 1)


def read(sid, path=None):
    """The latest turns, newest last. Never raises on a malformed line — a
    transcript that was being written while we read it is normal."""
    t0 = time.time()
    p = path or find(sid)
    if not p or not p.is_file():
        return {"id": sid, "error": "no transcript on disk", "turns": []}

    # backwards, a chunk at a time and each byte once: a chunk's records go in
    # front of the ones already read, and the turns are made again from them
    # all, which is cheap because nothing is scrubbed until the cut is made.
    # Each chunk is as long as the turns found so far say the rest will take.
    size = p.stat().st_size
    end, n, recs = size, TAIL_FIRST, []
    while True:
        start = max(0, end - n)
        got, end = _records(p, start, end)
        recs = got + recs
        title, cwd, turns = _turns(recs)
        if start == 0 or len(turns) > MAX_TURNS:
            break
        each = (size - start) / max(len(turns), 1)
        n = max(TAIL_FIRST, min(int((MAX_TURNS + 1 - len(turns)) * each * 1.3), 4 * (size - start)))

    # A window that starts mid-file stops only once it holds more turns than
    # are kept, so its first one, which may be the end of a turn, is never
    # among them; that there were earlier ones is said rather than hidden.
    earlier = len(turns) > MAX_TURNS
    turns = turns[-MAX_TURNS:]
    for t in turns:
        for k in ("text", "from"):
            if t.get(k):
                t[k] = scrub(t[k])
        for x in t.get("tools") or ():
            x["b"] = scrub(x["b"])
    return {"id": sid, "title": title, "project": cwd, "turns": turns,
            "you": sum(1 for t in turns if t["who"] == "you"),
            "claude": sum(1 for t in turns if t["who"] == "claude"),
            "notes": sum(1 for t in turns if t["who"] == "note"),
            "truncated": earlier, "earlier": earlier, "bytes": size,
            "read": size - start, "took": round(time.time() - t0, 2)}


def _records(p, start, end):
    """The records on the lines that begin in [start, end), each cut down to
    what a turn is made of, and the offset the first of those lines begins at
    — where the next chunk back has to end."""
    out = []
    with p.open("rb") as f:
        f.seek(start)
        if start:
            f.readline()            # the end of a line that began before `start`
        first = pos = f.tell()
        while pos < end:
            line = f.readline()
            if not line:
                break
            pos += len(line)
            top = TOP_TYPE.match(line)
            if top and top.group(1) not in READ:
                continue
            try:
                d = json.loads(line.decode("utf-8", "replace"))
            except Exception:
                continue
            if isinstance(d, dict):
                out.append(_slim(d))
    return out, min(first, end)


def _slim(d):
    """A record without what no turn shows — a tool's output, a file's
    content — so a gigabyte of transcript is a few megabytes held."""
    msg = d.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    if d.get("type") == "user" and isinstance(content, list):
        keep = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                keep.append({"type": "tool_result", "tool_use_id": b.get("tool_use_id"),
                             "is_error": b.get("is_error")})
            elif isinstance(b, dict) and b.get("type") == "text":
                keep.append(b)
        res = d.get("toolUseResult")
        d = dict(d, message=dict(msg, content=keep),
                 toolUseResult={"type": res.get("type"), "filePath": res.get("filePath")}
                 if isinstance(res, dict) else None)
    elif d.get("type") == "assistant" and isinstance(content, list):
        keep = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                field = FIELD.get(b.get("name"), "")
                inp = {k: (v[:BRIEF * 4] if isinstance(v, str) else v) for k, v in inp.items()
                       if k == field or k in ("description", "prompt", "command", "file_path", "path", "query")}
                keep.append({"type": "tool_use", "id": b.get("id"), "name": b.get("name"), "input": inp})
            elif isinstance(b, dict) and b.get("type") == "thinking":
                keep.append({"type": "thinking"})
            else:
                keep.append(b)
        d = dict(d, message=dict(msg, content=keep))
    return d


def _turns(recs):
    """Records, in the order they were written, as turns."""
    title, cwd = "", ""
    turns = []
    cur = None                      # the claude turn being assembled
    pending = {}                    # tool_use_id → the tool entry awaiting a result

    def close():
        nonlocal cur
        if cur and (cur["text"] or cur["tools"] or cur["thinking"]):
            turns.append(cur)
        cur = None

    def mark(kind, text=""):
        close()
        turns.append({"who": "mark", "kind": kind, "text": text})

    for d in recs:
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
            if isinstance(content, str):
                text = content.strip()
            else:
                said = []
                for b in content if isinstance(content, list) else ():
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
                continue
            v = voice(d, text)
            if v == "you":
                if bare_command(text):
                    said_it(mark, text)
                else:
                    close()
                    turns.append({"who": "you", "t": stamp(d), "text": text[:MAX_TEXT]})
            elif v:
                close()
                turns.append({"who": "note", "t": stamp(d), "kind": v[0], "from": v[1],
                              "about": v[2], "text": v[3][:MAX_TEXT]})
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
                    # scrubbed like your half, once the cut is made
                    cur["text"] = chunk[:MAX_TEXT]
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
    return title, cwd, merged


# ── whose words a user record holds ──────────────────────────────────────────
# Everything that reaches a session arrives as a record of `type: user`, and
# `promptSource` alone does not say whose it is: on 2.1.289–2.1.309 a background
# task's notice and another session's message both carry `promptSource:
# "system"`, which reads as typed to anything that only asks whether the field
# is there. What each looked like, read from this machine's transcripts:
#
#   another session   "Another Claude session sent a message:\n<cross-session-message
#                     from="uds:/tmp/cc-socks/<pid>.sock" from-name="sandburg-9e"
#                     from-mode="…">…</cross-session-message>\n\n<the harness's warning>",
#                     origin.kind "peer", origin.name the sender's name, isMeta
#   an agent          the same opening, then <agent-message from="<task id>">
#                     [Subagent hand-back] <a preamble> The report follows:\n  <the
#                     report, each line indented two spaces></agent-message>,
#                     origin.kind "peer", origin.name the agent's type, origin.handback
#   a task's notice   "<task-notification>…<status>…</status><summary>…</summary>…",
#                     origin.kind "task-notification"
#   the harness       a compaction's summary ("This session is being continued from a
#                     previous conversation…", isCompactSummary), <system-reminder>,
#                     <local-command-caveat>, <local-command-stdout>, a scheduled
#                     wake-up (turnOrigin "scheduled") and the continuation after a
#                     usage limit (origin.kind "auto-continuation")
#
# None of them is in history.jsonl, which holds only what was typed into the
# prompt box; `harness_text` is the same test for that file, so a later build
# that wrote one there would still not name a session or answer a search.
HARNESS = ("Another Claude session sent a message", "<cross-session-message",
           "<agent-message", "<task-notification>", "<system-reminder>",
           "<local-command-caveat>", "<local-command-stdout>", "<local-command-stderr>",
           "This session is being continued from a previous conversation")


def harness_text(text):
    """Whether these words were written by the harness, not typed by you."""
    return isinstance(text, str) and text.lstrip().startswith(HARNESS)


def _attr(text, name):
    m = re.search(r'\b' + re.escape(name) + r'="([^"]{0,200})"', text[:2000])
    return m.group(1) if m else ""


def _inner(text, tag):
    """What a tag holds; the text as it is when the tag is not there."""
    m = re.search(r"<" + tag + r"\b[^>]*>\n?(.*?)\n?</" + tag + r">", text, re.S)
    return m.group(1) if m else text


def voice(d, text):
    """'you' for a record you typed; for one that only wears your role, what it
    is — (kind, who it is from, what it is, the words); None for plumbing,
    which `said_it` decides about."""
    o = d.get("origin") if isinstance(d.get("origin"), dict) else {}
    t = text.lstrip()
    if (t.startswith(("Another Claude session sent a message", "<cross-session-message",
                      "<agent-message")) or o.get("kind") == "peer"):
        if "<agent-message" in t[:400] or o.get("handback"):
            body = _inner(t, "agent-message")
            if "The report follows:\n" in body[:2000]:
                body = body.split("The report follows:\n", 1)[1]
            body = "\n".join(ln[2:] if ln.startswith("  ") else ln for ln in body.split("\n"))
            return ("agent", o.get("name") or "an agent", "an agent's report", body.strip())
        who = _attr(t, "from-name") or o.get("name") or ""
        return ("peer", who or "another session", "another session",
                _inner(t, "cross-session-message").strip())
    if t.startswith("<task-notification>") or o.get("kind") == "task-notification":
        summary = _inner(t, "summary") if "<summary>" in t else ""
        status = _inner(t, "status") if "<status>" in t else ""
        return ("task", "", "a task's notice" + (" · " + status.strip() if status else ""),
                (summary or re.sub(r"<[^>]+>", " ", t)).strip())
    if d.get("isCompactSummary") or t.startswith("This session is being continued"):
        return ("system", "", "the summary it was continued from", t)
    for tag, about in (("system-reminder", "a system reminder"),
                       ("local-command-caveat", "a local command"),
                       ("local-command-stdout", "a local command's output"),
                       ("local-command-stderr", "a local command's output")):
        if t.startswith("<" + tag + ">"):
            return ("system", "", about, _inner(t, tag).strip())
    # what is left is yours when Claude Code says it came from the prompt box —
    # typed, a suggestion you accepted, one queued while it worked — and the
    # harness's own when it says `system`
    if d.get("promptSource") == "system" or d.get("isMeta"):
        if o.get("kind") == "auto-continuation" or d.get("turnOrigin") in ("scheduled", "auto_continuation"):
            about = ("a scheduled prompt" if d.get("turnOrigin") == "scheduled"
                     else "a continuation after a usage limit")
            return ("system", "", about, t)
        return None
    return "you" if d.get("promptSource") else None


def bare_command(text):
    """`/compact` is plumbing; `/goal, keep going until it is done` is an
    instruction that happens to start with a slash."""
    return text.startswith("/") and len(text) <= 40 and "\n" not in text


def said_it(mark, text):
    """A user record you did not type. Most of it is plumbing and belongs
    nowhere; two kinds are worth a line, because they explain a gap."""
    # the record opens on <command-message>, and <command-name> follows it
    cmd = re.search(r"<command-name>([^<]+)</command-name>", text[:400])
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
