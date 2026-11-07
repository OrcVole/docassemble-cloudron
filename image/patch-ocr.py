"""ADR 0007: two upstream bugs that stop background OCR returning text. Usage: patch-ocr.py SITE_PACKAGES

1. webapp/tasks/tasks.py (1.10.0 to 1.10.15): the Celery task `ocr_finalize` returns
   `content=ocr_finalize(*pargs, **kwargs)`, calling itself. 1.9.0 called the helper
   (worker_controller.util.ocr_finalize); 1.10.0 imported it as `do_ocr_finalize` but left this call on
   the bare name. Each recursion opens a database connection until SQLAlchemy's pool times out.
2. base/util.py ocr_page (1.9.0 or earlier to 1.10.15): when a PDF page has no pre-rendered image, it
   runs `pdftoppm -r <ocr_resolution>`, but ocr_page_tasks has already multiplied that value by 11 to
   make a `-scale-to` pixel size (300 dpi becomes 3300), as ocr_file uses it. At 3300 dpi poppler
   refuses the allocation, still exits 0, and writes a 1x1 image, so OCR returns no text.
Each replacement must match exactly once, or the build stops: a changed upstream file is revisited,
never patched blindly.
"""
import sys

site = sys.argv[1].rstrip("/")
FIXES = [
    (f"{site}/docassemble/webapp/tasks/tasks.py",
     "content=ocr_finalize(*pargs, **kwargs)", "content=do_ocr_finalize(*pargs, **kwargs)",
     "ocr_finalize as do_ocr_finalize"),
    (f"{site}/docassemble/base/util.py",
     "args = [str(pdf_to_ppm), '-r', str(ocr_resolution), '-f', str(page), '-l', str(page)]",
     "args = [str(pdf_to_ppm), '-scale-to', str(ocr_resolution), '-f', str(page), '-l', str(page)]",
     "ocr_resolution = str(int(float(ocr_resolution)*11.0))"),
]
for path, old, new, context in FIXES:
    src = open(path, encoding="utf-8").read()
    if src.count(old) != 1 or context not in src:
        sys.exit(f"patch-ocr: expected exactly one {old!r} (with {context!r}) in {path}; "
                 "upstream changed, revisit ADR 0007")
    open(path, "w", encoding="utf-8").write(src.replace(old, new))
    print(f"patch-ocr: fixed {path.split('site-packages/')[-1]}")
