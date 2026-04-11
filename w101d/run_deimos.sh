#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Yaklaşım: process env okumak yerine dosya sisteminden Wine prefix'i bulur.
# Bundled Wine (Wizard101.app) child env'a WINEPREFIX koymadığından
# process tespiti yerine kurulum dizini taraması kullanılır.
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos
#   bash run_deimos.sh speed [N]    → Nx speedhack
#   bash run_deimos.sh quest        → quest TP
#   bash run_deimos.sh both [N]     → ikisi birden
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN (Homebrew Wine)

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2; exit 1
fi
if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: Deimos bulunamadı." >&2; exit 1
fi

# ── Wizard101 exe'sini dosya sisteminden bul → prefix türet ──────────────────
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
    # Geniş arama: Library + Wizard101.app içi
    find "$HOME/Library" /Applications/Wizard101.app \
         -name "WizardGraphicalClient.exe" -maxdepth 12 2>/dev/null | head -1
}

# ── Wizard101'in bundled Wine binary'sini bul ─────────────────────────────────
_find_bundled_wine() {
    # Önce bilinen sabit konumlar
    for b in \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/MacOS/wine64" \
        "/Applications/Wizard101.app/Contents/MacOS/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done
    # Geniş arama
    find /Applications/Wizard101.app -name "wine64" -maxdepth 8 2>/dev/null \
        | grep "/bin/" | head -1
}

# ── Preloader imzala (get-task-allow) ─────────────────────────────────────────
_sign_preloader() {
    local wine_bin="${1:-}"
    [[ -z "$wine_bin" || ! -x "$wine_bin" ]] && return
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
                echo "[run] İmzalandı (get-task-allow): $(basename "$b") ← $b"
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
    ps auxww 2>/dev/null \
        | grep -iE "(WizardGraphicalClient|KingsIsle)" \
        | grep -v "grep\|run_deimos\|bash\|python" \
        | grep -q . 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Dosya sisteminden Wizard101 kurulumunu bul
# ─────────────────────────────────────────────────────────────────────────────
echo "[run] Wizard101 kurulumu aranıyor..."
WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[run] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[run] Lütfen tam yolunu girin:"
    read -r WIZ_EXE
fi

if [[ -z "$WIZ_EXE" || ! -f "$WIZ_EXE" ]]; then
    echo "[run] HATA: Geçerli exe yolu yok: $WIZ_EXE" >&2; exit 1
fi

WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
echo "[run] Wizard101 prefix: $WIZ_PREFIX"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Bundled Wine'ı bul ve preloader'ı imzala
# ─────────────────────────────────────────────────────────────────────────────
BUNDLED_WINE=$(_find_bundled_wine)

if [[ -n "$BUNDLED_WINE" ]]; then
    echo "[run] Bundled Wine: $BUNDLED_WINE"
    _sign_preloader "$BUNDLED_WINE"
else
    echo "[run] Bundled Wine bulunamadı → Homebrew Wine preloader imzalanıyor"
    _sign_preloader "$WINE_BIN"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Oyunun çalışmasını bekle / aç
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
            echo "[run] Wizard101 başladı!"
            sleep 3   # Yüklenmesi için kısa bekleme
            break
        fi
        echo "[run] Bekleniyor... ($i/36)"
        if [[ "$i" -eq 36 ]]; then
            echo "[run] HATA: Wizard101 başlamadı." >&2; exit 1
        fi
    done
fi

echo "[run] Wizard101 çalışıyor."

# ─────────────────────────────────────────────────────────────────────────────
# 4. Python için Wine seç
#    Bundled Wine (Wizard101.app) Python'u crash eder → Homebrew Wine kullan
# ─────────────────────────────────────────────────────────────────────────────
if [[ -n "$BUNDLED_WINE" ]]; then
    ACTIVE_WINE="$WINE_BIN"
    echo "[run] Python Wine: Homebrew ($WINE_BIN) — bundled Wine Python'u desteklemiyor"
else
    ACTIVE_WINE="$WINE_BIN"
    echo "[run] Python Wine: $WINE_BIN"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Python'u oyunun prefix'ine kopyala (yoksa)
# ─────────────────────────────────────────────────────────────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WIZ_PREFIX/drive_c/wiz_tools.py"
fi

export WINEPREFIX="$WIZ_PREFIX"
echo "[run] WINEPREFIX : $WIZ_PREFIX"
echo "[run] Wine       : $ACTIVE_WINE"
echo "[run] Mod        : $MODE"
echo ""

case "$MODE" in
    deimos)
        echo "[run] Deimos başlatılıyor..."
        cd "$DEIMOS_DIR"
        exec "$ACTIVE_WINE" "$WIN_PYTHON" Deimos.py
        ;;
    speed|quest|both)
        echo "[run] wiz_tools başlatılıyor ($MODE)..."
        exec "$ACTIVE_WINE" "$WIN_PYTHON" \
            "$WIZ_PREFIX/drive_c/wiz_tools.py" "$MODE" "$MULTIPLIER"
        ;;
    *)
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2; exit 1
        ;;
esac
