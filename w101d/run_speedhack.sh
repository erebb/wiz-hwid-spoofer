#!/usr/bin/env bash
# run_speedhack.sh — speedhack.py'yi çalışan Wizard101'in Wine prefix'inde başlatır.
#
# KULLANIM:
#   bash run_speedhack.sh          → 3x hız
#   bash run_speedhack.sh 5        → 5x hız
#   bash run_speedhack.sh 1        → sıfırla (normal hız)
#
# GEREKSINIM:
#   - Wizard101 Wine ile çalışıyor olmalı
#   - setup_env.sh daha önce çalıştırılmış olmalı
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

MULTIPLIER="${1:-3}"
OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"

if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[speedhack] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

# ── Çalışan Wizard101'den WINEPREFIX oku ─────────────────────────────────────
_get_wiz_prefix() {
    local pid
    pid=$(pgrep -f "WizardGraphicalClient.exe" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && echo "" && return
    ps eww -p "$pid" 2>/dev/null \
        | tr ' ' '\n' \
        | grep '^WINEPREFIX=' \
        | head -1 \
        | cut -d= -f2-
}

echo "[speedhack] Wizard101 aranıyor..."

WIZ_PREFIX=""
for i in $(seq 1 12); do
    WIZ_PREFIX=$(_get_wiz_prefix)
    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[speedhack] Wizard101 bulundu."
        break
    fi
    echo "[speedhack] Bekleniyor... ($i/12) — Wizard101'i önce Wine ile aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[speedhack] HATA: Wizard101 çalışmıyor." >&2
    exit 1
fi

# ── Python'u Wizard101 prefix'ine kopyala (henüz yoksa) ──────────────────────
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
