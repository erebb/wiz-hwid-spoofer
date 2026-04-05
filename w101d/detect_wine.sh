#!/usr/bin/env bash
# detect_wine.sh — Homebrew Wine'ı otomatik kurar ve Deimos için WINEPREFIX hazırlar.
# Bu script doğrudan çalıştırılmaz; diğer scriptler tarafından 'source' edilir.
#
# Kullanım:  source "$(dirname "$0")/detect_wine.sh"
# Sonuç:     WINE_BIN, WINEPREFIX, WINEARCH export edilir.
#
# NOT: Wizard101'in bundled Wine'ı Python'u crash ettirir.
#      Bu script Homebrew Wine kullanır — yoksa otomatik kurar.

set -euo pipefail

# Deimos için ayrı Wine prefix (Wizard101'in prefix'ine dokunmaz)
DEIMOS_PREFIX="$HOME/.w101d_wine"

# ─────────────────────────────────────────────
# Homebrew kurulu mu? Değilse otomatik kur.
# ─────────────────────────────────────────────
_ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return
    fi

    echo "[detect_wine] Homebrew bulunamadı, kuruluyor..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon için PATH'e ekle
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    echo "[detect_wine] Homebrew kuruldu."
}

# ─────────────────────────────────────────────
# wine-stable kurulu mu? Değilse otomatik kur.
# ─────────────────────────────────────────────
_ensure_wine() {
    # Mevcut Wine binary'lerini kontrol et
    for candidate in \
        "/opt/homebrew/bin/wine64" \
        "/opt/homebrew/bin/wine" \
        "/usr/local/bin/wine64" \
        "/usr/local/bin/wine"; do
        if [[ -x "$candidate" ]]; then
            return
        fi
    done

    # brew prefix üzerinden de dene
    if command -v brew &>/dev/null; then
        local prefix
        prefix=$(brew --prefix 2>/dev/null)
        for candidate in "$prefix/bin/wine64" "$prefix/bin/wine"; do
            if [[ -x "$candidate" ]]; then
                return
            fi
        done
    fi

    echo "[detect_wine] wine-stable bulunamadı, kuruluyor..."
    brew install --cask wine-stable
    echo "[detect_wine] wine-stable kuruldu."
}

# ─────────────────────────────────────────────
# Wine binary'sini bul
# ─────────────────────────────────────────────
_find_wine_bin() {
    for candidate in \
        "/opt/homebrew/bin/wine64" \
        "/opt/homebrew/bin/wine" \
        "/usr/local/bin/wine64" \
        "/usr/local/bin/wine"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    if command -v brew &>/dev/null; then
        local prefix
        prefix=$(brew --prefix 2>/dev/null)
        for candidate in "$prefix/bin/wine64" "$prefix/bin/wine"; do
            if [[ -x "$candidate" ]]; then
                echo "$candidate"
                return
            fi
        done
    fi

    echo ""
}

# ─────────────────────────────────────────────
# Homebrew ve Wine kur (gerekirse)
# ─────────────────────────────────────────────
_ensure_homebrew
_ensure_wine

# ─────────────────────────────────────────────
# Wine binary'sini export et
# ─────────────────────────────────────────────
WINE_BIN=$(_find_wine_bin)

if [[ -z "$WINE_BIN" ]]; then
    echo "[detect_wine] HATA: Wine kuruldu ama binary bulunamadı." >&2
    echo "[detect_wine] Terminal'i kapatıp açın ve tekrar deneyin." >&2
    exit 1
fi

# ─────────────────────────────────────────────
# Deimos Wine prefix'ini hazırla
# ─────────────────────────────────────────────
WINEPREFIX="$DEIMOS_PREFIX"
WINEARCH="win64"

export WINE_BIN WINEPREFIX WINEARCH

if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
    echo "[detect_wine] Deimos Wine prefix'i oluşturuluyor: $WINEPREFIX"
    WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" "$WINE_BIN" wineboot --init 2>/dev/null || true
fi

echo "[detect_wine] Wine    : $WINE_BIN"
echo "[detect_wine] Prefix  : $WINEPREFIX"
echo "[detect_wine] Arch    : $WINEARCH"
