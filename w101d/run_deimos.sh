#!/usr/bin/env bash
# run_deimos.sh — Wizard101 araçlarını çalıştırır.
#
# Çalışan Wizard101'in Wine prefix'ini otomatik tespit eder;
# Deimos, speedhack veya quest TP'yi aynı prefix'te başlatır.
# (Aynı wineserver = wizwalker/pymem memory okuyabilir)
#
# KULLANIM:
#   bash run_deimos.sh              → Deimos (varsayılan)
#   bash run_deimos.sh speed [N]    → Nx speedhack (varsayılan: 3)
#   bash run_deimos.sh quest        → Enter ile quest TP
#   bash run_deimos.sh both [N]     → Nx speed + quest TP
#
# GEREKSİNİM:
#   - setup_env.sh çalıştırılmış olmalı
#   - Wizard101 Wine ile açık olmalı
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect_wine.sh"

MODE="${1:-deimos}"
MULTIPLIER="${2:-3}"

OUR_PYTHON="$HOME/.w101d_wine/drive_c/Python313"
DEIMOS_DIR="${DEIMOS_DIR:-$HOME/.w101d_cache/Deimos}"

# ── Kurulum kontrolü ──────────────────────────────────────────────────────────
if [[ ! -d "$OUR_PYTHON" ]]; then
    echo "[run] HATA: Python bulunamadı. Önce setup_env.sh çalıştırın." >&2
    exit 1
fi

if [[ "$MODE" == "deimos" && ! -f "$DEIMOS_DIR/Deimos.py" ]]; then
    echo "[run] HATA: '$DEIMOS_DIR/Deimos.py' bulunamadı." >&2
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

echo "[run] Wizard101 aranıyor..."
WIZ_PREFIX=""
for i in $(seq 1 12); do
    WIZ_PREFIX=$(_get_wiz_prefix)
    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[run] Wizard101 bulundu."
        break
    fi
    echo "[run] Bekleniyor... ($i/12) — Wizard101'i Wine ile aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[run] HATA: Wizard101 çalışmıyor. Önce oyunu Wine ile aç." >&2
    exit 1
fi

# ── Python'u Wizard101 prefix'ine kopyala (yoksa) ────────────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

# wiz_tools.py'yi prefix'e kopyala (speed/quest/both modları için)
WIN_TOOLS="$WIZ_PREFIX/drive_c/wiz_tools.py"
if [[ "$MODE" != "deimos" ]]; then
    cp "$SCRIPT_DIR/wiz_tools.py" "$WIN_TOOLS"
fi

export WINEPREFIX="$WIZ_PREFIX"
echo "[run] WINEPREFIX : $WIZ_PREFIX"
echo "[run] Wine       : $WINE_BIN"
echo "[run] Mod        : $MODE"
echo ""

# ── Çalıştır ─────────────────────────────────────────────────────────────────
case "$MODE" in
    deimos)
        echo "[run] Deimos başlatılıyor..."
        cd "$DEIMOS_DIR"
        exec "$WINE_BIN" "$WIN_PYTHON" Deimos.py
        ;;
    speed|quest|both)
        echo "[run] wiz_tools başlatılıyor ($MODE)..."
        exec "$WINE_BIN" "$WIN_PYTHON" "$WIN_TOOLS" "$MODE" "$MULTIPLIER"
        ;;
    *)
        echo "[run] HATA: Bilinmeyen mod '$MODE'" >&2
        echo "      Kullanım: run_deimos.sh [deimos|speed|quest|both] [çarpan]" >&2
        exit 1
        ;;
esac
