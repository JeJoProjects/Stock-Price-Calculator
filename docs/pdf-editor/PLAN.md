# PDF Editor tab — requirements, research, architecture, plan

Status legend: [x] done and tested · [~] partly · [ ] planned. Keep this table
current (update it in the same commit as the code).

## Requirements (from the product owner's brief + 8 screenshots of a reference editor)

| # | Requirement | Status |
|---|---|---|
| R1 | New top-level **PDF Editor** tab, app theme (`AppColors`) | [x] |
| R2 | Open one or many PDFs, drag-and-drop, browse, **whole folder** (all PDFs listed), new blank document | [x] (also command-line / `STOCKCALC_PDF_OPEN`) |
| R3 | Toolbar, exact names/order: **Text▾ (Find & Replace) · Links · Forms▾ · Images▾ · Sign▾ · Whiteout · Annotate▾ · Shapes▾ · Undo** (+ Redo) | [x] |
| R4 | **Edit existing text / digits / currency symbols**, add new text (font, size, bold, italic, colour) | [x] logic tested; GUI seen working |
| R5 | Forms▾: symbols ✕ ✓ ■, text; field types (text, multiline, drop-down, radio, checkbox, signature box); detect fields; form edit mode; tab order | [~] symbols+text done; interactive fields listed as "soon" |
| R6 | Images▾: stamps (DRAFT…), new image, delete existing image, new stamp | [x] code+tests; stamp/image placing not yet clicked through in GUI |
| R7 | Sign▾: **remembers previous signatures** (delete ✕), New Signature by typing / drawing / uploading an image | [x] code+tests; dialog not yet clicked through in GUI |
| R8 | Whiteout; Annotate▾ (show annotations, strike out, highlight, underline with colours, freehand highlight, draw); Shapes▾ (ellipse, rectangle, line, arrow) | [x] bake tested; GUI interaction partly verified |
| R9 | Page tools: page number, delete page, zoom in/out, rotate left/right, Insert page here | [x] |
| R10 | **Apply changes → save**; Undo/Redo; intermediate saves (draft); Save as | [x] |
| R11 | Very intuitive, Photoshop-like UX | [~] options bar, handles, shortcuts, hints done; needs real-user feedback |
| R12 | Commercial-safe licensing (no copyleft deps); no copying of the reference product's assets/branding | [x] |
| R13 | 100% local/private (nothing uploaded) | [x] by design |
| R14 | Tests on synthetic PDFs only (never real personal documents) | [x] |

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
* PDFium is not thread-safe: all editor FFI work (bake, analyse, page actions,
  rendering) runs through ONE long-lived worker isolate (`pdfium_worker.dart`)
  that also keeps recent documents warm. The OCR tab's PDF extraction uses
  pdfrx's own worker: don't run a PDF OCR batch and heavy editing at once.

## Steps / milestones

1. [x] `pdfium_edit.dart` FFI wrapper + `pdf_baker.dart` + tests (synthetic PDFs)
2. [x] Edit model, history (undo/redo), drafts + tests
3. [x] Tab shell, document list (files/folder/drag-drop), page viewer, zoom
4. [x] Tools: Text (add/edit/find&replace), Whiteout, Shapes, Annotate, Images, Sign, symbols
5. [x] Page tools, Apply changes, Save/Save as/Save draft
6. [~] Links tool + stamps + shortcuts done. **Next:** interactive form fields (needs AcroForm object creation beyond PDFium's API), detect fields, page drag-reorder, autosave drafts, text-selection markup on scanned pages, GUI click-through of every dialog
