# Platform — macOS, and what that means

**Status: closed.** This is a decision, not a *not yet*. Open question 4 was
answered on 2026-08-24: rubricator targets macOS. Nothing here is a roadmap and
nothing below promises a port. It exists so that the first question a Linux
visitor asks is answered on the page rather than in an issue, and so that the
six places the decision is actually load-bearing are written down once instead
of being rediscovered every time someone touches `bin/md`.

Written as part of **O4**. See [`tasks.md`](tasks.md).

## Why it is not portable, in one line

Rubricator is a browser page plus a local process, and the *page* is portable —
it is HTML, and it renders in anything. What is not portable is the six ways the
process talks to the desktop around it. Five of the six degrade to something
that works; one does not degrade at all.

## The six

| # | Capability | How it is done | On Linux |
|---|---|---|---|
| 1 | **App window** | `open -na "Google Chrome.app" --args --app=<url>` | Chrome's `--app=` flag is identical; the launcher is not. `google-chrome --app=<url>` is the whole difference. Every call site already falls back to plain `open`, so the honest port is a two-line `_open_url`. **Degrades cleanly today** — without Chrome you get a normal tab. |
| 2 | **Closing the window when review ends** | `osascript` telling Chrome to close the tab whose URL matches | No equivalent. Chrome exposes no remote close on Linux without the DevTools protocol, which means a debugging port, which means a second security surface for a cosmetic gain. **Would not be ported.** The window stays open; the verdict is already delivered. |
| 3 | **Native folder chooser** | `osascript` → `choose folder` | `zenity --file-selection --directory`, `kdialog`, or nothing. Three answers depending on desktop, and the failure mode of guessing wrong is a hang. The page would fall back to typing a path. |
| 4 | **Opening a terminal on a session** | A `.command` file, dispatched by LaunchServices to whichever terminal the user has set | The `.command` convention is macOS-only. Linux has no user-level "my terminal" registry that every terminal honours — `x-terminal-emulator` exists on Debian and nowhere else reliably. This is the one that would need a hardcoded terminal table, which is exactly what the macOS path avoids. |
| 5 | **PDF and Word extraction** | `textutil` for Word; PDFKit through the JXA ObjC bridge for PDF | Both are macOS frameworks. The Linux equivalents exist and are good — `pdftotext` (poppler), `pandoc` or LibreOffice headless — but they are **installed dependencies**, and shipping none is why extraction currently adds nothing to install. A port trades that property away. |
| 6 | **Checksums** | `shasum -a 256`, falling back to `sha256sum` | Already portable: `bin/md` accepts either and **dies if neither is present** rather than installing an unverified library. Nothing to do. |

## What a port would actually cost

Rows 1, 3 and 6 are small. Row 5 is a dependency decision, not a code problem.
Row 4 is genuinely unpleasant. Row 2 would be dropped.

So the estimate is not *large*, and the reason for not doing it is not the size:
it is that a port has no user. Adding an untested second platform to a tool one
person runs converts a working program into two half-tested ones.

## The rule that goes with it

**Do not extract `share/platform.py`.** A seam built before the port it must
accommodate is the wrong seam — it gets drawn around today's call sites rather
than around the differences that turn out to matter, and then the port has to
break it anyway. The four Chrome guard sites were unified in O4 because they had
already drifted apart *within macOS*, which is a real defect with a real symptom;
that is a different thing from abstraction on speculation.

If someone does port it, this table is the checklist, and the first commit
should delete this paragraph.
