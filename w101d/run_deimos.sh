#!/usr/bin/env bash
# run_deimos.sh — Wizard101 + Deimos'u AYNI Wine prefix'inde başlatır.
# Aynı wineserver = WizWalker Wizard101'in memory'sini görebilir.
#
# Wizard101 → Whisky'nin kendi Wine binary'si (uyumlu)
# Deimos     → Homebrew Wine (Python için uyumlu)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

DEIMOS_DIR="${1:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"

if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[run] HATA: Wine içinde Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

if [[ ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
    exit 1
fi

# ── Whisky'nin Wine binary'sini bul ──────────
# Homebrew Wine, Whisky prefix'inde Wizard101'i çalıştıramaz (DLL uyumsuzluğu).
# Whisky kendi Wine sürümünü indirip saklar; onu kullanmamız gerekiyor.
_find_whisky_wine() {
    # Whisky Libraries klasörü (sandboxed ve normal)
    local lib_dirs=(
        "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Data/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine"
        "$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine"
        "$HOME/Library/Application Support/Whisky/Libraries/Wine"
    )
    for lib in "${lib_dirs[@]}"; do
        [[ -d "$lib" ]] || continue
        # İçindeki herhangi bir versiyonun wine64 veya wine binary'sini bul
        local bin
        bin=$(find "$lib" -name "wine64" -o -name "wine" 2>/dev/null | grep '/bin/' | head -1)
        if [[ -n "$bin" && -x "$bin" ]]; then
            echo "$bin"
            return
        fi
    done
    echo ""
}

WHISKY_WINE=$(_find_whisky_wine)

if [[ -z "$WHISKY_WINE" ]]; then
    echo "[run] UYARI: Whisky'nin Wine binary'si bulunamadı."
    echo "[run] Wizard101'i Whisky üzerinden manuel olarak açın, ardından Enter'a basın."
    read -r -p "[run] Wizard101 açık mı? (Enter ile devam): "
    WHISKY_WINE=""
fi

# ── WizardGraphicalClient.exe'yi bul ─────────
_find_wiz_exe() {
    local candidates=(
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        # Whisky bottle yolu
        "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Data/Library/Application Support/com.isaacmarovitz.Whisky/Bottles/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    find "$HOME/Library" -name "WizardGraphicalClient.exe" 2>/dev/null | head -1
}

WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[run] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[run] Lütfen exe'nin tam yolunu girin:"
    read -r WIZ_EXE
    if [[ ! -f "$WIZ_EXE" ]]; then
        echo "[run] HATA: Dosya bulunamadı: $WIZ_EXE" >&2
        exit 1
    fi
fi

echo "[run] Wizard101 bulundu: $WIZ_EXE"

# Exe'nin bulunduğu Wine prefix'ini tespit et
WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
echo "[run] Wizard101 Wine prefix : $WIZ_PREFIX"
echo "[run] Homebrew Wine (Deimos): $WINE_BIN"
echo "[run] Whisky Wine (Wizard101): ${WHISKY_WINE:-manuel başlatılacak}"

# Python'u Wizard101'in prefix'ine kopyala (henüz yoksa)
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python, Wizard101 prefix'ine kopyalanıyor: $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

# Her iki uygulama AYNI WINEPREFIX'te çalışmalı → aynı wineserver → memory erişimi OK
export WINEPREFIX="$WIZ_PREFIX"

# ── Wizard101'i başlat ───────────────────────
if [[ -n "$WHISKY_WINE" ]]; then
    echo "[run] Wizard101 Whisky Wine ile başlatılıyor..."
    # -L login.us.wizard101.com 12000 → launcher bypass, direkt login
    WINEPREFIX="$WIZ_PREFIX" "$WHISKY_WINE" "$WIZ_EXE" -L login.us.wizard101.com 12000 &
    echo "[run] Wizard101 yükleniyor, bekleniyor (20 saniye)..."
    sleep 20
else
    echo "[run] Wizard101 zaten açık kabul ediliyor, devam ediliyor..."
fi

# ── Deimos'u aynı prefix'te başlat ──────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
"$WINE_BIN" "$WIN_PYTHON" Deimos.py
