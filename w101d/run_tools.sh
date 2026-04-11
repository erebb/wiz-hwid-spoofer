#!/usr/bin/env bash
# run_tools.sh — wiz_tools.py'yi çalışan Wizard101'in Wine prefix'inde başlatır.
#
# KULLANIM:
#   bash run_tools.sh            → menü (mod seçimi)
#   bash run_tools.sh speed 3    → 3x speedhack
#   bash run_tools.sh speed 5    → 5x speedhack
#   bash run_tools.sh quest      → quest TP (Enter ile ışınlan)
#   bash run_tools.sh both 3     → 3x speed + quest TP aynı anda
#
# GEREKSİNİM:
#   1. setup_single.sh çalıştırılmış olmalı
#   2. Wizard101 Wine ile açık olmalı
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Homebrew Wine binary'sini bul ────────────────────────────────────────────
_find_wine_bin() {
    for c in \
        "/opt/homebrew/bin/wine64" "/opt/homebrew/bin/wine" \
        "/usr/local/bin/wine64"    "/usr/local/bin/wine"; do
        [[ -x "$c" ]] && echo "$c" && return
    done
    if command -v brew &>/dev/null; then
        local p; p=$(brew --prefix 2>/dev/null)
        for c in "$p/bin/wine64" "$p/bin/wine"; do
            [[ -x "$c" ]] && echo "$c" && return
        done
    fi
    echo ""
}

WINE_BIN=$(_find_wine_bin)
if [[ -z "$WINE_BIN" ]]; then
    echo "[tools] HATA: Wine bulunamadı. setup_single.sh çalıştırın." >&2
    exit 1
fi

# ── Çalışan Wizard101'den WINEPREFIX oku ─────────────────────────────────────
_get_wiz_prefix() {
    local pid
    pid=$(pgrep -f "WizardGraphicalClient.exe" 2>/dev/null | head -1)
    [[ -z "$pid" ]] && echo "" && return
    ps eww -p "$pid" 2>/dev/null | python3 -c "
import sys, re
txt = sys.stdin.read()
m = re.search(r'WINEPREFIX=(.*?)(?:\s+[A-Z_][A-Z0-9_]*=|\s*\Z)', txt, re.DOTALL)
if m: print(m.group(1).strip())
" 2>/dev/null
}

echo "[tools] Wizard101 aranıyor..."

WIZ_PREFIX=""
for i in $(seq 1 12); do
    WIZ_PREFIX=$(_get_wiz_prefix)
    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[tools] Wizard101 bulundu."
        break
    fi
    echo "[tools] Bekleniyor... ($i/12) — Wizard101'i Wine ile aç"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[tools] HATA: Wizard101 çalışmıyor. Önce oyunu Wine ile aç." >&2
    exit 1
fi

# ── Python ve wiz_tools.py kontrol ───────────────────────────────────────────
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
WIN_TOOLS="$WIZ_PREFIX/drive_c/wiz_tools.py"

if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[tools] HATA: Python bulunamadı → $WIN_PYTHON" >&2
    echo "[tools]       setup_single.sh çalıştırın." >&2
    exit 1
fi

if [[ ! -f "$WIN_TOOLS" ]]; then
    echo "[tools] wiz_tools.py kopyalanıyor..."
    cp "$SCRIPT_DIR/wiz_tools.py" "$WIN_TOOLS"
fi

export WINEPREFIX="$WIZ_PREFIX"

echo "[tools] Wine       : $WINE_BIN"
echo "[tools] WINEPREFIX : $WIZ_PREFIX"
echo ""

# Argümanları olduğu gibi wiz_tools.py'ye ilet
"$WINE_BIN" "$WIN_PYTHON" "$WIN_TOOLS" "$@"
