# Johnny knowledge ledger — Stock Screener app

Living history of *what changed and why* in this repo, kept by `/update-johnny`
and read by `/johnny`. **CLAUDE.md is the current-truth reference** (architecture,
build, OCR pipeline); this ledger is the *history, reasoning and traps*. Don't
duplicate long text from CLAUDE.md here — name the section instead.

Last updated: 2026-10-12T22:03:16+02:00
Last commit covered: 321c049 (HEAD just before the docs commit that records this update)

Rules for editing: newest Timeline entry first; every claim verified against
code/commands or marked *unverified*; no secrets; **no content of the user's
private documents or OCR output** (aggregate numbers and behavior only).

---

## Standing preferences (the user's — follow these)

- **Commit messages: exactly one line**, no body, no Co-Authored-By trailer.
  Stage only files relevant to the change (skip line-ending-only noise and
  `pub get`-regenerated plugin registrants, which show as modified).
- **Push only when asked** ("commit and push …"); a plain "commit" means local.
- **Private documents are private.** The user's scans (insurance statements,
  certificates) live in OneDrive; never commit them or their OCR text, never
  leave scratch copies (delete after analysis), use synthetic fixtures in tests.
- Wants work **finished end-to-end and verified**, not described: build it, run
  it, test it, then report. Likes numbers (before/after, timings, accuracy).
  Auto mode: act on sensible defaults, ask only when truly blocked.
- Digits/amounts in OCR must be right (target 99.9%); speed matters too.
- Writes casually (typos); infer intent, don't ask about spelling.
- Wants `setup_flutter.bat` to be the one-stop bootstrap on a fresh clone.
- Wants Claude-side tooling in the repo: `/johnny` (refresh) and
  `/update-johnny` (record) project commands in `.claude/commands/`.

## Environment facts (this machine)

- Windows 11 Pro, 16 logical cores, repo at `D:\C++\01_Test Project\StockPriceCalculator`
  (**path has spaces and a `+`**), D: has ~100 GB free. Git branch `develop`
  (also the PR base), remote `origin` = GitHub `JeJoProjects/Stock-Price-Calculator`.
- Flutter SDK actually used: **`C:\src\flutter`** (space-free path is mandatory,
  see traps). `external\flutter` is an unused duplicate. Dart via
  `C:\src\flutter\bin\dart.bat`. `PUB_CACHE` must be `<repo>\external\pub_cache`
  for manual builds.
- Python: only **miniconda 3.10** (`C:\ProgramData\miniconda3`), not on cmd PATH.
  Tesseract 5.4 installed via winget at `C:\Program Files\Tesseract-OCR`.
- VS Code + Dart extension keep daemons running from the SDK folder (lock files).
- User's scans: `D:\OneDrive\Bank - Work - More\...` (private). A printer
  software's OCR export (UTF-16 text) was the comparison baseline.

## Open items / not verified

- OCR tab has been exercised via its pipeline code, `tool/ocr_eval.dart`, the
  frozen sidecar and tests — **not by clicking through the running GUI** with
  the hybrid engine. Verify visually next time.
- Backend tests (`cd backend && dart test`, 26) last run 2026-10-04.
- Android/Linux/iOS never built on this machine.
- CLAUDE.md still shows a few example amounts taken from the real scans in the
  OCR section; harmless but worth genericizing if privacy matters more.
- `scripts/search_symbols.py`, `ToDo.txt` are dead repo cruft awaiting an
  explicit go-ahead to delete (see CLAUDE.md > Known Repo Cruft).
- `/update-johnny` has been run once (the 22:03 entry below) and worked end to
  end; **`/johnny` has not been run yet** — run it next session and check the
  briefing is useful and short enough.

---

## Timeline (newest first)

## 2026-10-12T22:03:16+02:00 — First /update-johnny run (covers 68a938a..321c049, since 2026-10-12T21:55:23+02:00)

**What changed.** Only one commit fell in the window: `321c049` (21:56:57)
added `.claude/commands/johnny.md` (64 lines), `.claude/commands/update-johnny.md`
(82 lines) and the seeded `.claude/johnny/KNOWLEDGE.md` (161 lines). This run
added a "Claude Code project commands" section to `CLAUDE.md` (before "OCR Tab")
so the current-truth doc knows the commands exist, refreshed this ledger's
header/open items, and recorded this entry. No application code, scripts or tests
changed in the window; working tree was clean at the start (`git status` empty).

**Why / decisions.** Kept the split "CLAUDE.md = current truth, ledger =
history/why/traps" so neither grows duplicated prose. The header stamp stores the
sha *before* the docs commit that records an update (a commit cannot contain its
own hash), so the next run's `<sha>..HEAD` window always includes the previous
docs commit — expect each run to list the prior run's own commit; that is normal,
just don't re-describe it.

**Observations (verified this session).**
- Project commands in `.claude/commands/` were picked up **without restarting**:
  `johnny` and `update-johnny` appeared in the skill list immediately.
- `$ARGUMENTS` was substituted with an empty string for a bare `/update-johnny`
  (so "contains `push`" is false → commit only, no push).
- `git add` prints "LF will be replaced by CRLF" for these files (repo
  `autocrlf`); harmless, same as the rest of the repo.
- `.claude/scheduled_tasks.lock` never shows in `git status` because it is
  excluded locally in `.git/info/exclude` (not in `.gitignore`, so a fresh clone
  has no such rule — it is a Claude Code runtime file, don't commit it).
- The primary working directory string flips between `d:\…` and `D:\…` across
  messages; Windows paths are case-insensitive, no action needed.

**Verified vs not verified.** Verified: commit contents/sizes above (`git log
--stat`), file existence, the lock-file exclusion, `$ARGUMENTS` behaviour.
**Not verified:** `/johnny` itself has never been run; no build/test was run in
this window (the 86 tests / clean analyze from 2026-10-05 still stand because no
code changed).

**User preferences & machine facts.** No new preferences. Re-confirmed: one-line
commits; push only on request (this run does not push).

**Open items / next steps.** Run `/johnny` once and tune it; consider replacing
the real-looking example amounts in CLAUDE.md's OCR section with invented ones;
GUI click-through of the hybrid OCR tab is still outstanding.

## 2026-10-12T21:55:23+02:00 — Created /johnny and /update-johnny (covers 68a938a..68a938a, since first ledger)

**What changed.** Added project slash commands `.claude/commands/johnny.md`
(read-only knowledge refresh + briefing; `verify` arg also runs analyze/tests)
and `.claude/commands/update-johnny.md` (records the window "last update → now"
into this ledger, reconciles CLAUDE.md, updates auto-memory, one-line commit,
pushes only with the `push` arg). This ledger (`.claude/johnny/KNOWLEDGE.md`) is
the store they share; its header holds the timestamp + sha they diff against.
**Why.** User wanted a one-command way to reload and to record app knowledge
across sessions. **Design choices.** Ledger is separate from CLAUDE.md so
CLAUDE.md stays current-truth while history/why lives here. Timestamps come from
`date -Iseconds`, never guessed.
**Unverified.** Neither command has been run yet; this entry is the seed that
summarizes the whole history below.

## Seed summary of history up to 2026-10-05 (commits up to 68a938a)

### Project lineage (from git log, verified)
- 2026-05-31 → 2026-06-19: C++23 / Dear ImGui app (Yahoo search, Finnhub, chart).
- 2026-08-31 → 09-01: Flutter/Dart rewrite added, repo converted to Flutter-only
  (`1a5898d`). 2026-09-04: Finviz-sourced micro-cap screener + self-launched Dart
  backend; tabbed Finviz/Yahoo/Combined screener (`a21cbb1`).
- 2026-10-04: OCR tab (`9635caf`, Tesseract + PaddleOCR, patched pdfrx); CLAUDE.md
  rewrite and dead C++ files removed (`e20d5a6`); Finnhub candle endpoint found
  paywalled → Alpha Vantage free daily candles + disk cache (`8e88ba6`); then
  found live that Alpha Vantage intraday is premium-only too → daily bars
  (`b2200e2`). See CLAUDE.md > Candle Data.

### 2026-10-05 session (commits 418cf6c, 7f5a273, d6eab98, 931d3b7, 68a938a)

**What changed.**
- *Windows build repair:* `setup_flutter.bat` failed 3 different ways before it
  worked. Fixes in both scripts: `:EnsurePubCache` (non-hidden `PUB_CACHE`),
  space-free Flutter SDK path (`%SystemDrive%\src\flutter` when repo path has
  spaces), `external\flutter` checked first in `:ResolveFlutterSdk`, CRLF line
  endings, escaped parentheses in echo lines. Details in CLAUDE.md > How to Build.
- *Batch OCR UI* (`ocr_panel.dart`, `ocr_batch.dart`): many files / folders /
  paste → queue → one combined Markdown doc (preview + source, copy all, save
  .md). Labels from file names (Unicode kept). Retry button + auto-retry when an
  engine appears later. Worker pool via `ImageRecognizer.preferredConcurrency`.
- *Accuracy pipeline* (`tesseract_client.dart`, `number_consensus.dart`,
  `image_variants.dart`, `ocr_sidecar_client.dart`, `pyocr/*`): primary Tesseract
  pass (`deu+eng`, German first) + 0.9x/1.3x passes + PaddleOCR verifier,
  position-aware weighted number voting, recovery of missed/garbled values,
  deterministic amount rules. Full spec in CLAUDE.md > OCR Tab.
- *Automation* (`scripts/build_ocr_sidecar.bat`, `setup_flutter.bat`,
  `run_flutter.bat`, `pyocr/build_sidecar.spec`, `prefetch_models.py`): one-stop
  bootstrap — installs Tesseract via winget, bundles `Release\tessdata`
  (eng/osd/deu), finds/installs Python 3.9–3.12, builds the sidecar, deletes
  `pyocr\dist`, `pyocr\build` and the venv (658 MB kept of ~2.3 GB peak).
- *Tests/tools:* `test/ocr/{ocr_batch,number_consensus,ocr_pipeline,
  tesseract_client}_test.dart`; `app/tool/ocr_eval.dart` CLI. 86 app tests pass,
  `flutter analyze` clean.

**Problems → root cause → fix.**
- `Get-Item : Could not find item …\AppData` → cargokit's `resolve_symlinks.ps1`
  lacks `-Force`; hidden pub cache → move `PUB_CACHE` out of AppData.
- `'D:\C++\01_Test' is not recognized` / `build_hooks failed` → Flutter's
  native-assets hook launches `dart` via an unquoted path → SDK at `C:\src\flutter`.
- Script wiped `external\flutter` → `:ResolveFlutterSdk` never checked it and
  `rmdir`'d before re-cloning (I triggered this by running it without Flutter on PATH).
- Sidecar step crashed (`still was unexpected`) → unescaped `(`/`)` in `echo`
  inside an `if (...)` block.
- "No OCR engine found" on every file → Tesseract simply wasn't installed; also
  UX was poor (no hint/retry) → better message, Retry, auto-retry.
- Mangled labels → ASCII-only regex dropped `ä` and glued `1.1` + `01.2022`.
- `eng+deu` lost umlauts (`für`→`fur`) that `deu+eng` kept → German first.
- Image variants took 15–21 s/page → `package:image` cubic resize was the cost
  (13 s); replaced with own typed-array bilinear + PGM output (~0.1–0.3 s).
- Tesseract digit slips (listed in CLAUDE.md) → consensus pipeline; also needed
  first-digit changes allowed and verifier weight 2.5 (ties kept the wrong
  value at weight 2.0); omissions need recovery, voting can't fix them.
- PaddleOCR swaps decimal comma for dot on some fonts → `_plausibleFix` refuses
  to turn a well-formed German amount into a malformed one.
- Frozen sidecar died: `DLL load failed … _ctypes` (conda libffi not scanned) and
  `PackageNotFoundError: imageio` (missing dist-info) → both fixed in the spec.
- An orphaned old `stockcalc_ocr.exe` (old code, stuck "starting") blocked port
  8091 → killed; the new sidecar reaches `ready` in ~14 s.
- Python edits via heredocs repeatedly corrupted files (`\n`, `\b`, `\f` turned
  into real control characters; CRLF mismatches; IDE re-saving stale buffers).
  **Use the Edit/Write tools for code with escapes; check `grep -c $'\x08'`.**

**Measurements.** Parallel OCR: 12 full pages 61 s → 14 s (16 cores, 6 workers).
Number pipeline on 13 real German pages (425 money/date values, read from
OneDrive, not committed): plain Tesseract 418/421 agree with PaddleOCR; new
pipeline 425/425, and 178/178 vs the printer software's OCR on its 6 pages
(the two differences are printer errors). Cost ≈3× per page: ~50 s/13 pages
hybrid, ~38 s Tesseract-only, ~13 s single pass. 99.9% is *not provable* from
425 values — "no known errors".

**Traps.** Antivirus can transiently break `pub get` ("failed to rename
directory") → rerun. Don't run setup while an IDE holds the SDK. Keep the paddle
venv path short (Windows 260-char limit; script falls back to `C:\stockcalc_pyvenv`).
Real-Tesseract tests auto-skip without Tesseract + `Release\tessdata\deu`.
pip cache (6.5 GB) was deleted at the user's approval; rebuild re-downloads.
