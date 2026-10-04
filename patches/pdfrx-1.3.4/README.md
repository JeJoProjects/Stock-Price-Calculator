# Locally patched pdfrx 1.3.4

This is a vendored copy of the upstream [pdfrx](https://pub.dev/packages/pdfrx)
1.3.4 package, used via `dependency_overrides` in `app/pubspec.yaml`.

**Why this exists:** upstream's `lib/src/pdfium/pdf_file_cache.dart`
(an HTTP-caching code path used only by `PdfDocument.openUri` with caching
enabled - this app only calls `PdfDocument.openFile` and never hits this
path) fails to compile on Windows under this repo's Dart SDK: a captured
`PdfFileCache?` parameter is null-asserted once (`cache!.blockSize`) inside
a closure, then used again without the assertion (`cache.isCached(...)`) a
few lines later - Dart does not promote a captured parameter's nullability
across closure boundaries, so the second use is a compile error.

**The fix:** one line added, `final nonNullCache = cache!;`, right before
the closure, with every subsequent use inside it rebound to
`nonNullCache` instead of `cache`. No behavior change - purely a
null-promotion fix. See the diff in `lib/src/pdfium/pdf_file_cache.dart`.

**Maintenance:** this override should be removed once either (a) upstream
ships a fixed release, or (b) this repo can take pdfrx's 2.x line without
colliding with `excel`'s `archive` version constraint (pdfrx 2.x pulls in
`archive ^4.0.9`; `excel` 4.0.6 pins `archive ^3.6.1`). Check both
periodically.
