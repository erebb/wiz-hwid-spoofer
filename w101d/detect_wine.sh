#!/usr/bin/env bash
# detect_wine.sh — Wizard101 Mac için Wine binary ve WINEPREFIX'i tespit eder.
# Bu script doğrudan çalıştırılmaz; diğer scriptler tarafından 'source' edilir.
#
# Kullanım:  source "$(dirname "$0")/detect_wine.sh"
# Sonuç:     WINE_BIN ve WINEPREFIX export edilir.
#
# NOT: WINEPREFIX (oyunun kurulu olduğu sanal Windows dosya sistemi) Wizard101.app
# içinde DEĞİLDİR. Genellikle ~/Library/ altında ayrı bir klasördedir.
# Manuel override: WINEPREFIX=/yol/prefix bash w101d/run_deimos.sh ...

set -euo pipefail

_wiz_app="/Applications/Wizard101.app"

# --- Wine binary tespiti ---
_find_wine_bin() {
    # 1. Wizard101.app bundle içindeki Wine binary (genellikle Contents/Resources/wine/)
    if [[ -d "$_wiz_app" ]]; then
        local bundled
        bundled=$(find "$_wiz_app/Contents" -type f \( -name "wine64" -o -name "wine" \) 2>/dev/null | grep -v ".framework" | head -1)
        if [[ -n "$bundled" && -x "$bundled" ]]; then
            echo "$bundled"
            return
        fi
    fi

    # 2. Homebrew Wine (Apple Silicon: /opt/homebrew, Intel: /usr/local)
    for candidate in \
        "/opt/homebrew/bin/wine64" \
        "/opt/homebrew/bin/wine" \
        "/usr/local/bin/wine64" \
        "/usr/local/bin/wine" \
        "$(brew --prefix 2>/dev/null)/bin/wine64" \
        "$(brew --prefix 2>/dev/null)/bin/wine"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    echo ""
}

# --- WINEPREFIX tespiti ---
# WINEPREFIX, Wizard101.app DIŞINDA ~/Library/ altında bulunur.
# Oyunun sanal Windows dosya sistemi (drive_c/) burada saklanır.
_find_wineprefix() {
    local appdata="$HOME/Library/Application Support"
    local containers="$HOME/Library/Containers"

    # KingsIsle / Wizard101 için bilinen WINEPREFIX konumları
    for candidate in \
        "$appdata/com.kingsisle.wizard101/wine" \
        "$appdata/com.kingsisle.wizard101" \
        "$appdata/Wizard101/wine" \
        "$appdata/Wizard101/wineprefix" \
        "$appdata/Wizard101" \
        "$appdata/KingsIsle Entertainment/Wizard101/wine" \
        "$appdata/KingsIsle Entertainment/Wizard101" \
        "$containers/com.kingsisle.wizard101/Data/wine" \
        "$HOME/Library/Wizard101" \
        "$HOME/.wizard101" \
        "$HOME/.wine"; do
        # drive_c varsa geçerli bir Wine prefix'idir
        if [[ -d "$candidate/drive_c" ]]; then
            echo "$candidate"
            return
        fi
    done

    # drive_c bulunamadıysa — Wizard101.exe'yi ara (prefix'i tahmin et)
    local wiz_exe
    wiz_exe=$(find "$HOME/Library" -name "Wizard101.exe" -maxdepth 8 2>/dev/null | head -1)
    if [[ -n "$wiz_exe" ]]; then
        # Wizard101.exe genellikle {PREFIX}/drive_c/.../Wizard101/Bin/Wizard101.exe
        # drive_c'nin üst dizinini bul
        local drive_c
        drive_c=$(echo "$wiz_exe" | sed 's|/drive_c/.*|/drive_c|')
        echo "$(dirname "$drive_c")"
        return
    fi

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
