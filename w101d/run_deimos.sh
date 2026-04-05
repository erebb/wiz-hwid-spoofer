#!/usr/bin/env bash
# run_deimos.sh — Wizard101 + Deimos'u AYNI Wine prefix'inde başlatır.
# Aynı wineserver = WizWalker Wizard101'in memory'sini görebilir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

DEIMOS_DIR="${1:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

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
    # Mac app bundle içindeki yaygın lokasyonlar
    local candidates=(
        "/Applications/Wizard101.app/Contents/Resources/Wizard101/Bin/WizardGraphicalClient.exe"
        "/Applications/Wizard101.app/Contents/Resources/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "/Applications/Wizard101.app/Contents/Resources/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files/Wizard101/Bin/WizardGraphicalClient.exe"
        "$HOME/Library/Application Support/Wizard101/drive_c/Program Files (x86)/Wizard101/Bin/WizardGraphicalClient.exe"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && echo "$c" && return
    done
    # Fallback: find ile ara
    find /Applications/Wizard101.app -name "WizardGraphicalClient.exe" 2>/dev/null | head -1
}

WIZ_EXE=$(_find_wiz_exe)

if [[ -z "$WIZ_EXE" ]]; then
    echo "[run] HATA: WizardGraphicalClient.exe bulunamadı." >&2
    echo "[run] Wizard101'in /Applications/Wizard101.app'te kurulu olduğundan emin olun." >&2
    exit 1
fi

echo "[run] Wizard101 bulundu: $WIZ_EXE"
echo "[run] Wine prefix    : $WINEPREFIX"

# ── Wizard101'i bizim Wine prefix'imizle başlat ─
# -L login.us.wizard101.com 12000 → launcher'ı bypass eder, direkt login
# & → arka planda çalıştır, Deimos başlatmaya devam et
echo "[run] Wizard101 başlatılıyor (bizim Wine prefix'imizde)..."
"$WINE_BIN" "$WIZ_EXE" -L login.us.wizard101.com 12000 &

# ── Wizard101'in açılmasını bekle ────────────
echo "[run] Wizard101 yükleniyor, bekleniyor (20 saniye)..."
sleep 20

# ── Deimos'u aynı prefix'te başlat ──────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
"$WINE_BIN" "$WIN_PYTHON" Deimos.py
