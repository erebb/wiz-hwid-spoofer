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

# Kısayol: regex'i HİÇBİR ZAMAN source'dan derleme
# Bu flag her pip çağrısına eklenir
NO_REGEX_BUILD="--only-binary=regex"

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

# ── 1. regex'i binary olarak ÖN-YÜKLE ────────
# regex cp313-cp313-win_amd64 wheel'ı PyPI'da mevcut.
# Daha sonraki HER pip adımı $NO_REGEX_BUILD taşıdığından
# pip bir daha source derlemeye çalışmaz.
echo "[setup] regex (binary wheel) ön-yükleniyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=:all: regex

# ── 2. setuptools + wheel + poetry ───────────
echo "[setup] Build araçları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet $NO_REGEX_BUILD --prefer-binary \
        setuptools wheel poetry-core poetry

# ── 3. Deimos bağımlılıkları ─────────────────
echo "[setup] Deimos bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet $NO_REGEX_BUILD --prefer-binary \
        "pywin32>=306" \
        "pypresence>=4.3.0" \
        "PySimpleGUI==4.60.5.1" \
        "loguru>=0.5.1,<0.6.0" \
        "pyyaml>=6.0.1" \
        "requests>=2.32.3" \
        "pyperclip>=1.9.0" \
        "thefuzz>=0.22.1"

# ── 4. wizwalker + wizsprinter ────────────────
WIZWALKER_DIR="$CACHE/wizwalker"
WIZSPRINTER_DIR="$CACHE/wizsprinter"

echo "[setup] wizwalker indiriliyor..."
rm -rf "$WIZWALKER_DIR"
git clone --quiet https://github.com/StarrFox/wizwalker.git "$WIZWALKER_DIR"

echo "[setup] wizsprinter indiriliyor..."
rm -rf "$WIZSPRINTER_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"

# wizwalker regex<2023 constraint'i cp313 ile uyumsuz.
# --no-deps: version constraint kontrolünü bypass et.
# Bağımlılıkları (regex dahil) zaten binary olarak önceden kurduk.
echo "[setup] wizwalker kuruluyor (--no-deps)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --no-deps --no-build-isolation "$WIZWALKER_DIR"

echo "[setup] wizwalker bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet $NO_REGEX_BUILD --prefer-binary \
        pymem pywin32 websockets regex

echo "[setup] wizsprinter kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet $NO_REGEX_BUILD --prefer-binary \
        --no-build-isolation "$WIZSPRINTER_DIR"

# ── Doğrulama ─────────────────────────────────
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys; print(f'  Python     : {sys.version.split()[0]}')
import wizwalker;   print('  wizwalker  : OK')
import win32api;    print('  pywin32    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
"

echo ""
echo "[setup] Tamamlandı!"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
