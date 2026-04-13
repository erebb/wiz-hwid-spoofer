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

WIZWALKER_DIR="$CACHE/wizwalker"
WIZSPRINTER_DIR="$CACHE/wizsprinter"
DEIMOS_DIR="$CACHE/Deimos"

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

# ── pip upgrade ───────────────────────────────
echo "[setup] pip güncelleniyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --upgrade pip
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install pycryptodome
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m	pip3 install twofish
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" 
    -m pip install pytesseract opencv-python


# ── Deimos reposunu indir ────────────────────
# PySimpleGUI wheel ve kaynak kod için
echo "[setup] Deimos reposu indiriliyor..."
rm -rf "$DEIMOS_DIR"
git clone --quiet https://github.com/Deimos-Wizard101/Deimos-Wizard101.git "$DEIMOS_DIR"

# ── pip bağımlılıkları (requirements.txt'ten) ─
echo "[setup] Paketler kuruluyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --only-binary=regex --prefer-binary \
        "regex>=2024.0.0" \
        "thefuzz>=0.22.1" \
        "loguru>=0.7.2" \
        "pyperclip>=1.9.0" \
        "requests>=2.32.3" \
        "pypresence>=4.3.0" \
        "pywin32>=306" \
        "pyyaml>=6.0.1" \
        "pymem==1.8.3" \
        "appdirs>=1.4.4" \
        "aiofiles>=0.7.0" \
        "click>=7.1.2" \
        "click_default_group>=1.2.2" \
        "terminaltables>=3.1.0" \
        "janus>=0.6.1" \
        "pefile>=2021.5.24" \
        "lark>=1.1.9"

# ── Ekran okuma bağımlılıkları (questing için) ─
# is_visible_by_path → Pillow (görüntü yükleme) + opencv (template matching)
# Dialogue/combat memory tabanlı çalışır; questing ekran okur → bu paketler gerekli.
echo "[setup] Ekran okuma paketleri kuruluyor (Pillow, opencv)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet --prefer-binary \
        "Pillow>=10.0.0" \
        "opencv-python-headless>=4.8.0" \
        "numpy>=1.26.0"

# PySimpleGUI — Deimos'un kendi wheel'ından (PyPI'dan kaldırıldı)
echo "[setup] PySimpleGUI kuruluyor (Deimos wheel)..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" \
    -m pip install --quiet "$DEIMOS_DIR/wheels/PySimpleGUI-4.60.5-py3-none-any.whl"

# ── wizwalker: Deimos fork, development branch ─
echo "[setup] wizwalker indiriliyor (Deimos fork / development)..."
rm -rf "$WIZWALKER_DIR"
git clone --quiet --branch development \
    https://github.com/Deimos-Wizard101/wizwalker.git "$WIZWALKER_DIR"

# cli import kaldır: aiomonitor → telnetlib → Python 3.13'te yok
echo "[setup] wizwalker patch ediliyor..."
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
print('[setup] wizwalker/__init__.py patch OK')
"

echo "[setup] wizwalker site-packages'a kopyalanıyor..."
rm -rf "$SITE_PKG/wizwalker"
cp -r "$WIZWALKER_DIR/wizwalker" "$SITE_PKG/wizwalker"

# WIZ_PID cross-wineserver patch: ClientHandler.get_new_clients() içine
# env-var tabanlı bypass ekler. macOS'ta Wine EnumProcesses yalnızca aynı
# wineserver'ı görür; WIZ_PID ile direkt Client(pid) yaratarak bunu atlatır.
echo "[setup] wizwalker WIZ_PID cross-wineserver patch uygulanıyor..."
python3 -c "
import pathlib
handler = pathlib.Path('$SITE_PKG/wizwalker/client_handler.py')
content = handler.read_text()
PATCH = '''
# ── WIZ_PID cross-wineserver patch (macOS / Homebrew Wine) ──────────────────
import os as _os

_orig_get_new_clients = ClientHandler.get_new_clients

def _get_new_clients_patched(self):
    _pid_str = _os.environ.get(\"WIZ_PID\", \"\").strip()
    if _pid_str:
        try:
            from wizwalker.client import Client
            _pid = int(_pid_str)
            if not any(c.process_id == _pid for c in self.clients):
                _c = Client(_pid)
                self.clients.append(_c)
                return [_c]
            return []
        except Exception as _e:
            print(f\"[WIZ_PID] Direkt baglanti basarisiz ({_e}), normal kesif deneniyor...\")
    return _orig_get_new_clients(self)

ClientHandler.get_new_clients = _get_new_clients_patched
# ─────────────────────────────────────────────────────────────────────────────
'''
if '_get_new_clients_patched' not in content:
    handler.write_text(content + PATCH)
    print('[setup] wizwalker WIZ_PID patch OK')
else:
    print('[setup] wizwalker WIZ_PID patch zaten mevcut')
"

# ── wizsprinter: lib-update branch ────────────
echo "[setup] wizsprinter indiriliyor (lib-update branch)..."
rm -rf "$WIZSPRINTER_DIR"
git clone --quiet --branch lib-update \
    https://github.com/Deimos-Wizard101/WizSprinter.git "$WIZSPRINTER_DIR"

echo "[setup] wizsprinter site-packages'a kopyalanıyor..."
mkdir -p "$SITE_PKG/wizwalker/extensions"
rm -rf "$SITE_PKG/wizwalker/extensions/wizsprinter"
cp -r "$WIZSPRINTER_DIR/wizwalker/extensions/wizsprinter" \
      "$SITE_PKG/wizwalker/extensions/wizsprinter"

# ── Doğrulama ─────────────────────────────────
echo ""
echo "[setup] Doğrulanıyor..."
WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$WIN_PYTHON" -c "
import sys; print(f'  Python     : {sys.version.split()[0]}')
import tkinter;     print('  tkinter    : OK')
import wizwalker;   print('  wizwalker  : OK')
import wizwalker.extensions.wizsprinter; print('  wizsprinter: OK')
import win32api;    print('  pywin32    : OK')
import PySimpleGUI; print('  PySimpleGUI: OK')
import lark;        print('  lark       : OK')
"

# ── wine64-preloader'ı imzala (pymem memory erişimi için) ────────────────────
# macOS, task_for_pid çağrısını bloklar → pymem/wizwalker cross-process memory
# okuyamaz. wine64-preloader'a "get-task-allow" entitlement'ı ekleyerek
# diğer Wine proseslerinin bu prosesin memory'sini okumasına izin veriyoruz.
# sudo gerektirmez, SIP'i kapatmaya gerek yok.
_sign_wine_for_memory_access() {
    local wine_bin="$1"

    # Gerçek binary dizinini bul (wine64 bir wrapper script olabilir)
    local real_wine bin_dir
    real_wine=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$wine_bin" 2>/dev/null || echo "$wine_bin")
    bin_dir=$(dirname "$real_wine")

    # Entitlements plist — geçici dosya
    local ent
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

    local ok=0
    # İmzalanacak binary adayları: wine64-preloader en kritik olanı
    for bin in \
        "$bin_dir/wine64-preloader" \
        "$bin_dir/wine-preloader" \
        "$real_wine" \
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64-preloader" \
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine-preloader"; do
        [[ -x "$bin" ]] || continue
        # Gatekeeper quarantine varsa kaldır (imzalama başarısız olabilir)
        xattr -d com.apple.quarantine "$bin" 2>/dev/null || true
        if codesign --entitlements "$ent" --force -s - "$bin" 2>/dev/null; then
            echo "[setup] İmzalandı (get-task-allow): $(basename "$bin")"
            ok=1
        else
            echo "[setup] UYARI: İmzalanamadı: $bin"
        fi
    done

    rm -f "$ent"

    if [[ "$ok" -eq 0 ]]; then
        echo "[setup] UYARI: Hiçbir Wine binary imzalanamadı."
        echo "[setup]        speedhack çalışmayabilir. brew upgrade sonrası resign_wine.sh çalıştır."
    else
        echo "[setup] Memory erişim izni verildi. speedhack artık sudo gerekmez."
    fi
}

echo ""
echo "[setup] Wine memory erişimi yapılandırılıyor..."
_sign_wine_for_memory_access "$WINE_BIN"

echo ""
echo "[setup] Tamamlandı! Deimos klasörü: $DEIMOS_DIR"
echo "  bash run_deimos.sh"
echo "  bash run_speedhack.sh [çarpan]"