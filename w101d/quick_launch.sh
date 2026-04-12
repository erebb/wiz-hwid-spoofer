#!/usr/bin/env bash
# quick_launch.sh — Wizard101'i launcher olmadan direkt başlatır (otomatik giriş).
#
# Streaming sorunu neden çözüldü:
#   Eski sürüm detect_wine.sh'dan gelen ~/.w101d_wine prefix'ini kullanıyordu.
#   Oyun kendi prefix'inde (Bottles/wizard101) kurulu olduğu için registry,
#   data path'leri ve patch server bilgisi orada. Yanlış prefix → streaming çalışmaz.
#   Bu sürüm oyunun kendi prefix'ini otomatik bulur ve WINEPREFIX olarak set eder.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Giriş bilgileri ───────────────────────────────────────────────────────────
WIZ_USER="KULLANICI_ADIN"
WIZ_PASS="SIFREN"

# ── Oyun exe'sini otomatik bul ────────────────────────────────────────────────
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
# Oyunun kendi Wine'ı (Wizard101.app içindeki) kullanılmalı — böylece
# oyunun prefix'iyle uyumlu wineserver başlar, streaming çalışır.
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
    # Çalışan wineserver'dan türet (oyun zaten açıksa)
    local ws
    ws=$(ps auxww 2>/dev/null | grep -iE "[Ww]ineserver" | grep -v grep \
         | awk '{print $11}' | head -1 || true)
    if [[ -n "$ws" && -x "$ws" ]]; then
        local bd="${ws%/*}"
        for b in "$bd/wine64" "$bd/wine"; do
            [[ -x "$b" ]] && echo "$b" && return
        done
    fi
    # Fallback: Homebrew Wine (streaming çalışmayabilir ama oyun açılır)
    source "$SCRIPT_DIR/detect_wine.sh"
    echo "$WINE_BIN"
}

# ─────────────────────────────────────────────────────────────────────────────
WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" || ! -f "$WIZ_EXE" ]]; then
    echo "[QuickLaunch] HATA: WizardGraphicalClient.exe bulunamadı!"
    echo "  Wizard101'in kurulu olduğundan ve ~/Library/Application Support/Wizard101"
    echo "  dizininde bulunduğundan emin olun."
    exit 1
fi

WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
WIZ_BIN_DIR=$(dirname "$WIZ_EXE")
WINE_BIN=$(_find_bundled_wine)

# Oyunun kendi prefix'ini kullan → registry + data path'leri doğru → streaming çalışır
export WINEPREFIX="$WIZ_PREFIX"

echo "[QuickLaunch] Exe     : $WIZ_EXE"
echo "[QuickLaunch] Prefix  : $WIZ_PREFIX"
echo "[QuickLaunch] Wine    : $WINE_BIN"
echo "[QuickLaunch] Oyun başlatılıyor..."

cd "$WIZ_BIN_DIR"
"$WINE_BIN" WizardGraphicalClient.exe \
    -L login.us.wizard101.com 12000 \
    -u "$WIZ_USER" -p "$WIZ_PASS" \
    > /dev/null 2>&1 &

echo "[QuickLaunch] Tamam! KingsIsle ekranı birazdan gelir."
echo "             Zone'lara girişte dosya indirme artık çalışmalı."
