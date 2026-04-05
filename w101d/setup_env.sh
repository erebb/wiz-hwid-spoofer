#!/usr/bin/env bash
# setup_env.sh — Wine içine Python 3.13 (full installer) + Deimos bağımlılıklarını kurar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.13.3"
# Embeddable zip DEĞİL — full installer (tkinter dahil)
PYTHON_INSTALLER="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_INSTALLER}"
CACHE="$HOME/.w101d_cache"
PYTHON_DIR="$WINEPREFIX/drive_c/Python313"
WIN_PYTHON="$PYTHON_DIR/python.exe"

mkdir -p "$CACHE"

# ── Eski kalıntıları temizle ──────────────────
for old in "$WINEPREFIX/drive_c/Python311" "$WINEPREFIX/drive_c/Python312"; do
    [[ -d "$old" ]] && { echo "[setup] Temizleniyor: $old"; rm -rf "$old"; }
done
# Eski embeddable kurulumu varsa sil (tkinter yoktu)
if [[ -f "$PYTHON_DIR/python313._pth" ]]; then
    echo "[setup] Eski embeddable Python temizleniyor (tkinter yoktu)..."
    rm -rf "$PYTHON_DIR"
fi

# ── winetricks + vcrun2019 ────────────────────
if ! command -v winetricks &>/dev/null; then
    echo "[setup] winetricks kuruluyor..."; brew install winetricks
fi
echo "[setup] vcrun2019 kuruluyor (pywin32 için)..."
WINEPREFIX="$WINEPREFIX" winetricks --unattended vcrun2019 2>/dev/null || true

# ── Python full installer ─────────────────────
# Full installer tkinter, pip ve tüm stdlib'i içerir.
if [[ ! -f "$CACHE/$PYTHON_INSTALLER" ]]; then
    echo "[setup] Python $PYTHON_VERSION full installer indiriliyor (~25MB)..."
    curl -L --progress-bar -o "$CACHE/$PYTHON_INSTALLER" "$PYTHON_URL"
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python kuruluyor (bu 1-2 dk sürebilir)..."
    WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$CACHE/$PYTHON_INSTALLER" \
        /quiet \
        "TargetDir=C:\\Python313" \
        InstallAllUsers=0 \
        PrependPath=0 \
        Include_tcltk=1 \
        Include_pip=1 \
        Include_test=0
    echo "[setup] Python kurulumu tamamlandı."
else
    echo "[setup] Python zaten kurulu, atlanıyor."
fi

# ── 1. regex BİNARY — her şeyden ÖNCE ────────
echo "[setup] regex (binary wheel) ön-yükleniyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=:all: regex

# ── 2. Build araçları ─────────────────────────
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

echo "[setup] wizwalker patch ediliyor..."
python3 -c "
import pathlib

# pyproject.toml: regex constraint + build backend
p = pathlib.Path('$WIZWALKER_DIR/pyproject.toml')
t = p.read_text()
t = t.replace('regex = \"^2022.1.18\"',        'regex = \">=2024.0.0\"')
t = t.replace('requires = [\"poetry>=0.12\"]', 'requires = [\"poetry-core\"]')
t = t.replace('poetry.masonry.api',            'poetry.core.masonry.api')
p.write_text(t)
print('[setup] pyproject.toml patch OK')

# wizwalker/__init__.py: cli import kaldır
# aiomonitor 0.4.x -> telnetlib -> Python 3.13'te yok
init = pathlib.Path('$WIZWALKER_DIR/wizwalker/__init__.py')
t2 = init.read_text()
t2 = t2.replace('from . import cli, combat, memory, utils',
                'from . import combat, memory, utils')
t2 = t2.replace('from . import cli, memory, utils',
                'from . import memory, utils')
init.write_text(t2)
print('[setup] __init__.py cli patch OK')
"

echo "[setup] wizwalker kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        --no-build-isolation "$WIZWALKER_DIR"

echo "[setup] wizwalker bağımlılıkları tamamlanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        "aiofiles>=0.7.0" "pymem==1.8.3" \
        "appdirs>=1.4.4" "click>=7.1.2" "click_default_group>=1.2.2" \
        "terminaltables>=3.1.0" "janus>=0.6.1" "pefile>=2021.5.24"

# ── 5. wizsprinter ────────────────────────────
echo "[setup] wizsprinter indiriliyor..."
rm -rf "$WIZSPRINTER_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"

echo "[setup] wizsprinter kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --no-deps --no-build-isolation "$WIZSPRINTER_DIR"

WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary "lark>=1.1.9"

# ── Doğrulama ─────────────────────────────────
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys; print(f'  Python     : {sys.version.split()[0]}')
import wizwalker;   print('  wizwalker  : OK')
import win32api;    print('  pywin32    : OK')
import tkinter;     print('  tkinter    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
import lark;        print('  lark       : OK')
"

echo ""
echo "[setup] Tamamlandı!"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
