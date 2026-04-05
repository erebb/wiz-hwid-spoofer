#!/usr/bin/env bash
# run_deimos.sh — Deimos-Wizard101'i Wine içinde başlatır.
#
# Kullanım:
#   bash w101d/run_deimos.sh /path/to/Deimos-Wizard101
#   DEIMOS_DIR=/path/to/Deimos-Wizard101 bash w101d/run_deimos.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

# ─────────────────────────────────────────────
# Deimos klasörünü belirle
# ─────────────────────────────────────────────
# setup_env.sh Deimos'u buraya klonlar — argüman verilmezse orası kullanılır
DEIMOS_DIR="${1:-${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}}"

if [[ ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run_deimos] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
    echo "[run_deimos] Doğru klasörü gösterdiğinizden emin olun." >&2
    exit 1
fi

# ─────────────────────────────────────────────
# Wine içindeki Python'u bul
# ─────────────────────────────────────────────
WIN_PYTHON="$WINEPREFIX/drive_c/Python313/python.exe"

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run_deimos] HATA: Wine içinde Python bulunamadı." >&2
    echo "[run_deimos] Önce kurulum scriptini çalıştırın: bash w101d/setup_env.sh" >&2
    exit 1
fi

# ─────────────────────────────────────────────
# Deimos'u başlat
# ─────────────────────────────────────────────
echo "[run_deimos] Deimos başlatılıyor..."
echo "[run_deimos] Prefix : $WINEPREFIX"
echo "[run_deimos] Klasör : $DEIMOS_DIR"
echo ""

cd "$DEIMOS_DIR"
exec WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" \
    "$WINE_BIN" "$WIN_PYTHON" Deimos.py
