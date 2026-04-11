#!/usr/bin/env bash
# run_deimos.sh — Çalışan Wizard101'in Wine prefix'ini tespit eder ve
#                 Deimos'u AYNI prefix'te başlatır.
#
# KULLANIM:
#   1. Wizard101'i Wine ile KENDIN aç (script bunu YAPMAZ)
#   2. Oyun yüklendikten sonra bu scripti çalıştır
#   3. Script çalışan prosesten WINEPREFIX'i okur ve Deimos'u bağlar
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

# ── Çalışan Wizard101'den WINEPREFIX oku ─────
# macOS'ta çalışan proseslerin ortam değişkenlerini ps ile okuyabiliriz.
_get_wiz_prefix() {
    local pid
    pid=$(pgrep -f "WizardGraphicalClient.exe" 2>/dev/null | head -1)
    if [[ -z "$pid" ]]; then
        echo ""
        return
    fi
    # ps eww ile ortam değişkenlerini al, WINEPREFIX'i çıkar
    ps eww -p "$pid" 2>/dev/null \
        | tr ' ' '\n' \
        | grep '^WINEPREFIX=' \
        | head -1 \
        | cut -d= -f2-
}

echo "[run] Wizard101 aranıyor (çalışan proses)..."

WIZ_PREFIX=""
for i in $(seq 1 12); do
    WIZ_PREFIX=$(_get_wiz_prefix)
    if [[ -n "$WIZ_PREFIX" ]]; then
        echo "[run] Wizard101 bulundu (WINEPREFIX: $WIZ_PREFIX)"
        break
    fi
    echo "[run] Bekleniyor... ($i/12) — Wizard101'i Wine ile açtığından emin ol"
    sleep 5
done

if [[ -z "$WIZ_PREFIX" ]]; then
    echo "[run] HATA: Wizard101 çalışmıyor. Wine ile önce oyunu aç." >&2
    exit 1
fi

# ── Python'u Wizard101 prefix'ine kopyala (henüz yoksa) ──
WIN_PYTHON="$WIZ_PREFIX/drive_c/Python313/python.exe"
if [[ ! -f "$WIN_PYTHON" ]]; then
    echo "[run] Python kopyalanıyor → $WIZ_PREFIX/drive_c/Python313"
    cp -r "$OUR_PYTHON" "$WIZ_PREFIX/drive_c/Python313"
fi

echo "[run] Wine binary : $WINE_BIN"
echo "[run] WINEPREFIX  : $WIZ_PREFIX"

# Aynı prefix → aynı wineserver → Deimos Wizard101'in memory'sine erişebilir
export WINEPREFIX="$WIZ_PREFIX"

# ── Deimos'u başlat ──────────────────────────
echo "[run] Deimos başlatılıyor..."
cd "$DEIMOS_DIR"
"$WINE_BIN" "$WIN_PYTHON" Deimos.py
