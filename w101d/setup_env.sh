#!/usr/bin/env bash
# setup_env.sh — Wine içine Python 3.13 (full) + Deimos bağımlılıklarını kurar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.13.3"
PYTHON_INSTALLER="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_INSTALLER}"
CACHE="$HOME/.w101d_cache"
PYTHON_DIR="$WINEPREFIX/drive_c/Python313"
SITE_PKG="$PYTHON_DIR/Lib/site-packages"
WIN_PYTHON="$PYTHON_DIR/python.exe"

mkdir -p "$CACHE"

# ── Eski embeddable kalıntısını temizle ───────
for old in "$WINEPREFIX/drive_c/Python311" "$WINEPREFIX/drive_c/Python312"; do
    [[ -d "$old" ]] && { echo "[setup] Temizleniyor: $old"; rm -rf "$old"; }
done
if [[ -f "$PYTHON_DIR/python313._pth" ]]; then
    echo "[setup] Eski embeddable kurulum temizleniyor..."
    rm -rf "$PYTHON_DIR"
fi

# ── winetricks + vcrun2019 ────────────────────
if ! command -v winetricks &>/dev/null; then
    echo "[setup] winetricks kuruluyor..."; brew install winetricks
fi
echo "[setup] vcrun2019 kuruluyor..."
WINEPREFIX="$WINEPREFIX" winetricks --unattended vcrun2019 2>/dev/null || true

# ── Python full installer ─────────────────────
if [[ ! -f "$CACHE/$PYTHON_INSTALLER" ]]; then
    echo "[setup] Python $PYTHON_VERSION indiriliyor..."
    curl -L --progress-bar -o "$CACHE/$PYTHON_INSTALLER" "$PYTHON_URL"
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python kuruluyor (1-2 dk sürebilir)..."
    WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$CACHE/$PYTHON_INSTALLER" \
        /quiet \
        "TargetDir=C:\\Python313" \
        InstallAllUsers=0 \
        PrependPath=0 \
        Include_tcltk=1 \
        Include_pip=1 \
        Include_test=0
    echo "[setup] Python kurulumu tamamlandı."
fi

# ── pip bağımlılıkları ────────────────────────
echo "[setup] Paketler kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        "regex>=2024.0.0" \
        "loguru>=0.5.1" \
        "pymem==1.8.3" \
        "appdirs>=1.4.4" \
        "aiofiles>=0.7.0" \
        "click>=7.1.2" \
        "click_default_group>=1.2.2" \
        "terminaltables>=3.1.0" \
        "janus>=0.6.1" \
        "pefile>=2021.5.24" \
        "lark>=1.1.9" \
        "pywin32>=306" \
        "pypresence>=4.3.0" \
        "PySimpleGUI==4.60.5.1" \
        "pyyaml>=6.0.1" \
        "requests>=2.32.3" \
        "pyperclip>=1.9.0" \
        "thefuzz>=0.22.1"

# ── wizwalker: source'u direkt kopyala ────────
# Build sistemi yok → poetry/regex constraint sorunu yok
WIZWALKER_DIR="$CACHE/wizwalker"
echo "[setup] wizwalker indiriliyor..."
rm -rf "$WIZWALKER_DIR"
git clone --quiet https://github.com/StarrFox/wizwalker.git "$WIZWALKER_DIR"

# cli modülünü kaldır: aiomonitor → telnetlib (Python 3.13'te yok)
python3 -c "
import pathlib
init = pathlib.Path('$WIZWALKER_DIR/wizwalker/__init__.py')
t = init.read_text()
t = t.replace('from . import cli, combat, memory, utils',
              'from . import combat, memory, utils')
t = t.replace('from . import cli, memory, utils',
              'from . import memory, utils')
init.write_text(t)
print('[setup] wizwalker/__init__.py patch OK')
"

echo "[setup] wizwalker site-packages'a kopyalanıyor..."
rm -rf "$SITE_PKG/wizwalker"
cp -r "$WIZWALKER_DIR/wizwalker" "$SITE_PKG/wizwalker"

# ── wizsprinter: source'u direkt kopyala ──────
WIZSPRINTER_DIR="$CACHE/wizsprinter"
echo "[setup] wizsprinter indiriliyor..."
rm -rf "$WIZSPRINTER_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"

echo "[setup] wizsprinter site-packages'a kopyalanıyor..."
rm -rf "$SITE_PKG/wizsprinter"
cp -r "$WIZSPRINTER_DIR/wizsprinter" "$SITE_PKG/wizsprinter"

# ── Doğrulama ─────────────────────────────────
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys; print(f'  Python     : {sys.version.split()[0]}')
import tkinter;     print('  tkinter    : OK')
import wizwalker;   print('  wizwalker  : OK')
import wizsprinter; print('  wizsprinter: OK')
import win32api;    print('  pywin32    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
import lark;        print('  lark       : OK')
"

echo ""
echo "[setup] Tamamlandı!"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
