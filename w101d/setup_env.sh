#!/usr/bin/env bash
# setup_env.sh — Wine içine Windows Python + Deimos bağımlılıklarını kurar.
# Tek seferlik kurulum scriptidir.
#
# Kullanım: bash w101d/setup_env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.11.9"
PYTHON_INSTALLER="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_INSTALLER}"
DOWNLOAD_DIR="$HOME/.w101d_cache"

# Wine prefix içindeki Python yolu (kurulumdan sonra)
WIN_PYTHON="$WINEPREFIX/drive_c/Python311/python.exe"

# ─────────────────────────────────────────────
# 1. Python installer'ı indir (yoksa)
# ─────────────────────────────────────────────
mkdir -p "$DOWNLOAD_DIR"

if [[ ! -f "$DOWNLOAD_DIR/$PYTHON_INSTALLER" ]]; then
    echo "[setup] Python $PYTHON_VERSION indiriliyor..."
    curl -L --progress-bar -o "$DOWNLOAD_DIR/$PYTHON_INSTALLER" "$PYTHON_URL"
else
    echo "[setup] Python installer zaten mevcut, atlanıyor."
fi

# ─────────────────────────────────────────────
# 2. Wine içine Python kur (yoksa)
# ─────────────────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python Wine içine kuruluyor (bu birkaç dakika alabilir)..."
    WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$DOWNLOAD_DIR/$PYTHON_INSTALLER" \
        /quiet \
        InstallAllUsers=0 \
        PrependPath=1 \
        Include_test=0
    echo "[setup] Python kuruldu."
else
    echo "[setup] Python zaten kurulu: $WIN_PYTHON"
fi

# ─────────────────────────────────────────────
# 3. pip bağımlılıklarını kur
# ─────────────────────────────────────────────
echo "[setup] pip güncelleniyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --upgrade pip --quiet

echo "[setup] Deimos bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet \
    "pywin32>=306" \
    "pypresence>=4.3.0" \
    "PySimpleGUI==4.60.5" \
    "loguru>=0.7.2" \
    "pyyaml>=6.0.1" \
    "requests>=2.32.3" \
    "pyperclip>=1.9.0" \
    "thefuzz>=0.22.1"

echo "[setup] wizwalker kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet \
    "git+https://github.com/StarrFox/wizwalker.git@lib-update"

echo "[setup] wizsprinter kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet \
    "git+https://github.com/Deimos-Wizard101/WizSprinter.git@lib-update"

# ─────────────────────────────────────────────
# 4. Doğrulama
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
echo "  bash w101d/run_deimos.sh /path/to/Deimos-Wizard101"
