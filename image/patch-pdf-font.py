"""ADR 0006: docassemble's default LaTeX template asks for Times New Roman by name.

Times New Roman cannot ship in a public image (Microsoft's core-fonts EULA), so the default becomes
Tinos: metric-compatible (same widths and line spacing), OFL, and named honestly in the PDF's font
list. Interviews that set `fontfamily:` are unaffected. Exit non-zero unless exactly one expected
line is found, so a changed upstream template stops the build instead of being patched blindly.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
OLD = r"\setmainfont{Times New Roman}"
NEW = r"\setmainfont{Tinos}"
n = src.count(OLD)
if n != 1:
    sys.exit(f"patch-pdf-font: expected 1 '{OLD}', found {n}; upstream changed, revisit ADR 0006")
open(path, "w", encoding="utf-8").write(src.replace(OLD, NEW))
print("patch-pdf-font: default LaTeX font is now Tinos")
