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

A conversation open on the page follows its transcript as it grows, and that
is read from a turn rather than from the end. Every turn carries the byte its
first record's line begins at, and `since` reads from there: the page asks
from where its latest turn began, which takes in that turn as it grows and
every turn after it, and reads no more than they are. What came before that
turn is final — a turn begins on your prompt, on a note, on a mark, or on
Claude speaking again, and by then everything earlier is closed and its tools
have answered — so the turns read from there are the ones a read of the whole
would give from there. A file a turn wrote, and a picture it names, are told
relative to the folder their own record was written in, which a session that
moves between folders changes, so a turn reads the same whichever read it
came from.

Not every record that wears the user's role is the user's. Another session's
message, an agent's report, a background task's notice and the harness's own
notes arrive as `type: user` too, and `voice` says which each is; they become
turns of their own, never yours. The shapes are in `voice`'s comment.

A conversation carries pictures, and a turn says where each one is rather than
carrying it: the byte its record's line begins at, and which of that line's
images it is. `image` serves one by that place and by nothing else, so the page
never names a file. What the session published with the Artifact tool is read
by `artifacts`, from the whole transcript rather than its end, because a page
published early is still the session's.
"""

import base64
import calendar
import glob
import html
import json
import os
import re
import stat
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
    turns = _finish(turns[-MAX_TURNS:], cwd)
    return {"id": sid, "title": title, "project": cwd, "turns": turns,
            "you": sum(1 for t in turns if t["who"] == "you"),
            "claude": sum(1 for t in turns if t["who"] == "claude"),
            "notes": sum(1 for t in turns if t["who"] == "note"),
            "truncated": earlier, "earlier": earlier, "bytes": size,
            "read": size - start, "took": round(time.time() - t0, 2)}


def since(sid, at, path=None):
    """The turns from the one that began at byte `at` to the end of the
    transcript, newest last: what a conversation open on the page reads as
    the transcript grows. `at` is where a turn the page holds began; a place
    where no line begins is refused, and so is one past the end, which is a
    transcript written anew."""
    t0 = time.time()
    p = path or find(sid)
    if not p or not p.is_file():
        return {"id": sid, "error": "no transcript on disk", "turns": []}
    size = p.stat().st_size
    if not isinstance(at, int) or not 0 <= at <= size:
        return {"id": sid, "error": "that place is not in the transcript", "turns": []}
    if at:
        with p.open("rb") as f:
            f.seek(at - 1)
            if f.read(1) != b"\n":
                return {"id": sid, "error": "no line begins there", "turns": []}
    # from the line break before it, which _records passes over as the end of
    # a line that began earlier, so the line at `at` is the first one read
    recs, _ = _records(p, max(0, at - 1), size)
    title, cwd, turns = _turns(recs)
    return {"id": sid, "from": at, "title": title, "turns": _finish(turns, cwd),
            "bytes": size, "read": size - at, "took": round(time.time() - t0, 3)}


def _finish(turns, cwd):
    """Turns as the page gets them: scrubbed, once the cut is made, and each
    picture told by its place and whether it can be shown."""
    looked = {}
    for t in turns:
        for k in ("text", "from"):
            if t.get(k):
                t[k] = scrub(t[k])
        for x in t.get("tools") or ():
            x["b"] = scrub(x["b"])
            if x.get("imgs"):
                x["imgs"] = [_shot(s, cwd, looked, x["n"], x["b"]) for s in x["imgs"]]
        if t.get("imgs"):
            t["imgs"] = [_shot(s, cwd, looked) for s in t["imgs"]]
    return turns


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
            at, pos = pos, pos + len(line)
            top = TOP_TYPE.match(line)
            if top and top.group(1) not in READ:
                continue
            try:
                d = json.loads(line.decode("utf-8", "replace"))
            except Exception:
                continue
            if isinstance(d, dict):
                r = _slim(d, at)
                r["_at"] = at               # its line's first byte, which a turn it begins carries
                out.append(r)
    return out, min(first, end)


def _slim(d, at=0):
    """A record without what no turn shows — a tool's output, a file's
    content, an image's bytes — so a gigabyte of transcript is a few
    megabytes held. What stays of an image is where it is."""
    here = {"cwd": d["cwd"]} if isinstance(d.get("cwd"), str) and d["cwd"] else {}
    ims = [dict(k=im["k"], at=at, i=i, **{x: im[x] for x in ("tid", "path") if x in im},
                **(here if "path" in im else {}))
           for i, im in enumerate(images_of(d))]
    if ims:
        d = dict(d, _im=ims)
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
        turns.append({"who": "mark", "kind": kind, "text": text, "at": here})

    here = 0                        # the byte the record being read begins at
    for d in recs:
        kind = d.get("type")
        here = d.get("_at", 0)

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
            ims = d.get("_im") or []
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
                            # what a tool showed Claude: a screenshot, an image it read
                            shot = [s for s in ims if s["k"] == "tool" and s.get("tid") == b.get("tool_use_id")]
                            if shot:
                                got["imgs"] = shot
                        res = d.get("toolUseResult")
                        if isinstance(res, dict) and res.get("type") in ("create", "update"):
                            fp = res.get("filePath") or ""
                            if fp and cur:
                                cur["wrote" if res["type"] == "create" else "edited"].append(
                                    short(fp, d.get("cwd") or cwd))
                    elif b.get("type") == "text":
                        said.append(b.get("text") or "")
                text = "\n".join(x for x in said if x.strip()).strip()
            pasted = [s for s in ims if s["k"] == "pasted"]
            # The harness's note on an image a tool returned, its size and how
            # it was scaled, follows the tool's result: not a paste, and
            # nothing to show that the tool's own line does not.
            if text.startswith("[Image: original"):
                continue
            # A pasted image's bytes are in your prompt, and a note naming the
            # file it was saved to follows it. The prompt already shows it;
            # the note stands alone only where the prompt carried no image.
            if text.startswith("[Image: source:"):
                last = turns[-1] if turns and cur is None else None
                if not (last and last["who"] == "you" and last.get("imgs")):
                    mark("image", "you pasted an image")
                    src = [s for s in ims if s["k"] == "source"]
                    if src:
                        turns[-1]["imgs"] = src
                continue
            if not text and not pasted:
                continue
            if text.startswith("[Request interrupted"):
                mark("interrupted", "you interrupted here")
                continue
            v = voice(d, text)
            if v == "you":
                if bare_command(text) and not pasted:
                    said_it(mark, text)
                else:
                    close()
                    turns.append({"who": "you", "t": stamp(d), "text": text[:MAX_TEXT], "at": here})
                    if pasted:
                        turns[-1]["imgs"] = pasted
            elif v:
                close()
                turns.append({"who": "note", "t": stamp(d), "kind": v[0], "from": v[1],
                              "about": v[2], "text": v[3][:MAX_TEXT], "at": here})
                shots = [s for s in ims if s["k"] == "path"]
                if shots:
                    turns[-1]["imgs"] = shots
            else:
                said_it(mark, text)
            continue

        if kind == "assistant" and isinstance(content, list):
            if cur is None:
                cur = {"who": "claude", "t": stamp(d), "text": "", "thinking": 0,
                       "tools": [], "wrote": [], "edited": [], "at": here}
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
                               "tools": [], "wrote": [], "edited": [], "at": here}
                    # scrubbed like your half, once the cut is made
                    cur["text"] = chunk[:MAX_TEXT]
                elif bt == "thinking":
                    cur["thinking"] += 1
                elif bt == "tool_use":
                    entry = {"n": b.get("name") or "?", "b": brief(b.get("name"), b.get("input"))}
                    cur["tools"].append(entry)
                    pending[b.get("id")] = entry
            # the pictures Claude names by their path go with the words that name them
            shots = [s for s in d.get("_im") or () if s["k"] == "path"]
            if shots:
                cur.setdefault("imgs", []).extend(shots)
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
            if prev.get("imgs"):
                t["imgs"] = prev["imgs"] + t.get("imgs", [])
            t["thinking"] += prev["thinking"]
            t["wrote"] = prev["wrote"] + t["wrote"]
            t["edited"] = prev["edited"] + t["edited"]
            t["t"], t["at"] = prev["t"], prev["at"]
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
    """When a record was written: its timestamp is UTC, as its Z says."""
    ts = d.get("timestamp") or ""
    try:
        return calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return 0


# ── the pictures in a conversation ───────────────────────────────────────────
# Three ways, read off this machine's transcripts:
#
#   a tool's result   an image block inside a tool_result's content, base64:
#                     Claude read a PNG, or a browser tool returned a screenshot.
#                     The harness follows it with "[Image: original WxH,
#                     displayed at …]", a note of its own and not a paste
#   your paste        an image block beside your prompt's "[Image #1]", base64,
#                     and a record after it, "[Image: source: <path>]", naming
#                     where the harness saved it
#   a path            a screenshot Claude names in its own words, or a subagent
#                     in its report: an absolute path to an image on disk, which
#                     may have gone since
#
# A turn holds each as a place — the byte its record's line begins at and its
# ordinal among that line's images — and `image` serves it by that place alone.
# The page cannot name a file: the bytes come from the record itself, or from a
# path the record's own words name. What `images_of` counts on a line is what
# `image` counts there, because both call it.
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp")     # never SVG: it can carry a script
IMAGE_MAX = 25 * 1024 * 1024
LINE_MAX = 64 * 1024 * 1024
# an absolute path, or one from home, ending on a raster image's extension; not
# the tail of a URL, and not cut out of the middle of a longer word
IMAGE_PATH = re.compile(r"(?<![\w/.~:-])((?:~/|/)[^\s`'\"()<>\[\]{}|*,;]*\.(?:png|jpe?g|gif|webp))(?![\w])",
                        re.I)
PASTE_SOURCE = re.compile(r"\[Image: source: ([^\]\n]+)\]")
MAGIC = ((b"\x89PNG\r\n\x1a\n", "image/png"), (b"\xff\xd8\xff", "image/jpeg"),
         (b"GIF87a", "image/gif"), (b"GIF89a", "image/gif"))


class Withheld(Exception):
    """What a route refuses to serve, with the status it answers and why."""
    def __init__(self, status, why):
        super().__init__(why)
        self.status, self.why = status, why


def paths_in(text):
    """Image paths named in some words, each once, in the order named."""
    out = []
    for m in IMAGE_PATH.finditer(text or ""):
        p = os.path.expanduser(m.group(1))
        if p not in out:
            out.append(p)
    return out


def images_of(d):
    """The images one record holds, in order, as {k, tid?, src?, path?}."""
    if not isinstance(d, dict) or d.get("isSidechain"):
        return []
    msg = d.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    out = []
    if d.get("type") == "assistant" and isinstance(content, list):
        for p in paths_in("\n".join(b.get("text") or "" for b in content
                                    if isinstance(b, dict) and b.get("type") == "text")):
            out.append({"k": "path", "path": p})
    elif d.get("type") == "user":
        blocks = content if isinstance(content, list) else []
        text = content if isinstance(content, str) else "\n".join(
            b.get("text") or "" for b in blocks if isinstance(b, dict) and b.get("type") == "text")
        for b in blocks:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_result" and isinstance(b.get("content"), list):
                for x in b["content"]:
                    if isinstance(x, dict) and x.get("type") == "image" and isinstance(x.get("source"), dict):
                        out.append({"k": "tool", "tid": b.get("tool_use_id"), "src": x["source"]})
            elif b.get("type") == "image" and isinstance(b.get("source"), dict):
                out.append({"k": "pasted", "src": b["source"]})
        for m in PASTE_SOURCE.finditer(text):
            out.append({"k": "source", "path": os.path.expanduser(m.group(1).strip())})
        # a subagent's report names the screenshots it took, as Claude does
        if "<agent-message" in text[:1000]:
            v = voice(d, text.strip())
            if isinstance(v, tuple) and v[0] == "agent":
                out.extend({"k": "path", "path": p} for p in paths_in(v[3]))
    return out


def sniff(data):
    """The image type its first bytes say it is, or None."""
    for head, mime in MAGIC:
        if data.startswith(head):
            return mime
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def look(path):
    """Whether a named image can be shown: ok, gone, big, or not (not an
    image file of a kind this shows)."""
    if not path or not os.path.isabs(path) or not path.lower().endswith(IMAGE_EXT):
        return "not"
    try:
        st = os.stat(path)
    except OSError:
        return "gone"
    if not stat.S_ISREG(st.st_mode):
        return "not"
    return "big" if st.st_size > IMAGE_MAX else "ok"


def _shot(s, cwd, looked, tool="", brief_=""):
    """An image as the page gets it: its place, its kind, what to call it, and
    whether it can be shown. A path is told by its name, never sent back."""
    out = {"at": s["at"], "i": s["i"], "k": s["k"]}
    if "path" in s:
        p = s["path"]
        if p not in looked:
            looked[p] = look(p)
        out["state"] = looked[p]
        out["name"] = scrub(os.path.basename(p))
        out["where"] = scrub(short(p, s.get("cwd") or cwd))
    else:
        out["state"] = "ok"
    if tool:
        out["tool"] = tool
        out["about"] = brief_
    return out


def image(sid, at, i, path=None):
    """One image, by its place in the session's transcript: the line that
    begins at byte `at`, and the `i`th image on it. Returns (bytes, type), or
    raises Withheld saying why not."""
    p = path or find(sid)
    if not p or not p.is_file():
        raise Withheld(404, "no transcript on disk")
    if not isinstance(at, int) or not isinstance(i, int) or at < 0 or i < 0:
        raise Withheld(400, "an image is named by its place in the transcript")
    if at >= p.stat().st_size:
        raise Withheld(404, "that place is past the end of the transcript")
    with p.open("rb") as f:
        if at:
            f.seek(at - 1)
            if f.read(1) != b"\n":
                raise Withheld(404, "no line begins there")
        line = f.readline(LINE_MAX + 1)
    top = TOP_TYPE.match(line)
    if len(line) > LINE_MAX or (top and top.group(1) not in READ):
        raise Withheld(404, "no turn is read from that line")
    try:
        d = json.loads(line.decode("utf-8", "replace"))
    except Exception:
        raise Withheld(404, "that line is not a record")
    ims = images_of(d)
    if i >= len(ims):
        raise Withheld(404, "no such image on that line")
    im = ims[i]
    if "src" in im:
        src = im["src"]
        if src.get("type") != "base64" or not isinstance(src.get("data"), str):
            raise Withheld(415, "not an image carried in the transcript")
        if len(src["data"]) > IMAGE_MAX * 4 // 3 + 4:
            raise Withheld(413, "too large to show")
        try:
            data = base64.b64decode(src["data"])
        except Exception:
            raise Withheld(415, "not an image carried in the transcript")
    else:
        state = look(im["path"])
        if state != "ok":
            raise Withheld({"gone": 404, "big": 413}.get(state, 415),
                           {"gone": "that file is no longer on disk", "big": "too large to show"}
                           .get(state, "not an image file"))
        with open(im["path"], "rb") as f:
            data = f.read(IMAGE_MAX + 1)
        if len(data) > IMAGE_MAX:
            raise Withheld(413, "too large to show")
    mime = sniff(data)
    if not mime:
        raise Withheld(415, "not an image file")
    return data, mime


# ── what the session published ───────────────────────────────────────────────
# Claude Code's Artifact tool publishes a page to claude.ai. Its call names the
# local file (`file_path`), an `action` (none, or "publish", for a publish) and,
# when it updates one published from another session, its `url`; its result's
# `toolUseResult` holds the published `url`, the `path`, the published `title`
# and a `seq` counting versions, and its text says "Published <path> at <url>".
# An update keeps the url, sometimes from another file, so an artifact is its
# url. A call that failed, or that only read, listed, opened or uploaded an
# asset, published nothing. Read off this machine's transcripts on 2.1.309.
ARTIFACT_URL = re.compile(r"https://claude\.ai/(?:code/)?artifact/[A-Za-z0-9_-]+")
PAGE_EXT = (".html", ".htm", ".md")
PAGE_MAX = 16 * 1024 * 1024        # the Artifact tool's own limit on a page
SOURCE_MAX = 2 * 1024 * 1024       # what a source view is sent of one
STALE = 2000                       # lines a call waits for its result


class Published:
    """The artifacts a session published, one per artifact however often it
    was published again, fed one line at a time. Lines that cannot matter are
    passed over unparsed."""

    def __init__(self):
        self.calls = {}                 # tool_use id → the call, until its result is read
        self.arts = {}                  # url → the artifact, in the order first published
        self.seen = 0

    def feed(self, line):
        b = isinstance(line, bytes)
        self.seen += 1
        if (b'"name":"Artifact"' if b else '"name":"Artifact"') in line:
            d = self._parse(line)
            if d and d.get("type") == "assistant" and not d.get("isSidechain"):
                self._call(d)
        elif self.calls and (b'"tool_use_id"' if b else '"tool_use_id"') in line:
            ids = [k for k in self.calls if (k.encode() if b else k) in line]
            if ids:
                d = self._parse(line)
                if d and d.get("type") == "user":
                    self._result(d)
            for k in [k for k, c in self.calls.items() if self.seen - c["seen"] > STALE]:
                del self.calls[k]

    @staticmethod
    def _parse(line):
        try:
            d = json.loads(line.decode("utf-8", "replace") if isinstance(line, bytes) else line)
            return d if isinstance(d, dict) else None
        except Exception:
            return None

    def _call(self, d):
        for b in (d.get("message") or {}).get("content") or ():
            if not (isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Artifact"):
                continue
            inp = b.get("input") if isinstance(b.get("input"), dict) else {}
            if (inp.get("action") or "publish") != "publish" or inp.get("asset"):
                continue
            fp = inp.get("file_path") if isinstance(inp.get("file_path"), str) else ""
            if isinstance(b.get("id"), str):
                self.calls[b["id"]] = {"file": fp, "t": stamp(d), "seen": self.seen}

    def _result(self, d):
        for b in (d.get("message") or {}).get("content") or ():
            if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                continue
            c = self.calls.pop(b.get("tool_use_id"), None)
            if c is None or b.get("is_error"):
                continue
            res = d.get("toolUseResult") if isinstance(d.get("toolUseResult"), dict) else {}
            url = res.get("url") if isinstance(res.get("url"), str) else ""
            if not url:
                said = b.get("content")
                said = said if isinstance(said, str) else " ".join(
                    x.get("text") or "" for x in said or () if isinstance(x, dict))
                m = re.match(r"Published .* at (https://\S+)", said or "")
                url = m.group(1) if m else ""
            m = ARTIFACT_URL.match(url or "")
            if not m:
                continue
            url = m.group(0)
            a = self.arts.setdefault(url, {"url": url, "file": "", "title": "", "n": 0,
                                           "first": stamp(d) or c["t"]})
            a["n"] += 1
            a["last"] = stamp(d) or c["t"]
            fp = res.get("path") if isinstance(res.get("path"), str) else ""
            a["file"] = fp or c["file"] or a["file"]
            if isinstance(res.get("title"), str) and res["title"].strip():
                a["title"] = res["title"].strip()

    def out(self):
        return list(self.arts.values())


def _line_start(f, pos):
    """The byte the line holding `pos` begins at."""
    while pos > 0:
        back = min(pos, 1 << 20)
        f.seek(pos - back)
        i = f.read(back).rfind(b"\n")
        if i >= 0:
            return pos - back + i + 1
        pos -= back
    return 0


def published(p):
    """Every artifact a transcript published. A gigabyte is read in a second:
    it is searched in large pieces for the tool's name, and only the lines
    that hold it, and the few after each where its result is, are parsed."""
    pub, needle = Published(), b'"name":"Artifact"'
    starts, done, size = [], 0, p.stat().st_size
    with p.open("rb") as f:
        tail = b""
        while done < size:
            chunk = f.read(16 << 20)
            if not chunk:
                break
            buf, base = tail + chunk, done - len(tail)
            i = buf.find(needle)
            while i >= 0:
                starts.append(base + i)
                i = buf.find(needle, i + 1)
            done += len(chunk)
            tail = buf[-(len(needle) - 1):]
        lines = []
        for hit in starts:
            at = _line_start(f, hit)
            if not lines or lines[-1] != at:
                lines.append(at)
        for at in lines:
            f.seek(at)
            pub.feed(f.readline(LINE_MAX))
            # its result follows within a few lines, read until it is found
            n = 0
            while pub.calls and n < STALE:
                line = f.readline(LINE_MAX)
                if not line:
                    break
                n += 1
                if needle not in line:
                    pub.feed(line)
            pub.calls.clear()
    return pub.out()


def page_title(path):
    """What a page calls itself: its <title>, or a Markdown page's first heading."""
    try:
        with open(path, "rb") as f:
            head = f.read(256 * 1024).decode("utf-8", "replace")
    except OSError:
        return ""
    m = (re.search(r"<title[^>]*>(.*?)</title>", head, re.S | re.I) if not path.endswith(".md")
         else re.search(r"^#\s+(.+)$", head, re.M))
    return re.sub(r"\s+", " ", html.unescape(m.group(1))).strip()[:200] if m else ""


def _source_state(path):
    """Whether a published file can be opened as its source: ok, gone, big, not."""
    if not path or not os.path.isabs(path) or not path.lower().endswith(PAGE_EXT):
        return "not"
    try:
        st = os.stat(path)
    except OSError:
        return "gone"
    if not stat.S_ISREG(st.st_mode):
        return "not"
    return "big" if st.st_size > PAGE_MAX else "ok"


def artifacts(sid, path=None):
    """The artifacts a session published, for its view. Each is numbered by
    the order it was first published in, which a growing transcript keeps, and
    that number is how the page asks for its source."""
    t0 = time.time()
    p = path or find(sid)
    if not p or not p.is_file():
        return {"id": sid, "error": "no transcript on disk", "artifacts": []}
    out = []
    for n, a in enumerate(published(p)):
        state = _source_state(a["file"])
        title = (page_title(a["file"]) if state == "ok" else "") or a["title"] or a["url"].rsplit("/", 1)[-1]
        out.append({"n": n, "url": a["url"], "title": scrub(title), "count": a["n"],
                    "first": a["first"], "last": a["last"], "source": state,
                    "file": scrub(a["file"].replace(str(HOME), "~", 1))})
    return {"id": sid, "artifacts": out, "took": round(time.time() - t0, 2)}


def artifact_source(sid, n, path=None):
    """The source of the `n`th artifact a session published, as text. The
    file is the one its Artifact call named; the page names only the number."""
    p = path or find(sid)
    if not p or not p.is_file():
        raise Withheld(404, "no transcript on disk")
    if not isinstance(n, int) or n < 0:
        raise Withheld(400, "an artifact is named by its number in the session")
    arts = published(p)
    if n >= len(arts):
        raise Withheld(404, "the session published no such artifact")
    a = arts[n]
    state = _source_state(a["file"])
    if state != "ok":
        raise Withheld({"gone": 404, "big": 413}.get(state, 415),
                       {"gone": "its file is no longer on disk", "big": "its file is too large to show"}
                       .get(state, "it was published from no page file"))
    with open(a["file"], "rb") as f:
        raw = f.read(SOURCE_MAX + 1)
    size = os.path.getsize(a["file"])
    return {"id": sid, "n": n, "url": a["url"], "count": a["n"], "last": a["last"],
            "title": scrub(page_title(a["file"]) or a["title"] or a["url"].rsplit("/", 1)[-1]),
            "file": scrub(a["file"].replace(str(HOME), "~", 1)),
            "kind": "md" if a["file"].lower().endswith(".md") else "html",
            "text": raw[:SOURCE_MAX].decode("utf-8", "replace"), "bytes": size,
            "cut": size > SOURCE_MAX}


if __name__ == "__main__":
    import sys
    out = read(sys.argv[1] if len(sys.argv) > 1 else "")
    out["turns"] = out["turns"][:6]
    print(json.dumps(out, indent=1)[:4000])
