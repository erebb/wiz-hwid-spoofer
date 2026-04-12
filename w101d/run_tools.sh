#!/usr/bin/env bash
# run_tools.sh — wiz_tools.py'yi Homebrew Wine + ~/.w101d_wine prefix ile çalıştırır.
#
# Neden ~/.w101d_wine: bundled Wine'da propsys.dll.VariantToString yok → crash.
# Homebrew Wine tam DLL desteği. macOS proc_listallpids() wineserver bağımsız
# process bulur. Memory erişim task_for_pid ile yapılır (imzalı preloader).
#
# KULLANIM:
#   bash run_tools.sh            → menü
#   bash run_tools.sh speed 3    → 3x speedhack
#   bash run_tools.sh quest      → quest TP
#   bash run_tools.sh both 3     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN, WINEPREFIX (~/.w101d_wine)

WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"
WIN_TOOLS="$WINEPREFIX/drive_c/wiz_tools.py"

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[tools] HATA: Python bulunamadı → setup_env.sh çalıştırın." >&2; exit 1
fi

# ── Çalışan wineserver'dan wine binary'sini türet (preloader imzalamak için) ──
_find_wine_from_wineserver() {
    local ws
    ws=$(ps auxww 2>/dev/null | grep -iE "[Ww]ineserver" | grep -v grep \
         | awk '{print $11}' | head -1)
    [[ -z "$ws" || ! -x "$ws" ]] && return 0
    local bin_dir="${ws%/*}"
    for b in "$bin_dir/wine64" "$bin_dir/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done
}

# ── Preloader imzala (get-task-allow) ─────────────────────────────────────────
_sign_preloader() {
    local wine_bin="${1:-}"
    [[ -z "$wine_bin" || ! -x "$wine_bin" ]] && return 0
    local real bin_dir
    real=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" \
           "$wine_bin" 2>/dev/null || echo "$wine_bin")
    bin_dir=$(dirname "$real")

    local ent signed=0
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
    for d in "$bin_dir" "$(dirname "$wine_bin")"; do
        for b in "$d/wine64-preloader" "$d/wine-preloader"; do
            [[ -x "$b" ]] || continue
            xattr -d com.apple.quarantine "$b" 2>/dev/null || true
            if codesign --entitlements "$ent" --force -s - "$b" 2>/dev/null; then
                echo "[tools] İmzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    [[ "$signed" -eq 0 ]] && echo "[tools] UYARI: Preloader imzalanamadı."
}

# ── Wizard101 process'i çalışıyor mu? ─────────────────────────────────────────
_wiz_is_running() {
    local out
    out=$(ps auxww 2>/dev/null \
        | grep -iE "(WizardGraphicalClient|KingsIsle)" \
        | grep -v "grep\|run_tools\|bash\|python" || true)
    [[ -n "$out" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Bundled Wine preloader'ı imzala (memory erişim için)
WIZ_WINE=$(_find_wine_from_wineserver)
if [[ -n "$WIZ_WINE" ]]; then
    echo "[tools] Bundled Wine preloader imzalanıyor: $WIZ_WINE"
    _sign_preloader "$WIZ_WINE"
fi

# Oyunun çalışmasını bekle
if ! _wiz_is_running; then
    echo "[tools] Wizard101 çalışmıyor."
    if [[ -d "/Applications/Wizard101.app" ]]; then
        echo "[tools] Wizard101 açılıyor..."
        open -a Wizard101 2>/dev/null || true
    else
        echo "[tools] Lütfen Wizard101'i açın."
    fi
    for i in $(seq 1 36); do
        sleep 5
        if _wiz_is_running; then
            echo "[tools] Wizard101 başladı!"; sleep 5; break
        fi
        echo "[tools] Bekleniyor... ($i/36)"
        [[ "$i" -eq 36 ]] && { echo "[tools] HATA: Zaman aşımı." >&2; exit 1; }
    done
fi

cp "$SCRIPT_DIR/wiz_tools.py" "$WIN_TOOLS"

# ── WIZ_PID cross-wineserver patch (her çalışmada uygula) ────────────────────
SITE_PKG="$WINEPREFIX/drive_c/Python313/Lib/site-packages"
HANDLER_PY="$SITE_PKG/wizwalker/client_handler.py"
if [[ -f "$HANDLER_PY" ]]; then
    python3 -c "
import pathlib
handler = pathlib.Path('$HANDLER_PY')
content = handler.read_text()
PATCH = '''
# -- WIZ_PID cross-wineserver patch (macOS / Homebrew Wine) ------------------
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
# ---------------------------------------------------------------------------
'''
if '_get_new_clients_patched' not in content:
    handler.write_text(content + PATCH)
    print('[tools] wizwalker WIZ_PID patch uygulandı')
"
fi

# Wizard101 macOS PID → task_for_pid ile cross-wineserver erişim
WIZ_PID=$(ps auxww 2>/dev/null \
    | grep -i "WizardGraphicalClient" | grep -v grep \
    | awk '{print $2}' | head -1 || true)
if [[ -n "$WIZ_PID" ]]; then
    echo "[tools] Wizard101 PID: $WIZ_PID"
    export WIZ_PID
fi

echo "[tools] Wine       : $WINE_BIN  (Homebrew)"
echo "[tools] WINEPREFIX : $WINEPREFIX"
echo ""

exec "$WINE_BIN" "$WIN_PYTHON" "$WIN_TOOLS" "$@"
