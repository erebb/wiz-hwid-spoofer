#!/usr/bin/env bash
# detect_wine.sh — Wizard101.app içindeki Wine binary ve WINEPREFIX'i tespit eder.
# Bu script doğrudan çalıştırılmaz; diğer scriptler tarafından 'source' edilir.
#
# Kullanım:  source "$(dirname "$0")/detect_wine.sh"
# Sonuç:     WINE_BIN ve WINEPREFIX export edilir.

set -euo pipefail

_wiz_app="/Applications/Wizard101.app"

# --- Wine binary tespiti ---
_find_wine_bin() {
    # 1. Wizard101.app bundle içindeki Wine (tercih edilen)
    if [[ -d "$_wiz_app" ]]; then
        local bundled
        bundled=$(find "$_wiz_app" -type f \( -name "wine64" -o -name "wine" \) 2>/dev/null | head -1)
        if [[ -n "$bundled" && -x "$bundled" ]]; then
            echo "$bundled"
            return
        fi
    fi

    # 2. Homebrew Wine
    for candidate in \
        "$(brew --prefix 2>/dev/null)/bin/wine64" \
        "$(brew --prefix 2>/dev/null)/bin/wine" \
        "/usr/local/bin/wine64" \
        "/usr/local/bin/wine" \
        "/opt/homebrew/bin/wine64" \
        "/opt/homebrew/bin/wine"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    echo ""
}

# --- WINEPREFIX tespiti ---
_find_wineprefix() {
    local appdata="$HOME/Library/Application Support"

    # KingsIsle Wizard101'in kullandığı olası prefix konumları
    for candidate in \
        "$appdata/Wizard101/wine" \
        "$appdata/Wizard101" \
        "$appdata/KingsIsle Entertainment/Wizard101" \
        "$HOME/.wine"; do
        # drive_c varsa bu geçerli bir Wine prefix'idir
        if [[ -d "$candidate/drive_c" ]]; then
            echo "$candidate"
            return
        fi
    done

    # Hiçbiri bulunamazsa varsayılan
    echo "$HOME/.wine"
}

# --- Export ---
WINE_BIN=$(_find_wine_bin)

if [[ -z "$WINE_BIN" ]]; then
    echo "[detect_wine] HATA: Wine binary bulunamadı." >&2
    echo "[detect_wine] Çözüm: 'brew install wine-stable' komutunu çalıştırın." >&2
    exit 1
fi

WINEPREFIX=$(_find_wineprefix)
WINEARCH="${WINEARCH:-win64}"

export WINE_BIN WINEPREFIX WINEARCH

echo "[detect_wine] Wine    : $WINE_BIN"
echo "[detect_wine] Prefix  : $WINEPREFIX"
echo "[detect_wine] Arch    : $WINEARCH"
