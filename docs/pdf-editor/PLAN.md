# PDF Editor tab — requirements, research, architecture, plan

Status legend: [x] done and tested · [~] partly · [ ] planned. Keep this table
current (update it in the same commit as the code).

## Requirements (from the product owner's brief + 8 screenshots of a reference editor)

| # | Requirement | Status |
|---|---|---|
| R1 | New top-level **PDF Editor** tab, app theme (`AppColors`) | [ ] |
| R2 | Open one or many PDFs, drag-and-drop, browse, **whole folder** (all PDFs listed), new blank document | [ ] |
| R3 | Toolbar, exact names/order: **Text▾ (Find & Replace) · Links · Forms▾ · Images▾ · Sign▾ · Whiteout · Annotate▾ · Shapes▾ · Undo** (+ Redo) | [ ] |
| R4 | **Edit existing text / digits / currency symbols**, add new text (font, size, bold, italic, colour) | [ ] |
| R5 | Forms▾: symbols ✕ ✓ ■, text; field types (text, multiline, drop-down, radio, checkbox, signature box); detect fields; form edit mode; tab order | [ ] |
| R6 | Images▾: stamps (DRAFT…), new image, delete existing image, new stamp | [ ] |
| R7 | Sign▾: **remembers previous signatures** (delete ✕), New Signature by typing / drawing / uploading an image | [ ] |
| R8 | Whiteout; Annotate▾ (show annotations, strike out, highlight, underline with colours, freehand highlight, draw); Shapes▾ (ellipse, rectangle, line, arrow) | [ ] |
| R9 | Page tools: page number, delete page, zoom in/out, rotate left/right, Insert page here | [ ] |
| R10 | **Apply changes → save**; Undo/Redo; intermediate saves (draft); Save as | [ ] |
| R11 | Very intuitive, Photoshop-like UX | [ ] |
| R12 | Commercial-safe licensing (no copyleft deps); no copying of the reference product's assets/branding | [x] |
| R13 | 100% local/private (nothing uploaded) | [x] by design |
| R14 | Tests on synthetic PDFs only (never real personal documents) | [ ] |

Out of scope (cloud-only in the reference): "Publish for others to fill & sign".

## Research findings that drove decisions

* **Engine.** The app already ships PDFium (`pdfium.dll`, via the patched
  `pdfrx`). PDFium's C API can enumerate page objects, read text/bounds/font,
  remove objects, create text/path/image objects, add annotations and save.
  `pdfrx`'s generated bindings lack the save call and `FPDF_FILEWRITE`, so
  `lib/pdfedit/pdfium_edit.dart` binds the ~40 needed functions directly from the
  same DLL. **Spike verified (2026-10-12):** create doc, insert text + filled
  rect, `FPDFPage_GenerateContent`, `FPDF_SaveAsCopy` through a
  `NativeCallable.isolateLocal` write callback -> valid PDF.
* PDFium rule: edits only reach the saved file after `FPDFPage_GenerateContent`;
  a cached text page goes stale after edits (reload it).
* **Licensing.** PDFium BSD/Apache; pdf-lib MIT; Stirling-PDF is open-core;
  MuPDF is AGPL -> avoided. No Syncfusion (commercial licence).
* **UX patterns** (PDF-XChange, Adobe): context-sensitive properties bar that
  only shows options for the active tool/selection; most important text options
  in the top bar, secondary options in a collapsible panel; novices need a
  minimal first view, experts need shortcuts.

## Architecture (decisions)

* **Overlay edit list + bake.** Live edits are immutable Dart objects drawn as
  Flutter widgets over the rendered page (`pdfrx` render). "Apply changes" /
  Save bakes them into real PDF objects with PDFium and saves. Gives cheap
  undo/redo, drafts, and a fast UI.
* **History = snapshots** `{workingFile, ops}`. Structural page changes (delete,
  rotate, insert) bake into a new working file version; overlay changes only
  change `ops`. Undo/redo moves a pointer.
* **Editing existing text:** hit-test PDFium text objects (grouped into lines);
  an edit deletes the original object(s) at bake time and inserts a new text
  object (closest installed font; Unicode via embedded TrueType). The preview
  paints a page-colour patch over the original until baked.
* Module split (project rule): `lib/pdfedit/` (pure Dart/FFI, tested) +
  `lib/widgets/pdf_editor_panel.dart` (+ `lib/widgets/pdf_editor/*`).
* Signatures: PNGs in `%APPDATA%\stockcalc\signatures\`.
* PDFium is not thread-safe: all FFI work runs in one isolate at a time; do not
  run PDF OCR extraction and the editor's bake simultaneously.

## Steps / milestones

1. [ ] `pdfium_edit.dart` FFI wrapper + `pdf_baker.dart` + tests (synthetic PDFs)
2. [ ] Edit model, history (undo/redo), drafts + tests
3. [ ] Tab shell, document list (files/folder/drag-drop), page viewer, zoom
4. [ ] Tools: Text (add/edit/find&replace), Whiteout, Shapes, Annotate, Images, Sign, symbols
5. [ ] Page tools, Apply changes, Save/Save as/Save draft
6. [ ] Links, form fields, stamps; polish, shortcuts, docs, build, verification
