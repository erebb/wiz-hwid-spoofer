#!/usr/bin/env bash
# run_speedhack.sh — speedhack.py'yi çalışan Wizard101'in Wine prefix'inde başlatır.
#
# KULLANIM:
#   bash run_speedhack.sh          → 3x hız
#   bash run_speedhack.sh 5        → 5x hız
#   bash run_speedhack.sh 1        → sıfırla (normal hız)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"   # WINE_BIN (Homebrew Wine)

MULTIPLIER="${1:-3}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"

if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[speedhack] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2; exit 1
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
    find "$HOME/Library" -name "WizardGraphicalClient.exe" -maxdepth 12 2>/dev/null \
        | head -1 || true
}

# ── Bundled Wine binary'sini bul ─────────────────────────────────────────────
_find_bundled_wine() {
    for b in \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/SharedSupport/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine64" \
        "/Applications/Wizard101.app/Contents/Resources/wine/bin/wine" \
        "/Applications/Wizard101.app/Contents/MacOS/wine64" \
        "/Applications/Wizard101.app/Contents/MacOS/wine"; do
        [[ -x "$b" ]] && echo "$b" && return
    done
    [[ -d "/Applications/Wizard101.app" ]] || return 0
    find /Applications/Wizard101.app -name "wine64" -maxdepth 8 2>/dev/null \
        | grep "/bin/" | head -1 || true
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
                echo "[speedhack] İmzalandı (get-task-allow): $(basename "$b")"
                signed=1
            fi
        done
    done
    rm -f "$ent"
    [[ "$signed" -eq 0 ]] && echo "[speedhack] UYARI: Preloader imzalanamadı."
}

# ── Wizard101 process'i çalışıyor mu? ─────────────────────────────────────────
_wiz_is_running() {
    local out
    out=$(ps auxww 2>/dev/null \
        | grep -iE "(WizardGraphicalClient|KingsIsle)" \
        | grep -v "grep\|run_speedhack\|bash\|python" || true)
    [[ -n "$out" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
echo "[speedhack] Wizard101 kurulumu aranıyor..."
WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[speedhack] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[speedhack] Lütfen tam yolunu girin:"
    read -r WIZ_EXE
fi

if [[ -z "$WIZ_EXE" || ! -f "$WIZ_EXE" ]]; then
    echo "[speedhack] HATA: Geçerli exe yolu yok." >&2; exit 1
fi

WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
echo "[speedhack] Wine prefix: $WIZ_PREFIX"

# Bundled Wine → preloader imzala
BUNDLED_WINE=$(_find_bundled_wine)
if [[ -n "$BUNDLED_WINE" ]]; then
    echo "[speedhack] Bundled Wine: $BUNDLED_WINE"
    _sign_preloader "$BUNDLED_WINE"
else
    _sign_preloader "$WINE_BIN"
fi

# Oyunun çalışmasını bekle
if ! _wiz_is_running; then
    echo "[speedhack] Wizard101 çalışmıyor."
    if [[ -d "/Applications/Wizard101.app" ]]; then
        echo "[speedhack] Wizard101 açılıyor..."
        open -a Wizard101 2>/dev/null || true
    else
        echo "[speedhack] Lütfen Wizard101'i açın."
    fi
    for i in $(seq 1 36); do
        sleep 5
        if _wiz_is_running; then
            echo "[speedhack] Wizard101 başladı!"; sleep 3; break
        fi
        echo "[speedhack] Bekleniyor... ($i/36)"
        [[ "$i" -eq 36 ]] && { echo "[speedhack] HATA: Zaman aşımı." >&2; exit 1; }
    done
fi

# Python'u Wizard101 prefix'ine kopyala (henüz yoksa)
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[speedhack] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

export WINEPREFIX="$WIZ_PREFIX"

echo "[speedhack] WINEPREFIX : $WIZ_PREFIX"
echo "[speedhack] Wine       : $WINE_BIN"
echo "[speedhack] Çarpan     : ${MULTIPLIER}x"
echo ""

"$WINE_BIN" "$WIN_PYTHON" "$SCRIPT_DIR/speedhack.py" "$MULTIPLIER"
