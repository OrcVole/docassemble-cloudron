# 0007. Fix two upstream bugs that stop background OCR returning text

- **Status:** accepted, 2026-11-07. Third recorded exception to "never patch the application".

## Context

Proof 1 (ADR 0005) runs `ocr_file_in_background()` on a PDF the interview itself assembled. On
1.10.15 it failed twice, for reasons that are upstream's, not the package's:

1. **Recursion** (`webapp/tasks/tasks.py`, 1.10.0 to 1.10.15). The Celery task `ocr_finalize` returns
   `content=ocr_finalize(*pargs, **kwargs)`, calling itself. In 1.9.0 the line called the helper
   `worker_controller.util.ocr_finalize`; the 1.10.0 refactor imported it as `do_ocr_finalize` and left
   this call on the bare name. Each level opens an app context and a database connection, so the task
   ends with `QueuePool limit of size 5 overflow 10 reached` instead of text.
2. **A 1x1 page image** (`base/util.py` `ocr_page`, 1.9.0 or earlier to 1.10.15). For a PDF page with no
   pre-rendered image, `ocr_page` runs `pdftoppm -r <ocr_resolution>`, but `ocr_page_tasks` has already
   multiplied that value by 11 to make a `-scale-to` pixel size (300 dpi becomes 3300), as `ocr_file`
   uses it. Poppler refuses a 28,050 x 36,300 page ("Bogus memory allocation size"), still exits 0, and
   writes a 1x1 image; Tesseract returns nothing. Uploaded PDFs usually have pre-rendered page images,
   which hides the bug; PDFs the interview makes do not.

## Decision

`image/patch-ocr.py` makes both one-word changes (`do_ocr_finalize`; `-scale-to`) and stops the build
unless each original line is found exactly once. Both go upstream (`docs/FOR-UPSTREAM.md`). Remove each
fix when a release carries it.

## Evidence

Before: `QueuePool limit ... reached`, then an empty OCR result. After: the proof's OCR returns "I.
Proof letter The quick brown fox jumps over the lazy dog. Docassemble on Cloudron.", before and after a
restart.
