#!/usr/bin/env bash
# setup_env.sh — Homebrew Wine içine Python + Deimos bağımlılıklarını otomatik kurar.
# Tek seferlik kurulum scriptidir.
#
# Kullanım: bash setup_env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

PYTHON_VERSION="3.11.9"
EMBED_ZIP="python-${PYTHON_VERSION}-embed-amd64.zip"
EMBED_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${EMBED_ZIP}"
GET_PIP_URL="https://bootstrap.pypa.io/get-pip.py"
DOWNLOAD_DIR="$HOME/.w101d_cache"

PYTHON_DIR="$WINEPREFIX/drive_c/Python311"
WIN_PYTHON="$PYTHON_DIR/python.exe"

mkdir -p "$DOWNLOAD_DIR"

# ─────────────────────────────────────────────
# 1. winetricks otomatik kur (gerekli DLL'ler için)
# ─────────────────────────────────────────────
if ! command -v winetricks &>/dev/null; then
    echo "[setup] winetricks kuruluyor..."
    brew install winetricks
fi

# ─────────────────────────────────────────────
# 2. Gerekli Windows DLL'lerini kur
#    vcrun2019 = Visual C++ runtime (pywin32 için şart)
#    dotnet48  = .NET 4.8 (bazı Python paketleri için)
# ─────────────────────────────────────────────
echo "[setup] Gerekli Windows DLL'leri kuruluyor (vcrun2019)..."
WINEPREFIX="$WINEPREFIX" winetricks --unattended vcrun2019 2>/dev/null || \
    echo "[setup] vcrun2019 kurulumu atlandı (zaten kurulu olabilir)."

# ─────────────────────────────────────────────
# 3. Eski Python 3.13 kalıntısını temizle (varsa)
# ─────────────────────────────────────────────
OLD_PYTHON_DIR="$WINEPREFIX/drive_c/Python313"
if [[ -d "$OLD_PYTHON_DIR" ]]; then
    echo "[setup] Eski Python 3.13 temizleniyor..."
    rm -rf "$OLD_PYTHON_DIR"
fi

# ─────────────────────────────────────────────
# 4. Embeddable Python zip'i indir
# ─────────────────────────────────────────────
if [[ ! -f "$DOWNLOAD_DIR/$EMBED_ZIP" ]]; then
    echo "[setup] Python $PYTHON_VERSION indiriliyor..."
    curl -L --progress-bar -o "$DOWNLOAD_DIR/$EMBED_ZIP" "$EMBED_URL"
else
    echo "[setup] Python zip zaten mevcut, atlanıyor."
fi

# ─────────────────────────────────────────────
# 5. Wine prefix içine extract et
# ─────────────────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python extract ediliyor: $PYTHON_DIR"
    mkdir -p "$PYTHON_DIR"
    unzip -q "$DOWNLOAD_DIR/$EMBED_ZIP" -d "$PYTHON_DIR"
else
    echo "[setup] Python zaten mevcut: $WIN_PYTHON"
fi

# ─────────────────────────────────────────────
# 6. site-packages etkinleştir (python311._pth)
# ─────────────────────────────────────────────
PTH_FILE="$PYTHON_DIR/python311._pth"
if [[ -f "$PTH_FILE" ]] && grep -q "^#import site" "$PTH_FILE"; then
    echo "[setup] site-packages etkinleştiriliyor..."
    sed -i '' 's/^#import site/import site/' "$PTH_FILE"
fi

# ─────────────────────────────────────────────
# 7. pip kur
# ─────────────────────────────────────────────
if [[ ! -f "$DOWNLOAD_DIR/get-pip.py" ]]; then
    echo "[setup] get-pip.py indiriliyor..."
    curl -L --progress-bar -o "$DOWNLOAD_DIR/get-pip.py" "$GET_PIP_URL"
fi

echo "[setup] pip kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" "$DOWNLOAD_DIR/get-pip.py" --quiet

# ─────────────────────────────────────────────
# 8. setuptools + wheel (build backend için şart)
#    Embeddable zip bunları içermez, ayrıca kurulmalı.
# ─────────────────────────────────────────────
echo "[setup] setuptools + wheel kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet --prefer-binary \
    setuptools wheel

# ─────────────────────────────────────────────
# 9. Build backend'ler
# ─────────────────────────────────────────────
echo "[setup] Build backend'ler kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet --prefer-binary \
    poetry-core poetry hatchling

# ─────────────────────────────────────────────
# 10. Deimos bağımlılıkları
#    --prefer-binary: C extension paketleri (regex, cffi vb.) için
#    hazır wheel kullan, Wine içinde MSVC derleyici olmadığından
#    kaynak koddan derleme başarısız olur.
# ─────────────────────────────────────────────
echo "[setup] Deimos bağımlılıkları kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet --prefer-binary \
    "pywin32>=306" \
    "pypresence>=4.3.0" \
    "PySimpleGUI==4.60.5.1" \
    "loguru>=0.5.1,<0.6.0" \
    "pyyaml>=6.0.1" \
    "requests>=2.32.3" \
    "pyperclip>=1.9.0" \
    "thefuzz>=0.22.1"

# pywin32 post-install (servis DLL'lerini register eder)
echo "[setup] pywin32 post-install çalıştırılıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    "$PYTHON_DIR/Lib/site-packages/win32/pythonservice.exe" \
    --register 2>/dev/null || true

# ─────────────────────────────────────────────
# 11. wizwalker + wizsprinter
# ─────────────────────────────────────────────
WIZWALKER_DIR="$DOWNLOAD_DIR/wizwalker"
WIZSPRINTER_DIR="$DOWNLOAD_DIR/wizsprinter"

echo "[setup] wizwalker indiriliyor..."
if [[ ! -d "$WIZWALKER_DIR" ]]; then
    git clone --quiet https://github.com/StarrFox/wizwalker.git "$WIZWALKER_DIR"
else
    git -C "$WIZWALKER_DIR" pull --quiet
fi

echo "[setup] wizsprinter indiriliyor..."
if [[ ! -d "$WIZSPRINTER_DIR" ]]; then
    git clone --quiet https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"
else
    git -C "$WIZSPRINTER_DIR" pull --quiet
fi

echo "[setup] wizwalker kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary --no-build-isolation "$WIZWALKER_DIR"

echo "[setup] wizsprinter kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary --no-build-isolation "$WIZSPRINTER_DIR"

# ─────────────────────────────────────────────
# 12. Doğrulama
# ─────────────────────────────────────────────
echo ""
echo "[setup] Kurulum doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys
print(f'  Python     : {sys.version.split()[0]}')
import wizwalker;   print('  wizwalker  : OK')
import win32api;    print('  pywin32    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
"

echo ""
echo "[setup] Tamamlandı! Deimos başlatmak için:"
echo "  bash run_deimos.sh /path/to/Deimos-Wizard101"
