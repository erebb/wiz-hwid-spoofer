#!/usr/bin/env bash
# run_deimos.sh — Wizard101 + Deimos'u AYNI Wine prefix'inde başlatır.
# Aynı wineserver = WizWalker Wizard101'in memory'sini görebilir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

DEIMOS_DIR="${1:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"
# Python: setup_env.sh ~/.w101d_wine'a kurdu — onu Wizard101'in prefix'ine kopyala
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

if [[ ! -f "$WIN_PYTHON" && -d "$OUR_PYTHON" ]]; then
    echo "[run] Python, Wizard101 prefix'ine kopyalanıyor..."
    cp -r "$OUR_PYTHON" "$WINEPREFIX/drive_c/Python313"
    # site-packages de kopyala
    cp -r "$HOME/.w101d_wine/drive_c/Python313" "$WINEPREFIX/drive_c/" 2>/dev/null || true
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] HATA: Wine içinde Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

if [[ ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
    exit 1
fi

# ── WizardGraphicalClient.exe'yi bul ─────────
_find_wiz_exe() {
    local candidates=(
        # Whisky (Mac Wine manager) — Bottles yapısı
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        # Program Files alternatifleri
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/Bottles/wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        # Bottles olmadan
        "$HOME/Library/Application Support/Wizard101/drive_c/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    find "$HOME/Library" -name "WizardGraphicalClient.exe" 2>/dev/null | head -1
}

WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[run] WizardGraphicalClient.exe otomatik bulunamadı."
    echo "[run] Aranılan yerler:"
    echo "  /Applications/Wizard101.app/..."
    echo "  ~/Library/Application Support/Wizard101/..."
    echo ""
    echo "[run] Lütfen exe'nin tam yolunu girin:"
    read -r WIZ_EXE
    if [[ ! -f "$WIZ_EXE" ]]; then
        echo "[run] HATA: Dosya bulunamadı: $WIZ_EXE" >&2
        exit 1
    fi
fi

echo "[run] Wizard101 bulundu: $WIZ_EXE"

# Exe'nin bulunduğu Wine prefix'ini tespit et
# Yol: .../drive_c/... → prefix = drive_c'nin üstü
WIZ_PREFIX=$(echo "$WIZ_EXE" | sed 's|/drive_c/.*||')
echo "[run] Wizard101 Wine prefix: $WIZ_PREFIX"
echo "[run] Bizim Homebrew Wine  : $WINE_BIN"

# Her iki uygulama AYNI WINEPREFIX'te çalışmalı → aynı wineserver → memory erişimi OK
export WINEPREFIX="$WIZ_PREFIX"

# ── Wizard101'i başlat ───────────────────────
# -L login.us.wizard101.com 12000 → launcher bypass, direkt login
echo "[run] Wizard101 başlatılıyor..."
"$WINE_BIN" "$WIZ_EXE" -L login.us.wizard101.com 12000 &

# ── Wizard101'in açılmasını bekle ────────────
echo "[run] Wizard101 yükleniyor, bekleniyor (20 saniye)..."
sleep 20

# ── Deimos'u aynı prefix'te başlat ──────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
"$WINE_BIN" "$WIN_PYTHON" Deimos.py
