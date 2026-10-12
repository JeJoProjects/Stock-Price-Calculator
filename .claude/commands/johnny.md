---
description: Refresh Claude's full knowledge of this app (docs, ledger, memory, git changes since the last update) and give a briefing
argument-hint: [verify | <topic, e.g. ocr, build, backend>]
allowed-tools: Read, Glob, Grep, Bash(git log:*), Bash(git status:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(date:*), Bash(ls:*)
---

You are being asked to **refresh your knowledge of this app** (Stock Screener —
Flutter + Dart desktop app: profit calculator, Finviz/Yahoo screener, Finnhub +
Alpha Vantage chart, batch OCR tab) so you can work on it with full context.
This command is **read-only**: do not edit, stage, commit or run builds
(unless the argument is `verify`, see step 5).

Argument given: `$ARGUMENTS` (empty = general refresh).

## Steps

1. **Read the knowledge sources, in this order, completely:**
   - `CLAUDE.md` (canonical architecture, build, OCR pipeline, gotchas, logs)
   - `.claude/johnny/KNOWLEDGE.md` (the living ledger: timeline of what changed
     and why, root causes, measurements, user preferences, open items; its
     header holds `Last updated` and `Last commit covered`)
   - `README.md`
   - the auto-memory index `MEMORY.md` and every file it links (user
     preferences/feedback — follow them)
   If the argument names a topic, additionally read the code behind it
   (e.g. `ocr` → `app/lib/ocr/*`, `app/lib/widgets/ocr_panel.dart`,
   `app/tool/ocr_eval.dart`, `pyocr/*`, `scripts/build_ocr_sidecar.bat`,
   `app/test/ocr/*`).

2. **Find what changed since the ledger was last updated.** Take
   `Last commit covered` and `Last updated` from the ledger header, then run:
   `git log <sha>..HEAD --stat --format="%h %ad %s" --date=short`,
   `git status --short`, and `git diff --stat` for uncommitted work.
   Any commit or uncommitted change **not** described in the ledger is
   *unrecorded knowledge* — read those diffs (`git show --stat <sha>`, then the
   relevant files) so you actually understand them, not just their titles.

3. **Check the knowledge is still true.** Spot-check, by `Glob`/`Grep`, that
   the files, scripts, flags and symbols CLAUDE.md and the ledger name still
   exist (a handful of the most load-bearing ones is enough). Trust the code
   over the docs when they disagree, and list every discrepancy.

4. **Brief the user** in at most ~25 lines, in this shape:
   - **App in one paragraph** — what it is and the three local processes.
   - **How to build / run / test** — the exact commands and the Windows gotchas
     that bite (pub cache, SDK path with spaces, locked exes).
   - **Current state** — branch, HEAD, clean/dirty, last verified date and
     what was/wasn't verified.
   - **Since the last update** — unrecorded commits/changes (or "nothing new").
   - **Standing rules** from the user's memory (e.g. one-line commits, never
     commit private documents, ask before pushing unless told to).
   - **Known traps & open items** from the ledger.
   - **Stale docs found** (if any) and a recommendation to run
     `/update-johnny` when there is unrecorded knowledge.
   Be concrete; do not paste whole files.

5. **Only if the argument is `verify`:** additionally run, from `app/`,
   `flutter analyze` and `flutter test` (Flutter SDK is `C:\src\flutter\bin\flutter.bat`
   on this machine, with `PUB_CACHE` set to `<repo>\external\pub_cache`; see
   CLAUDE.md > How to Build & Run) and report pass/fail counts next to the
   documented numbers. This is the only case in which you may run builds.

Never read or quote the user's private scanned documents or OCR output; they
are not part of this app's knowledge (see memory: private documents).
