#!/usr/bin/env bash
# setup_single.sh — wiz_tools.py için gereken her şeyi Wizard101'in kendi
#                   Wine prefix'ine kurar. Ayrı bir prefix açılmaz.
#
# Kurulumlar:
#   • Python 3.13 (full installer, Wine içinde)
#   • wizwalker (Deimos fork / development branch)
#   • pymem, pywin32 ve diğer bağımlılıklar
#   • wine64-preloader imzalama (get-task-allow — pymem memory erişimi)
#
# Kullanım:  bash w101d/setup_single.sh
# Gereksinim: Homebrew kurulu olmalı (yoksa otomatik kurar)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_VERSION="3.13.3"
PYTHON_INSTALLER="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_INSTALLER}"
CACHE="$HOME/.w101d_cache"
WIZWALKER_DIR="$CACHE/wizwalker_single"

mkdir -p "$CACHE"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Homebrew + Wine
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_ensure_homebrew() {
    command -v brew &>/dev/null && return
    echo "[setup] Homebrew bulunamadı, kuruluyor..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ -f "/opt/homebrew/bin/brew" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f "/usr/local/bin/brew"    ]] && eval "$(/usr/local/bin/brew shellenv)"
}

_find_wine_bin() {
    for c in \
        "/opt/homebrew/bin/wine64" "/opt/homebrew/bin/wine" \
        "/usr/local/bin/wine64"    "/usr/local/bin/wine"; do
        [[ -x "$c" ]] && echo "$c" && return
    done
    if command -v brew &>/dev/null; then
        local p; p=$(brew --prefix 2>/dev/null)
        for c in "$p/bin/wine64" "$p/bin/wine"; do
            [[ -x "$c" ]] && echo "$c" && return
        done
    fi
    echo ""
}

_ensure_homebrew

if [[ -z "$(_find_wine_bin)" ]]; then
    echo "[setup] wine-stable bulunamadı, kuruluyor..."
    brew install --cask wine-stable
fi

WINE_BIN=$(_find_wine_bin)
echo "[setup] Wine : $WINE_BIN"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Wizard101 Wine prefix'ini bul
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_find_wiz_exe() {
    local candidates=(
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    find "$HOME/Library" -name "WizardGraphicalClient.exe" 2>/dev/null | head -1
}

echo "[setup] Wizard101 aranıyor..."
WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[setup] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[setup] Lütfen tam yolunu girin:"
    read -r WIZ_EXE
    if [[ ! -f "$WIZ_EXE" ]]; then
        echo "[setup] HATA: Dosya bulunamadı: $WIZ_EXE" >&2
        exit 1
    fi
fi

# drive_c'nin üstü = Wine prefix
WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
export WINEPREFIX="$WIZ_PREFIX"
export WINEARCH="win64"

PYTHON_DIR="$WIZ_PREFIX/drive_c/Python313"
SITE_PKG="$PYTHON_DIR/Lib/site-packages"
WIN_PYTHON="$PYTHON_DIR/python.exe"

echo "[setup] Wizard101 prefix : $WIZ_PREFIX"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Python 3.13 kur (yoksa)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Eski embeddable kalıntısını temizle
if [[ -f "$PYTHON_DIR/python313._pth" ]]; then
    echo "[setup] Eski embeddable Python temizleniyor..."
    rm -rf "$PYTHON_DIR"
fi

if [[ ! -f "$CACHE/$PYTHON_INSTALLER" ]]; then
    echo "[setup] Python $PYTHON_VERSION indiriliyor..."
    curl -L --progress-bar -o "$CACHE/$PYTHON_INSTALLER" "$PYTHON_URL"
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[setup] Python kuruluyor (1-2 dk sürebilir)..."
    WINEPREFIX="$WIZ_PREFIX" "$WINE_BIN" "$CACHE/$PYTHON_INSTALLER" \
        /quiet \
        "TargetDir=C:\\Python313" \
        InstallAllUsers=0 \
        PrependPath=0 \
        Include_tcltk=0 \
        Include_pip=1 \
        Include_test=0
    echo "[setup] Python kuruldu."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. pip bağımlılıkları
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "[setup] pip güncelleniyor..."
WINEPREFIX="$WIZ_PREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --upgrade pip

echo "[setup] Bağımlılıklar kuruluyor..."
WINEPREFIX="$WIZ_PREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary \
        "pymem==1.8.3" \
        "pywin32>=306" \
        "loguru>=0.7.2" \
        "aiofiles>=0.7.0" \
        "lark>=1.1.9" \
        "pefile>=2021.5.24" \
        "janus>=0.6.1"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. wizwalker (Deimos fork / development)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "[setup] wizwalker indiriliyor..."
rm -rf "$WIZWALKER_DIR"
git clone --quiet --branch development \
    https://github.com/Deimos-Wizard101/wizwalker.git "$WIZWALKER_DIR"

# Python 3.13: telnetlib kaldırıldı → cli import'unu çıkar
echo "[setup] wizwalker Python 3.13 patch uygulanıyor..."
python3 -c "
import pathlib
init = pathlib.Path('$WIZWALKER_DIR/wizwalker/__init__.py')
t = init.read_text()
for old in [
    'from . import cli, combat, memory, utils',
    'from . import cli, memory, utils',
    'from . import cli, utils',
]:
    if old in t:
        t = t.replace(old, old.replace('cli, ', ''))
        break
init.write_text(t)
print('[setup] patch OK')
"

echo "[setup] wizwalker site-packages'a kopyalanıyor..."
rm -rf "$SITE_PKG/wizwalker"
cp -r "$WIZWALKER_DIR/wizwalker" "$SITE_PKG/wizwalker"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. wiz_tools.py'yi prefix'e kopyala
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "[setup] wiz_tools.py kopyalanıyor..."
cp "$SCRIPT_DIR/wiz_tools.py" "$WIZ_PREFIX/drive_c/wiz_tools.py"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. wine64-preloader imzala (pymem memory erişimi)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "[setup] Wine memory erişim izni yapılandırılıyor..."

real_wine=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$WINE_BIN" 2>/dev/null || echo "$WINE_BIN")
bin_dir=$(dirname "$real_wine")

ent=$(mktemp /tmp/wine-ent-XXXXXX.plist)
cat > "$ent" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
PLIST

signed=0
for bin in \
    "$bin_dir/wine64-preloader" \
    "$bin_dir/wine-preloader" \
    "$real_wine" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64-preloader" \
    "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine-preloader"; do
    [[ -x "$bin" ]] || continue
    if codesign --entitlements "$ent" --force -s - "$bin" 2>/dev/null; then
        echo "[setup] İmzalandı: $(basename "$bin")"
        signed=1
    fi
done
rm -f "$ent"

if [[ "$signed" -eq 0 ]]; then
    echo "[setup] UYARI: Wine imzalanamadı → speedhack memory erişimi çalışmayabilir."
else
    echo "[setup] Memory erişim izni verildi (sudo gerekmez)."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. Doğrulama
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WIZ_PREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys
print(f'  Python    : {sys.version.split()[0]}')
import pymem;     print('  pymem     : OK')
import win32api;  print('  pywin32   : OK')
import wizwalker; print('  wizwalker : OK')
import lark;      print('  lark      : OK')
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kurulum tamamlandı!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Kullanım:"
echo "    bash w101d/run_tools.sh            → menü"
echo "    bash w101d/run_tools.sh speed 3    → 3x speedhack"
echo "    bash w101d/run_tools.sh quest      → quest TP"
echo "    bash w101d/run_tools.sh both 3     → ikisi birden"
echo ""
echo "  brew upgrade sonrası:"
echo "    bash w101d/resign_wine.sh"
