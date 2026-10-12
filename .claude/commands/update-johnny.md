---
description: Record everything learned in this session (from the last update until now) into the app knowledge ledger, CLAUDE.md and memory, then commit
argument-hint: [push] [extra notes to record]
---

You are being asked to **update the app's knowledge** with everything that
happened from the **previous update time until right now**, in detail, so the
next `/johnny` refresh (in this or a future session) knows it. Arguments:
`$ARGUMENTS` (the word `push` means push the commit afterwards; any other
text is extra notes the user wants recorded verbatim in spirit).

## Steps

1. **Get the window.** Read the header of `.claude/johnny/KNOWLEDGE.md`:
   `Last updated` (ISO timestamp) and `Last commit covered` (sha). Get the
   current time with `date -Iseconds` and `git rev-parse --short HEAD`.
   The window to document is `Last updated → now`, `<sha>..HEAD`, plus any
   uncommitted work. If the ledger is missing, create it (first run: window =
   first commit → now).

2. **Gather evidence — do not rely on memory of the conversation alone.**
   - `git log <sha>..HEAD --stat --format="%h %ad %an %s" --date=iso` and, for
     each non-trivial commit, `git show --stat` + the important diffs.
   - `git status --short` / `git diff --stat` for uncommitted changes.
   - This conversation: decisions and *why*, errors hit and their root causes,
     dead ends, measurements and benchmark numbers, things verified vs
     assumed, user preferences/corrections, environment facts about the user's
     machine, and anything left undone.
   - The auto-memory directory (`MEMORY.md` + linked files) for what is
     already stored there.

3. **Verify before you write.** Every file, script, flag, function or number you
   are about to record must be checked against the code or a command result
   (`Grep`/`Glob`/`Read`, or re-run a quick command). Do not record a
   claim you could not confirm; if it is unconfirmed, record it explicitly as
   *unverified*.

4. **Add one new entry at the TOP of the ledger's Timeline**, headed
   `## <ISO now> — <short title> (covers <old sha>..<new sha>, since <old timestamp>)`,
   with these sub-sections (omit a sub-section only if truly empty):
   - **What changed** — by area, with file paths and the commit shas.
   - **Why / decisions** — the reasoning, alternatives rejected.
   - **Problems → root cause → fix** — symptom, cause, fix, how it was confirmed.
   - **Measurements & results** — numbers with units/conditions (timings,
     accuracy, sizes, test counts).
   - **Verified vs not verified** — be honest about what was never run.
   - **Traps / gotchas** — things that will bite the next person or session.
   - **User preferences & machine facts** — new or changed.
   - **Open items / next steps.**
   Be detailed and factual. **Never record secrets** (API keys, tokens) **or
   any content of the user's private documents/scans/OCR text** — describe
   behavior and aggregate numbers only.

5. **Update the header** of the ledger: `Last updated: <ISO now>`,
   `Last commit covered: <HEAD sha>` (if you are about to commit, that is the
   sha *before* your own docs commit; say so), and refresh the ledger's
   evergreen sections ("Standing preferences", "Environment facts", "Open
   items") so they describe the *current* state, not history.

6. **Reconcile the canonical docs.** Compare what you learned with `CLAUDE.md`
   (and `README.md` if user-facing behavior changed). Fix anything now false
   or missing — test counts, flags, file lists, build steps, the "Last
   verified" paragraph — and add a dated build-log entry only if something
   was actually run and verified. Keep CLAUDE.md the *current-truth* document
   and the ledger the *history/why* document; do not duplicate long text
   between them (link by section name instead).

7. **Update auto-memory** for durable user-level knowledge (preferences,
   feedback, corrections, who the user is) using the memory system's normal
   file + `MEMORY.md` index rules; update or delete entries that turned out
   wrong. Do not store things derivable from the code or git history.

8. **Commit.** Stage only the files you changed here (the ledger, CLAUDE.md,
   README.md if touched — never unrelated working-tree noise), and commit with a
   **single-line message** (the user requires one-line commit messages),
   e.g. `Update johnny knowledge ledger and docs through <short summary>`.
   Push **only** if `$ARGUMENTS` contains `push`; otherwise say it is
   committed locally and not pushed.

9. **Report** in ≤10 lines: the window covered (old → new timestamp and
   shas), the main things recorded, which docs/memory files changed, the
   commit sha, and anything you could not verify.
