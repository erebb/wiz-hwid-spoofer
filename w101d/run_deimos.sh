#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Mimari:
#   - Python/Deimos → Homebrew Wine + ~/.w101d_wine prefix
#   - Oyun           → Wizard101.app bundled Wine (ayrı wineserver)
#   - Process bulma  → macOS proc_listallpids() (wineserver bağımsız)
#   - Memory erişim  → task_for_pid (get-task-allow imzalı preloader)
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos
#   bash run_deimos.sh speed [N]    → Nx speedhack
#   bash run_deimos.sh quest        → quest TP
#   bash run_deimos.sh both [N]     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN, WINEPREFIX (~/.w101d_wine)

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı ($WIN_PYTHON). Önce setup_env.sh çalıştırın." >&2
    exit 1
fi
if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: Deimos bulunamadı ($DEIMOS_DIR). Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

# ── Wizard101 exe'sini dosya sisteminden bul (preloader imzalamak için) ───────
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
    find "$HOME/Library" -name "WizardGraphicalClient.exe" -maxdepth 12 2>/dev/null \
        | head -1 || true
}

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
# macOS: task_for_pid hedefe izin vermek için HEDEF imzalı olmalı.
# Bu imza sayesinde Homebrew Wine farklı wineserver'dan memory okuyabilir.
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
                echo "[run] İmzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    if [[ "$signed" -eq 0 ]]; then
        echo "[run] UYARI: Preloader imzalanamadı → memory erişimi başarısız olabilir."
    else
        echo "[run] NOT: İmza yeni açılışta geçerli olur → oyunu kapat/aç."
    fi
}

# ── Wizard101 process'i çalışıyor mu? ─────────────────────────────────────────
_wiz_is_running() {
    local out
    out=$(ps auxww 2>/dev/null \
        | grep -iE "(WizardGraphicalClient|KingsIsle)" \
        | grep -v "grep\|run_deimos\|bash\|python" || true)
    [[ -n "$out" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Oyunun wineserver'ından bundled wine binary'sini bul → preloader imzala
#    (Python bu wine'ı KULLANMAZ, sadece preloader imzalamak için buluyoruz)
# ─────────────────────────────────────────────────────────────────────────────
echo "[run] Wizard101 Wine + preloader aranıyor..."
WIZ_EXE=$(_find_wiz_exe)

# WIZ_DATA_DIR: Deimos.py WAD patch'inin oyun dosyalarını bulması için
if [[ -n "$WIZ_EXE" ]]; then
    _wiz_prefix_tmp=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
    _wiz_data_tmp="$_wiz_prefix_tmp/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Data/GameData"
    if [[ -d "$_wiz_data_tmp" ]]; then
        export WIZ_DATA_DIR="$_wiz_data_tmp"
        echo "[run] WIZ_DATA_DIR : $WIZ_DATA_DIR"
    fi
fi

WIZ_WINE=$(_find_wine_from_wineserver)

if [[ -n "$WIZ_WINE" ]]; then
    echo "[run] Bundled Wine preloader imzalanıyor: $WIZ_WINE"
    _sign_preloader "$WIZ_WINE"
elif [[ -n "$WIZ_EXE" ]]; then
    WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
    # Wizard101.app içinde wine binary ara
    for b in \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine"; do
        if [[ -x "$b" ]]; then
            echo "[run] Bundled Wine preloader imzalanıyor: $b"
            _sign_preloader "$b"
            break
        fi
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Oyunun çalışmasını bekle / aç
# ─────────────────────────────────────────────────────────────────────────────
if ! _wiz_is_running; then
    echo "[run] Wizard101 çalışmıyor."
    if [[ -d "/Applications/Wizard101.app" ]]; then
        echo "[run] Wizard101 açılıyor..."
        open -a Wizard101 2>/dev/null || open /Applications/Wizard101.app 2>/dev/null || true
    else
        echo "[run] Lütfen Wizard101'i manuel olarak açın."
    fi
    echo "[run] Oyunun yüklenmesi bekleniyor..."
    for i in $(seq 1 36); do
        sleep 5
        if _wiz_is_running; then
            echo "[run] Wizard101 başladı!"; sleep 5; break
        fi
        echo "[run] Bekleniyor... ($i/36)"
        [[ "$i" -eq 36 ]] && { echo "[run] HATA: Zaman aşımı." >&2; exit 1; }
    done
fi

echo "[run] Wizard101 çalışıyor."

# ─────────────────────────────────────────────────────────────────────────────
# 3. Python'u Homebrew Wine + ~/.w101d_wine prefix ile çalıştır
#    Neden: propsys.dll.VariantToString Homebrew Wine'da implemente,
#           bundled Wine'da yok (game-specific stripped build).
#    Process bulma: macOS proc_listallpids() → wineserver bağımsız
#    Memory erişim: task_for_pid (get-task-allow imzalı preloader)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WINEPREFIX/drive_c/wiz_tools.py"
fi

# ── WIZ_PID cross-wineserver patch (her çalışmada uygula) ────────────────────
# setup_env.sh çalıştırılmadan da patch aktif olsun.
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
    print('[run] wizwalker WIZ_PID patch uygulandı')
"
fi

# Wizard101 macOS PID'ini bul → Wine içinden task_for_pid ile cross-wineserver erişim
# EnumProcesses yalnızca aynı wineserver'ı görür; PID ile direkt bağlantı bunu atlatır.
WIZ_PID=$(ps auxww 2>/dev/null \
    | grep -i "WizardGraphicalClient" | grep -v grep \
    | awk '{print $2}' | head -1 || true)
if [[ -n "$WIZ_PID" ]]; then
    echo "[run] Wizard101 PID: $WIZ_PID (cross-wineserver bağlantı için)"
    export WIZ_PID
fi

echo "[run] Wine       : $WINE_BIN  (Homebrew — tam DLL desteği)"
echo "[run] WINEPREFIX : $WINEPREFIX  (~/.w101d_wine)"
echo "[run] Mod        : $MODE"
echo ""

case "$MODE" in
    deimos)
        echo "[run] Deimos başlatılıyor..."
        cd "$DEIMOS_DIR"
        exec "$WINE_BIN" "$WIN_PYTHON" Deimos.py
        ;;
    speed|quest|both)
        echo "[run] wiz_tools başlatılıyor ($MODE)..."
        exec "$WINE_BIN" "$WIN_PYTHON" \
            "$WINEPREFIX/drive_c/wiz_tools.py" "$MODE" "$MULTIPLIER"
        ;;
    *)
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2; exit 1
        ;;
esac