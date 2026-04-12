#!/usr/bin/env bash
# setup_env.sh — macOS/Wine için otomatik yama ve dosya yapılandırmalı sürüm.
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
DEIMOS_DIR="$CACHE/Deimos"

mkdir -p "$CACHE"

# 1. Python ve Temel Bağımlılıklar (Standart Kurulum)
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python kuruluyor..."
    curl -L -o "$CACHE/$PYTHON_INSTALLER" "$PYTHON_URL"
    WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$CACHE/$PYTHON_INSTALLER" /quiet TargetDir="C:\\Python313" InstallAllUsers=0 Include_pip=1
fi

echo "[setup] Deimos indiriliyor..."
rm -rf "$DEIMOS_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/Deimos-Wizard101.git "$DEIMOS_DIR"

# 2. Gerekli Python Paketleri
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -m pip install --quiet \
    regex thefuzz loguru pyperclip requests pypresence pywin32 pyyaml pymem appdirs aiofiles click janus pefile lark

# 3. ROOT.WAD Otomatik Taşıma
echo "[setup] root.wad dosyası aranıyor..."
WIZ_WAD=$(find "$HOME/Library/Application Support/Wizard101" -name "root.wad" -maxdepth 15 2>/dev/null | head -1)

if [[ -f "$WIZ_WAD" ]]; then
    echo "[setup] root.wad bulundu, kopyalanıyor..."
    cp "$WIZ_WAD" "$DEIMOS_DIR/"
else
    echo "[setup] UYARI: root.wad bulunamadı, manuel taşımanız gerekebilir."
fi

# 4. Deimos.py Otomatik Yama (Klasörden okuma desteği)
echo "[setup] Deimos.py yamalanıyor..."
python3 -c "
import pathlib
import re
p = pathlib.Path('$DEIMOS_DIR/Deimos.py')
c = p.read_text(encoding='utf-8', errors='ignore')
patch = '''
# --- ROOT.WAD KLASORDEN OKUMA YAMASI (macOS) ---
import os, pathlib, wizwalker.file_readers.wad
_orig = wizwalker.file_readers.wad.Wad.from_game_data
def _patched(cls, name, *args, **kwargs):
    local = pathlib.Path(os.getcwd()) / f'{name}.wad'
    return cls(local) if local.exists() else _orig.__func__(cls, name, *args, **kwargs)
wizwalker.file_readers.wad.Wad.from_game_data = classmethod(_patched)
# ----------------------------------------------
'''
if 'ROOT.WAD' not in c:
    c = re.sub(r'(import [^\n]+\n)', r'\g<1>' + patch + '\n', c, count=1)
    p.write_text(c, encoding='utf-8')
    print('[setup] Deimos.py yaması OK')
"

# 5. Wine Memory İzni (resign_wine mantığı)
echo "[setup] Wine memory erişim izni veriliyor..."
ent=$(mktemp /tmp/ent.plist)
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>' > "$ent"
codesign --entitlements "$ent" --force -s - "$(dirname $(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$WINE_BIN"))/wine64-preloader" 2>/dev/null || true

echo "[setup] Tamamlandı! Artık sadece 'bash run_deimos.sh' demen yeterli."