#!/usr/bin/env bash
# setup_env.sh — Wizard101'in kendi Wine'ına Python (embeddable) + Deimos bağımlılıklarını kurar.
# Tek seferlik kurulum scriptidir. Python installer (.exe) kullanmaz — zip ile extract eder.
#
# Kullanım: bash setup_env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.13.3"
EMBED_ZIP="python-${PYTHON_VERSION}-embed-amd64.zip"
EMBED_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${EMBED_ZIP}"
GET_PIP_URL="https://bootstrap.pypa.io/get-pip.py"
DOWNLOAD_DIR="$HOME/.w101d_cache"

# Wine prefix içindeki Python kurulum dizini
PYTHON_DIR="$WINEPREFIX/drive_c/Python313"
WIN_PYTHON="$PYTHON_DIR/python.exe"

# ─────────────────────────────────────────────
# 1. Eski Python311 varsa kaldır
# ─────────────────────────────────────────────
OLD_PYTHON_DIR="$WINEPREFIX/drive_c/Python311"
if [[ -d "$OLD_PYTHON_DIR" ]]; then
    echo "[setup] Eski Python311 siliniyor..."
    rm -rf "$OLD_PYTHON_DIR"
fi

# ─────────────────────────────────────────────
# 2. Embeddable Python zip'i indir
# ─────────────────────────────────────────────
mkdir -p "$DOWNLOAD_DIR"

if [[ ! -f "$DOWNLOAD_DIR/$EMBED_ZIP" ]]; then
    echo "[setup] Python $PYTHON_VERSION embeddable indiriliyor..."
    curl -L --progress-bar -o "$DOWNLOAD_DIR/$EMBED_ZIP" "$EMBED_URL"
else
    echo "[setup] Python zip zaten mevcut, atlanıyor."
fi

# ─────────────────────────────────────────────
# 3. Wine prefix içine extract et
# ─────────────────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python Wine prefix'e extract ediliyor..."
    mkdir -p "$PYTHON_DIR"
    unzip -q "$DOWNLOAD_DIR/$EMBED_ZIP" -d "$PYTHON_DIR"
    echo "[setup] Python extract edildi: $PYTHON_DIR"
else
    echo "[setup] Python zaten mevcut: $WIN_PYTHON"
fi

# ─────────────────────────────────────────────
# 4. Embeddable Python'da site-packages'i etkinleştir
#    (python313._pth dosyasında 'import site' satırını aç)
# ─────────────────────────────────────────────
PTH_FILE="$PYTHON_DIR/python313._pth"
if [[ -f "$PTH_FILE" ]] && grep -q "^#import site" "$PTH_FILE"; then
    echo "[setup] site-packages etkinleştiriliyor..."
    sed -i '' 's/^#import site/import site/' "$PTH_FILE"
fi

# ─────────────────────────────────────────────
# 5. pip kur (get-pip.py ile)
# ─────────────────────────────────────────────
if [[ ! -f "$DOWNLOAD_DIR/get-pip.py" ]]; then
    echo "[setup] get-pip.py indiriliyor..."
    curl -L --progress-bar -o "$DOWNLOAD_DIR/get-pip.py" "$GET_PIP_URL"
fi

echo "[setup] pip kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" "$DOWNLOAD_DIR/get-pip.py" --quiet

# ─────────────────────────────────────────────
# 6. Build backend'leri kur
# ─────────────────────────────────────────────
echo "[setup] build backend'ler kuruluyor (poetry, hatchling)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet poetry-core poetry hatchling

# ─────────────────────────────────────────────
# 7. Deimos bağımlılıklarını kur
# ─────────────────────────────────────────────
echo "[setup] Deimos bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet \
    "pywin32>=306" \
    "pypresence>=4.3.0" \
    "PySimpleGUI==4.60.5.1" \
    "loguru>=0.5.1,<0.6.0" \
    "pyyaml>=6.0.1" \
    "requests>=2.32.3" \
    "pyperclip>=1.9.0" \
    "thefuzz>=0.22.1"

# ─────────────────────────────────────────────
# 8. wizwalker ve wizsprinter
# ─────────────────────────────────────────────
WIZWALKER_DIR="$DOWNLOAD_DIR/wizwalker"
WIZSPRINTER_DIR="$DOWNLOAD_DIR/wizsprinter"

echo "[setup] wizwalker indiriliyor (Mac git ile)..."
if [[ ! -d "$WIZWALKER_DIR" ]]; then
    git clone --quiet https://github.com/StarrFox/wizwalker.git "$WIZWALKER_DIR"
else
    git -C "$WIZWALKER_DIR" pull --quiet
fi

echo "[setup] wizsprinter indiriliyor (Mac git ile)..."
if [[ ! -d "$WIZSPRINTER_DIR" ]]; then
    git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"
else
    git -C "$WIZSPRINTER_DIR" pull --quiet
fi

echo "[setup] wizwalker kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet --no-build-isolation "$WIZWALKER_DIR"

echo "[setup] wizsprinter kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet --no-build-isolation "$WIZSPRINTER_DIR"

# ─────────────────────────────────────────────
# 9. Doğrulama
# ─────────────────────────────────────────────
echo ""
echo "[setup] Kurulum doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys
print(f'  Python : {sys.version.split()[0]}')
import wizwalker; print('  wizwalker : OK')
import win32api;  print('  pywin32   : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
"

echo ""
echo "[setup] Kurulum tamamlandı! Deimos'u başlatmak için:"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
