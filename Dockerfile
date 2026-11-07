# Docassemble for Cloudron. Design: docs/decisions/0001 to 0005. Three stages:
#   uv       the pinned uv binary, which installs the interpreter as well as the packages (ADR 0002)
#   builder  compilers + CPython 3.15 + docassemble's pinned dependency set into /app/code
#   runtime  cloudron/base plus the OS tools docassemble drives (LibreOffice, pandoc, TeX, Tesseract);
#            only /app/code is copied across, so no compiler ships.
# The single bump point for an upstream release is DA_VERSION (mirrored as upstreamVersion).

ARG DA_VERSION=1.10.15
ARG PY_VERSION=3.15.2

FROM ghcr.io/astral-sh/uv:0.13.7@sha256:96f40d3904aad8d0bd010539001d36c8e2188b981e1334471a90c4a1d93bb490 AS uv

# ---------------------------------------------------------------------------------------------------
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee AS builder
ARG DA_VERSION
ARG PY_VERSION
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/app/code/python UV_LINK_MODE=copy UV_NO_CACHE=1 UV_COMPILE_BYTECODE=1

# Headers for the packages that compile locally on 3.15 (PyYAML, ruamel.yaml.clib, netifaces,
# python-ldap, uWSGI) and for anything else that falls back to source.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      build-essential pkg-config libldap-dev libsasl2-dev libpq-dev libxml2-dev libxslt1-dev \
      libjpeg-dev zlib1g-dev libffi-dev libssl-dev libcairo2-dev libpcre2-dev libzbar0 libmagic1 \
 && rm -rf /var/lib/apt/lists/*

RUN uv python install "${PY_VERSION}" \
 && uv venv --seed --python "${PY_VERSION}" /app/code/venv \
 && uv pip install --python /app/code/venv/bin/python \
      "docassemble.base==${DA_VERSION}" "docassemble.webapp==${DA_VERSION}" "uWSGI==2.0.31"

# ADR 0003: the websocket server must send the Redis password. Fails the build unless exactly the
# three expected upstream lines are found.
COPY image/patch-socketserver.py /tmp/patch-socketserver.py
RUN /app/code/venv/bin/python /tmp/patch-socketserver.py \
      /app/code/venv/lib/python3.15/site-packages/docassemble/webapp/socketserver.py

# ADR 0007: two upstream bugs that stop background OCR returning text.
COPY image/patch-ocr.py /tmp/patch-ocr.py
RUN /app/code/venv/bin/python /tmp/patch-ocr.py /app/code/venv/lib/python3.15/site-packages

# ADR 0008: LDAP sign-in with Cloudron's ldap addon (no WhoAmI there; anonymous binds refused).
COPY image/patch-ldap.py /tmp/patch-ldap.py
RUN /app/code/venv/bin/python /tmp/patch-ldap.py \
      /app/code/venv/lib/python3.15/site-packages/docassemble/webapp/users/forms.py

# ADR 0006: the default PDF template's font becomes Tinos (Times New Roman cannot ship).
COPY image/patch-pdf-font.py /tmp/patch-pdf-font.py
RUN /app/code/venv/bin/python /tmp/patch-pdf-font.py \
      /app/code/venv/lib/python3.15/site-packages/docassemble/base/data/templates/Legal-Template.tex

# ADR 0004: add-on packages and Playground modules live under /app/data/packages. One static .pth
# puts that prefix on every process's import path.
RUN echo /app/data/packages/lib/python3.15/site-packages \
      > /app/code/venv/lib/python3.15/site-packages/zz-docassemble-addons.pth

# The NLTK corpora docassemble otherwise downloads on first use (upstream's nltkdownload.py list).
RUN /app/code/venv/bin/python -m nltk.downloader -q -d /app/code/nltk_data \
      omw-1.4 wordnet wordnet_ic sentiwordnet stopwords punkt

# Field guide #331: glibc 2.43 refuses a dlopen'ed library that asks for an executable stack.
RUN bad=$(find /app/code -name '*.so*' -type f -exec sh -c 'readelf -lW "$1" 2>/dev/null | grep -q "GNU_STACK.*RWE" && echo "$1"' _ {} \;); \
    if [ -n "$bad" ]; then echo "execstack libraries:"; echo "$bad"; exit 1; fi

# ---------------------------------------------------------------------------------------------------
# ADR 0006: fonts for PDFs, each file pinned by commit or release and checked by sha256.
#   Tinos 1.340 (OFL): the default face, metric-compatible with Times New Roman. Full TTFs from the
#     Google Fonts repository; the web-font mirrors serve 235-glyph WOFF2 subsets LaTeX cannot use.
#   Source Serif 4 4.005R (OFL): a modern alternative authors can choose with `fontfamily:`.
#   (STIX Two Text, the other alternative, comes from Ubuntu's fonts-stix in the runtime stage.)
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee AS fonts
ARG TINOS_COMMIT=ba95515f1333efe9342c2ad988b9c2f6bef6dbad
ARG TINOS_LICENCE_COMMIT=4106aab86ddefe26d58a69745e04ae9479d22993
ARG SOURCE_SERIF_RELEASE=4.005R
WORKDIR /out
RUN set -e; mkdir -p tinos source-serif-4; \
    for f in Regular Bold Italic BoldItalic; do \
      curl -fsSL -o "tinos/Tinos-$f.ttf" "https://raw.githubusercontent.com/google/fonts/${TINOS_COMMIT}/ofl/tinos/Tinos-$f.ttf"; done; \
    curl -fsSL -o tinos/OFL.txt "https://raw.githubusercontent.com/googlefonts/tinos/${TINOS_LICENCE_COMMIT}/OFL.txt"; \
    curl -fsSL -o /tmp/ss4.zip "https://github.com/adobe-fonts/source-serif/releases/download/${SOURCE_SERIF_RELEASE}/source-serif-4.005_Desktop.zip"; \
    printf '%s\n' \
      "60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61  tinos/Tinos-Regular.ttf" \
      "393269dbab8899f938db19783eca5eac92eb431f7ae0ab45b8349ca895f1a06b  tinos/Tinos-Bold.ttf" \
      "5942266ed398b155d7dc23e36833e7ec6be988f2439bdbeb8ef1bede808eaa91  tinos/Tinos-Italic.ttf" \
      "a5de79f0fe863ea0954757acb3d47b3ccd0a930ce3dd5b97230cd3866790a06e  tinos/Tinos-BoldItalic.ttf" \
      "cb3382d4643e8b02c12e322c220a3c76a5020d667e4fd4e7c75e744cca6caa6b  tinos/OFL.txt" \
      "549fdb8f9a682bd06944298621404969f6de77c2e422ff3b8244a1dcd6a0c425  /tmp/ss4.zip" | sha256sum -c -; \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/ss4.zip').extractall('/tmp/ss4')"; \
    cp /tmp/ss4/source-serif-4.005_Desktop/OTF/SourceSerif4-*.otf /tmp/ss4/source-serif-4.005_Desktop/LICENSE.md source-serif-4/

# ---------------------------------------------------------------------------------------------------
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee
ARG DA_VERSION
COPY --from=uv /uv /usr/local/bin/uv

# The OS tools docassemble drives, after upstream's docassemble-os list, without the services
# Cloudron supplies (PostgreSQL, Redis, RabbitMQ, exim4, Apache, certbot, syslog-ng, cron).
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      libldap2 libsasl2-2 libpq5 libxml2-16 libxslt1.1 libcairo2 libzbar0 libmagic1 \
      libreoffice-writer libreoffice-calc libreoffice-impress python3-uno \
      pandoc texlive texlive-luatex texlive-xetex texlive-latex-recommended texlive-latex-extra \
      texlive-font-utils texlive-lang-all texlive-extra-utils lmodern \
      poppler-utils qpdf ghostscript pdftk-java imagemagick ffmpeg \
      tesseract-ocr-all wamerican fonts-liberation fonts-dejavu-core fonts-stix \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fonts /out/ /usr/local/share/fonts/
RUN fc-cache -f >/dev/null && fc-list | grep -q 'Tinos' && fc-list | grep -q 'Source Serif 4' && fc-list | grep -q 'STIX Two Text'
# After the build's cache exists: operator fonts in /app/data/fonts, cached under /run at runtime.
COPY image/fontconfig-app-data.conf /etc/fonts/conf.d/99-app-data-fonts.conf

COPY --from=builder /app/code /app/code

# unoserver runs on the distribution's Python because it needs LibreOffice's uno binding (ADR 0002).
RUN uv venv --system-site-packages --python /usr/bin/python3 /app/code/uno \
 && UV_NO_CACHE=1 uv pip install --python /app/code/uno/bin/python "unoserver==3.7" \
 && /app/code/uno/bin/python -c "import uno, unoserver" \
 && rm /usr/local/bin/uv

# LuaLaTeX's font cache, built once here so the first PDF does not stall on a read-only home.
ENV TEXMFVAR=/app/code/texmf-var
RUN mkdir -p /app/code/texmf-var && luaotfload-tool --update --force >/dev/null

# ImageMagick refuses PDF by default; docassemble converts PDF pages to images (upstream does this).
RUN sed -i 's|</policymap>|  <policy domain="coder" rights="read \| write" pattern="PDF" />\n</policymap>|' \
      /etc/ImageMagick-*/policy.xml

RUN echo "${DA_VERSION}" > /app/code/VERSION
COPY image/ /app/code/image/
COPY bin/ /app/code/bin/
COPY start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh /app/code/bin/*

# Build gate: the packaged interpreter, docassemble, the patch and the add-on path are all present.
RUN /app/code/venv/bin/python -c "import docassemble.base, docassemble.webapp, ldap, psycopg2, celery, pyzbar.pyzbar" \
 && /app/code/venv/bin/uwsgi --version \
 && mkdir -p /app/data/packages/lib/python3.15/site-packages \
 && /app/code/venv/bin/python -c "import sys; assert '/app/data/packages/lib/python3.15/site-packages' in sys.path, sys.path" \
 && rm -rf /app/data/packages \
 && grep -q 'password=redis_password' /app/code/venv/lib/python3.15/site-packages/docassemble/webapp/socketserver.py

ENV DA_PYTHON=/app/code/venv \
    DA_CONFIG_FILE=/app/data/config/config.yml \
    NLTK_DATA=/app/code/nltk_data \
    UV_PYTHON_DOWNLOADS=never \
    PATH=/app/code/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app/code
CMD ["/app/code/start.sh"]
