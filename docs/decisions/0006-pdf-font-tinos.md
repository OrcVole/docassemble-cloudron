# 0006. Tinos replaces Times New Roman as the default PDF font

- **Status:** accepted, 2026-11-07 (maintainer's choice after a measured comparison)
- **Second recorded exception** to "never patch the application" (AGENTS.md, golden rule 1)

## Context

docassemble's default LaTeX template (`Legal-Template.tex`) contains `\setmainfont{Times New Roman}`,
used for every PDF assembled from Markdown unless the interview sets `fontfamily:`. Without that
font, LuaLaTeX stops with a fontspec error and no PDF is produced. Upstream's image installs
Microsoft's core fonts. Microsoft's EULA allows passing on only its original installers, so a public
image carrying the installed fonts is a grey area we decline.

Measured against Times New Roman 2.82 (fontTools, same sample text and size):

| Face | Widths equal to TNR (of 191) | Line height | 20-page brief |
|---|---|---|---|
| Tinos 1.340 | 190 | ×1.000 | 20.0 pp |
| Liberation Serif 2.1.5 | 190 | ×1.000 | 20.0 pp |
| Nimbus Roman | 187 | ×1.043 | 20.0 pp |
| STIX Two Text 2.13 | 1 | ×1.087 | 20.6 pp |
| Source Serif 4 4.004 | 15 | ×1.192 | 21.7 pp |

Renaming a substitute to "Times New Roman" was considered and rejected: the PDF's embedded-font list
would then claim Times New Roman, a false statement in a court filing.

## Decision

- The build changes that one template line to `\setmainfont{Tinos}`. `image/patch-pdf-font.py` fails
  the build unless exactly one original line is found.
- The image ships Tinos 1.340 (OFL, full TTFs pinned by commit and sha256 from the Google Fonts
  repository; the web mirrors, Bunny included, serve 235-glyph WOFF2 subsets that LaTeX cannot read),
  plus two modern faces authors may choose per document with `fontfamily:`: STIX Two Text
  (Ubuntu `fonts-stix`, 2.13b171) and Source Serif 4 (Adobe release 4.005R, pinned by sha256).

## Consequences

- Existing interviews keep their line and page breaks: Tinos matches Times New Roman's widths and
  line spacing. The letter shapes differ slightly (R, 2, 4, 6; a 3% larger x-height).
- PDFs name Tinos in their font list. Where a rule requires Times New Roman itself, an operator with a
  licence puts the font files in `/app/data/fonts` (backed up; picked up by fontconfig and LuaLaTeX at
  start). The package never ships it.
- DOCX templates are unaffected: LibreOffice substitutes Liberation Serif for Times New Roman.
- Each upstream bump re-checks the template line automatically.
