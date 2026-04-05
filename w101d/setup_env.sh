#!/usr/bin/env bash
# setup_env.sh — Wine içine Python 3.13 + Deimos bağımlılıklarını kurar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.13.3"
EMBED_ZIP="python-${PYTHON_VERSION}-embed-amd64.zip"
EMBED_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${EMBED_ZIP}"
GET_PIP_URL="https://bootstrap.pypa.io/get-pip.py"
CACHE="$HOME/.w101d_cache"
PYTHON_DIR="$WINEPREFIX/drive_c/Python313"
WIN_PYTHON="$PYTHON_DIR/python.exe"

mkdir -p "$CACHE"

# ── Eski kalıntıları temizle ──────────────────
for old in "$WINEPREFIX/drive_c/Python311" "$WINEPREFIX/drive_c/Python312"; do
    [[ -d "$old" ]] && { echo "[setup] Temizleniyor: $old"; rm -rf "$old"; }
done

# ── winetricks + vcrun2019 ────────────────────
if ! command -v winetricks &>/dev/null; then
    echo "[setup] winetricks kuruluyor..."; brew install winetricks
fi
echo "[setup] vcrun2019 kuruluyor (pywin32 için)..."
WINEPREFIX="$WINEPREFIX" winetricks --unattended vcrun2019 2>/dev/null || true

# ── Python zip indir ──────────────────────────
if [[ ! -f "$CACHE/$EMBED_ZIP" ]]; then
    echo "[setup] Python $PYTHON_VERSION indiriliyor..."
    curl -L --progress-bar -o "$CACHE/$EMBED_ZIP" "$EMBED_URL"
fi

# ── Extract ───────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python extract ediliyor..."
    mkdir -p "$PYTHON_DIR"
    unzip -q "$CACHE/$EMBED_ZIP" -d "$PYTHON_DIR"
fi

# ── site-packages aç ─────────────────────────
PTH="$PYTHON_DIR/python313._pth"
if [[ -f "$PTH" ]] && grep -q "^#import site" "$PTH"; then
    echo "[setup] site-packages etkinleştiriliyor..."
    sed -i '' 's/^#import site/import site/' "$PTH"
fi

# ── pip ───────────────────────────────────────
[[ ! -f "$CACHE/get-pip.py" ]] && \
    curl -L --progress-bar -o "$CACHE/get-pip.py" "$GET_PIP_URL"
echo "[setup] pip kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" "$CACHE/get-pip.py" --quiet

# ── 1. regex BİNARY — her şeyden ÖNCE ────────
# poetry, wizwalker deps vs. regex'i transitive dep olarak çeker.
# cp313-win_amd64 wheel PyPI'da mevcut (2024.x+).
# --only-binary=:all: → source derleme KESİNLİKLE yasak.
echo "[setup] regex (binary wheel) ön-yükleniyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=:all: regex

# ── 2. Build araçları ─────────────────────────
# poetry       → wizwalker build backend (poetry.masonry.api)
# poetry-core  → poetry.core.masonry.api (patch sonrası)
# hatchling    → wizsprinter build backend
echo "[setup] Build araçları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        setuptools wheel poetry poetry-core hatchling

# ── 3. Deimos bağımlılıkları ─────────────────
echo "[setup] Deimos bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        "pywin32>=306" \
        "pypresence>=4.3.0" \
        "PySimpleGUI==4.60.5.1" \
        "loguru>=0.5.1" \
        "pyyaml>=6.0.1" \
        "requests>=2.32.3" \
        "pyperclip>=1.9.0" \
        "thefuzz>=0.22.1"

# ── 4. wizwalker ─────────────────────────────
WIZWALKER_DIR="$CACHE/wizwalker"
WIZSPRINTER_DIR="$CACHE/wizsprinter"

echo "[setup] wizwalker indiriliyor..."
rm -rf "$WIZWALKER_DIR"
git clone --quiet https://github.com/StarrFox/wizwalker.git "$WIZWALKER_DIR"

# pyproject.toml patch (macOS python3 ile — Wine Python değil):
# 1) regex "^2022.1.18" → ">=2024.0.0"  (cp313 binary wheel mevcut)
# 2) poetry>=0.12 → poetry-core          (modern build backend)
# 3) poetry.masonry.api → poetry.core.masonry.api
echo "[setup] wizwalker pyproject.toml patch ediliyor..."
python3 -c "
import pathlib
p = pathlib.Path('$WIZWALKER_DIR/pyproject.toml')
t = p.read_text()
t = t.replace('regex = \"^2022.1.18\"',        'regex = \">=2024.0.0\"')
t = t.replace('requires = [\"poetry>=0.12\"]', 'requires = [\"poetry-core\"]')
t = t.replace('poetry.masonry.api',            'poetry.core.masonry.api')
p.write_text(t)
print('[setup] wizwalker pyproject.toml patch OK')
"

# wizwalker'ı kur (poetry-core + regex>=2024 binary hazır)
echo "[setup] wizwalker kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        --no-build-isolation "$WIZWALKER_DIR"

# wizwalker'ın runtime dep'lerini garantiye al
echo "[setup] wizwalker bağımlılıkları tamamlanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        "loguru>=0.5.1" "aiofiles>=0.7.0" "pymem==1.8.3" \
        "appdirs>=1.4.4" "click>=7.1.2" "click_default_group>=1.2.2" \
        "terminaltables>=3.1.0" "janus>=0.6.1" "pefile>=2021.5.24"

# ── 5. wizsprinter ────────────────────────────
echo "[setup] wizsprinter indiriliyor..."
rm -rf "$WIZSPRINTER_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"

# wizsprinter'ın packages=["wizwalker"] hatası build'i bozar.
# --no-deps ile sadece Python dosyalarını kur, lark ayrıca pip ile kur.
echo "[setup] wizsprinter kuruluyor (--no-deps)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --no-deps --no-build-isolation "$WIZSPRINTER_DIR"

echo "[setup] lark kuruluyor (wizsprinter dep)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary "lark>=1.1.9"

# ── Doğrulama ─────────────────────────────────
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys; print(f'  Python     : {sys.version.split()[0]}')
import wizwalker;   print('  wizwalker  : OK')
import win32api;    print('  pywin32    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
import lark;        print('  lark       : OK')
"

echo ""
echo "[setup] Tamamlandı!"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
